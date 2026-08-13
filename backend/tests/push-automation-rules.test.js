import { describe, it, expect, beforeAll, vi } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';
import { _setPushProviderForTests } from '../src/modules/push/providers/index.js';
import { FakePushProvider } from '../src/modules/push/providers/fakePushProvider.js';
import { processDueReminders, todayInTimezone } from '../src/modules/push/services/dueReminderService.js';
import { processTips } from '../src/modules/push/services/tipService.js';
import { processFinancialInsights } from '../src/modules/push/services/financialInsightService.js';
import { dispatchPendingDeliveries } from '../src/modules/push/services/deliveryService.js';
import { llm } from '../src/modules/ai/llm.js';

let api;
let fakeProvider;

/** N dias após uma data YYYY-MM-DD, em aritmética UTC pura (mesma base usada por reminderKindFor). */
function addDaysToIsoDate(isoDate, days) {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

beforeAll(async () => {
  api = await makeApp();
  fakeProvider = new FakePushProvider();
  _setPushProviderForTests(fakeProvider);
});

async function makeAdmin() {
  const { access_token: superToken } = await loginSuperuser(api);
  const email = `adm-auto-${Date.now()}-${Math.random().toString(36).slice(2)}@test.dev`;
  await api.post('/api/v1/retaguarda/users').set(auth(superToken))
    .send({ name: 'Operador Automação', email, password: 'Senha123!', role: 'admin' });
  const login = await api.post('/api/v1/retaguarda/auth/login').send({ email, password: 'Senha123!' });
  return login.body.data.access_token;
}

async function withDevice(platform = 'android') {
  const user = await registerUser(api);
  const token = `auto-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform });
  return { user, token };
}

/**
 * Lançamento PAGO exige conta ou cartão (core/transactionDestination.js).
 * Estes testes só se importam com categoria/valor, então usam uma conta
 * descartável só para satisfazer o destino.
 */
async function accountFor(accessToken) {
  const res = await api.post('/api/v1/accounts').set(auth(accessToken))
    .send({ name: 'Conta do teste', type: 'checking' });
  expect(res.status).toBe(201);
  return res.body.data.id;
}

describe('Retaguarda — regras de mensagens automáticas: listagem e autorização', () => {
  it('lista as três regras padrão e bloqueia edição para admin', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const adminToken = await makeAdmin();

    const list = await api.get('/api/v1/retaguarda/automation-rules').set(auth(superToken));
    expect(list.status).toBe(200);
    const types = list.body.data.map((r) => r.message_type).sort();
    expect(types).toEqual(['due_reminder', 'financial_insight', 'tip']);
    for (const rule of list.body.data) {
      expect(rule.enabled).toBeTruthy();
      expect(rule.frequency_days).toBeGreaterThan(0);
    }

    const listAsAdmin = await api.get('/api/v1/retaguarda/automation-rules').set(auth(adminToken));
    expect(listAsAdmin.status).toBe(200); // leitura liberada para admin

    const editAsAdmin = await api.put('/api/v1/retaguarda/automation-rules/tip')
      .set(auth(adminToken)).send({ enabled: false });
    expect(editAsAdmin.status).toBe(403);
  });

  it('rejeita tipo de mensagem desconhecido', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const res = await api.put('/api/v1/retaguarda/automation-rules/nao-existe')
      .set(auth(superToken)).send({ enabled: false });
    expect(res.status).toBe(404);
  });
});

describe('Avisos de vencimento — controlados pela regra de automação', () => {
  it('desligar a regra impede qualquer aviso, mesmo com preferência do usuário ligada', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    const today = todayInTimezone('America/Sao_Paulo');
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Conta a pagar', competence_date: today, due_date: today, status: 'planned',
    });

    const disabled = await api.put('/api/v1/retaguarda/automation-rules/due_reminder')
      .set(auth(superToken)).send({ enabled: false });
    expect(disabled.status).toBe(200);
    expect(!!disabled.body.data.enabled).toBe(false);

    const result = await processDueReminders();
    expect(result.disabled).toBe(true);
    expect(result.enqueued).toBe(0);

    await dispatchPendingDeliveries();
    expect(fakeProvider.sent.some((m) => m.token === token)).toBe(false);

    // Religa para não afetar os demais testes deste arquivo.
    await api.put('/api/v1/retaguarda/automation-rules/due_reminder').set(auth(superToken)).send({ enabled: true });
  });

  it('a antecedência ajustada na retaguarda vale como padrão para quem não tem preferência própria', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();

    const updated = await api.put('/api/v1/retaguarda/automation-rules/due_reminder')
      .set(auth(superToken)).send({ frequency_days: 5 });
    expect(updated.status).toBe(200);
    expect(updated.body.data.frequency_days).toBe(5);

    // Usuário nunca acessou /push/preferences — sem linha própria, usa o padrão da regra (5 dias).
    const prefsRow = await db('push_preferences').where({ user_id: user.user.id }).first();
    expect(prefsRow).toBeUndefined();

    const todaySp = todayInTimezone('America/Sao_Paulo');
    const dueDate = addDaysToIsoDate(todaySp, 5);
    const createdTx = await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Conta futura', competence_date: dueDate, due_date: dueDate, status: 'planned',
    });
    expect(createdTx.status).toBe(201);

    await processDueReminders();
    await dispatchPendingDeliveries();
    const sent = fakeProvider.sent.find((m) => m.token === token && m.data?.type === 'due_reminder');
    expect(sent).toBeTruthy();
    expect(sent.data.reminder_kind).toBe('advance');

    await api.put('/api/v1/retaguarda/automation-rules/due_reminder').set(auth(superToken)).send({ frequency_days: 3 });
  });
});

describe('Dicas da Hope — worker automático', () => {
  it('gera dica geral por IA com saída pronta para revisão', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const chat = vi.spyOn(llm, 'chatJson').mockResolvedValueOnce({
      title: 'Comece pelo que cabe hoje',
      body: 'Escolha uma despesa recorrente e confirme se ela ainda entrega valor antes da próxima cobrança.',
    });

    const response = await api.post('/api/v1/retaguarda/automation-rules/tip/generate')
      .set(auth(superToken)).send({});

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      title: 'Comece pelo que cabe hoje',
      personalized: false,
      target_user_id: null,
    });
    expect(chat).toHaveBeenCalledOnce();
    chat.mockRestore();
  });

  it('gera dica personalizada com resumo financeiro agregado e sem dados identificáveis', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const user = await registerUser(api, { name: 'Pessoa Privada' });
    const category = await db('categories').where({ user_id: user.user.id, type: 'expense' }).first();
    const month = new Date().toISOString().slice(0, 7);
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Descrição extremamente privada', amount: 321,
      category_id: category.id, competence_date: `${month}-10`, status: 'paid',
      account_id: await accountFor(user.access_token),
    });
    const chat = vi.spyOn(llm, 'chatJson').mockResolvedValueOnce({
      title: 'Dê espaço ao que importa',
      body: 'Revise a categoria que mais pesa no mês e defina um limite simples para a próxima semana.',
    });

    const response = await api.post('/api/v1/retaguarda/automation-rules/tip/generate')
      .set(auth(superToken)).send({ user_id: user.user.id });

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({ personalized: true, target_user_id: user.user.id });
    const call = chat.mock.calls[0][0];
    const prompt = call.messages.map((message) => message.content).join('\n');
    expect(prompt).toContain('321');
    expect(prompt).not.toContain('Pessoa Privada');
    expect(prompt).not.toContain(user.email);
    expect(prompt).not.toContain('Descrição extremamente privada');
    chat.mockRestore();
  });

  it('envia imediatamente uma dica personalizada somente ao usuário escolhido', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const first = await withDevice();
    const second = await withDevice();
    const title = `Dica individual ${Date.now()}`;

    const response = await api.post('/api/v1/retaguarda/automation-rules/tip/send')
      .set(auth(superToken)).send({
        title,
        body: 'Faça uma pequena revisão financeira hoje.',
        user_id: first.user.user.id,
      });

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      category: 'tips', audience: 'selected', recipients_total: 1,
    });
    expect(fakeProvider.sent.some((message) => message.token === first.token && message.title === title)).toBe(true);
    expect(fakeProvider.sent.some((message) => message.token === second.token && message.title === title)).toBe(false);
  });

  it('gera e envia uma dica personalizada, persistindo o conteúdo para todos os canais', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();

    const configured = await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({
      title: 'Dica de contingência', body: 'Corpo usado somente quando a IA falhar.', frequency_days: 30,
    });
    expect(configured.status).toBe(200);

    const generatePersonalizedTip = vi.fn(async ({ userId }) => ({
      title: `Dica para ${userId.slice(0, 8)}`,
      body: 'Revise a categoria que mais pesa no seu mês e escolha um limite possível para esta semana.',
    }));
    const result = await processTips({ generatePersonalizedTip });
    await dispatchPendingDeliveries();
    const messages = fakeProvider.sent.filter((m) => m.token === token && m.data?.type === 'tip');
    expect(messages.length).toBe(1);
    expect(messages[0].title).toBe(`Dica para ${user.user.id.slice(0, 8)}`);
    expect(result.generated).toBeGreaterThan(0);
    expect(result.fallback).toBe(0);

    const deliveries = await db('push_deliveries')
      .where({ source_type: 'tip', user_id: user.user.id })
      .select('notification_content');
    expect(deliveries.length).toBe(2);
    expect(new Set(deliveries.map((row) => row.notification_content)).size).toBe(1);
    expect(JSON.parse(deliveries[0].notification_content)).toMatchObject({
      title: `Dica para ${user.user.id.slice(0, 8)}`,
      data: { type: 'tip' },
    });

    // Roda de novo no mesmo dia — não deve enviar outra (intervalo mínimo de 30 dias).
    const callsBeforeRetry = generatePersonalizedTip.mock.calls.length;
    await processTips({ generatePersonalizedTip });
    await dispatchPendingDeliveries();
    const messagesAfter = fakeProvider.sent.filter((m) => m.token === token && m.data?.type === 'tip');
    expect(messagesAfter.length).toBe(1);
    expect(generatePersonalizedTip.mock.calls.length).toBe(callsBeforeRetry);
  });

  it('usa a dica configurada como contingência quando a IA falha para um usuário', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    const title = `Dica de contingência ${Date.now()}`;
    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({
      title, body: 'Revise hoje uma despesa recorrente e confirme se ela ainda faz sentido.', frequency_days: 30,
    });

    const result = await processTips({
      generatePersonalizedTip: async () => { throw new Error('IA indisponível no teste'); },
    });
    await dispatchPendingDeliveries();

    expect(result.fallback).toBeGreaterThan(0);
    expect(fakeProvider.sent.some((message) => message.token === token && message.title === title)).toBe(true);
    const persisted = await db('push_deliveries')
      .where({ source_type: 'tip', user_id: user.user.id, channel: 'push' })
      .first('notification_content');
    expect(JSON.parse(persisted.notification_content).title).toBe(title);
  });

  it('não envia dica quando a regra está desabilitada', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { token } = await withDevice();
    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({ enabled: false });

    const result = await processTips();
    expect(result.disabled).toBe(true);
    await dispatchPendingDeliveries();
    expect(fakeProvider.sent.some((m) => m.token === token && m.data?.type === 'tip')).toBe(false);

    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({ enabled: true });
  });

  it('não envia dica para quem desativou essa categoria nas preferências', async () => {
    const { user, token } = await withDevice();
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({ tips_enabled: false });

    await processTips({
      generatePersonalizedTip: async () => ({
        title: 'Dica personalizada de teste',
        body: 'Faça uma pequena revisão financeira hoje e escolha uma ação simples para a semana.',
      }),
    });
    await dispatchPendingDeliveries();
    expect(fakeProvider.sent.some((m) => m.token === token && m.data?.type === 'tip')).toBe(false);
  });
});

describe('Insights financeiros — worker automático', () => {
  async function categoryIdFor(userId, type = 'expense') {
    const category = await db('categories').where({ user_id: userId, type }).first();
    return category.id;
  }

  it('detecta orçamento perto do limite e envia o insight configurado', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();

    await api.put('/api/v1/retaguarda/automation-rules/financial_insight').set(auth(superToken)).send({
      title: 'Insight de teste', body: 'Corpo do insight de teste', frequency_days: 30,
      config: { threshold_percent: 80 },
    });

    const currentMonth = new Date().toISOString().slice(0, 7);
    const categoryId = await categoryIdFor(user.user.id);
    const budget = await api.post('/api/v1/budgets').set(auth(user.access_token))
      .send({ reference_month: `${currentMonth}-01` });
    expect(budget.status).toBe(201);
    await api.post('/api/v1/budgets/items').set(auth(user.access_token)).send({
      budget_id: budget.body.data.id, category_id: categoryId, planned_amount: 100,
    });
    // 90% do planejado — acima do limiar de 80% configurado.
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Gasto do mês', amount: 90, category_id: categoryId,
      competence_date: `${currentMonth}-10`, status: 'paid',
      account_id: await accountFor(user.access_token),
    });

    await processFinancialInsights();
    await dispatchPendingDeliveries();
    const message = fakeProvider.sent.find((m) => m.token === token && m.data?.type === 'financial_insight');
    expect(message).toBeTruthy();
    expect(message.title).toBe('Insight de teste');
    expect(message.body).toBe('Corpo do insight de teste');
    // Nunca inclui valores/saldos no conteúdo do push.
    expect(message.body).not.toMatch(/\d/);
    const channels = await db('push_deliveries')
      .where({ source_type: 'financial_insight', user_id: user.user.id })
      .pluck('channel');
    expect(channels.sort()).toEqual(['email', 'push']);
  });

  it('não envia insight quando o orçamento está dentro do limite', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    await api.put('/api/v1/retaguarda/automation-rules/financial_insight').set(auth(superToken))
      .send({ config: { threshold_percent: 80 } });

    const currentMonth = new Date().toISOString().slice(0, 7);
    const categoryId = await categoryIdFor(user.user.id);
    const budget = await api.post('/api/v1/budgets').set(auth(user.access_token))
      .send({ reference_month: `${currentMonth}-01` });
    await api.post('/api/v1/budgets/items').set(auth(user.access_token)).send({
      budget_id: budget.body.data.id, category_id: categoryId, planned_amount: 1000,
    });
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Gasto pequeno', amount: 10, category_id: categoryId,
      competence_date: `${currentMonth}-10`, status: 'paid',
      account_id: await accountFor(user.access_token),
    });

    await processFinancialInsights();
    await dispatchPendingDeliveries();
    expect(fakeProvider.sent.some((m) => m.token === token && m.data?.type === 'financial_insight')).toBe(false);
  });

  it('não envia insight quando a regra está desabilitada', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    await api.put('/api/v1/retaguarda/automation-rules/financial_insight').set(auth(superToken)).send({ enabled: false });

    const currentMonth = new Date().toISOString().slice(0, 7);
    const categoryId = await categoryIdFor(user.user.id);
    const budget = await api.post('/api/v1/budgets').set(auth(user.access_token))
      .send({ reference_month: `${currentMonth}-01` });
    await api.post('/api/v1/budgets/items').set(auth(user.access_token)).send({
      budget_id: budget.body.data.id, category_id: categoryId, planned_amount: 100,
    });
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Gasto do mês', amount: 95, category_id: categoryId,
      competence_date: `${currentMonth}-10`, status: 'paid',
      account_id: await accountFor(user.access_token),
    });

    const result = await processFinancialInsights();
    expect(result.disabled).toBe(true);
    await dispatchPendingDeliveries();
    expect(fakeProvider.sent.some((m) => m.token === token && m.data?.type === 'financial_insight')).toBe(false);

    await api.put('/api/v1/retaguarda/automation-rules/financial_insight').set(auth(superToken)).send({ enabled: true });
  });
});
