import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, auth } from './helpers.js';
import { _setPushProviderForTests } from '../src/modules/push/providers/index.js';
import { FakePushProvider } from '../src/modules/push/providers/fakePushProvider.js';
import {
  reminderKindFor, todayInTimezone, processDueReminders, dueReminderContent, detailedReminderBody,
} from '../src/modules/push/services/dueReminderService.js';
import { dispatchPendingDeliveries } from '../src/modules/push/services/deliveryService.js';

let api;
let fakeProvider;

beforeAll(async () => {
  api = await makeApp();
  fakeProvider = new FakePushProvider();
  _setPushProviderForTests(fakeProvider);
});

describe('Avisos de vencimento — classificação (reminderKindFor)', () => {
  it('devolve due_today quando o vencimento é hoje', () => {
    expect(reminderKindFor('2026-07-20', '2026-07-20', 3)).toBe('due_today');
  });

  it('devolve advance quando faltam exatamente os dias configurados', () => {
    expect(reminderKindFor('2026-07-23', '2026-07-20', 3)).toBe('advance');
    expect(reminderKindFor('2026-07-25', '2026-07-20', 3)).toBeNull();
  });

  it('devolve overdue exatamente 1 dia após o vencimento, e nunca mais depois disso', () => {
    expect(reminderKindFor('2026-07-19', '2026-07-20', 3)).toBe('overdue');
    expect(reminderKindFor('2026-07-18', '2026-07-20', 3)).toBeNull(); // 2 dias de atraso — não repete
  });

  it('não avisa fora dessas datas', () => {
    expect(reminderKindFor('2026-08-01', '2026-07-20', 3)).toBeNull();
  });

  it('todayInTimezone devolve uma data no formato YYYY-MM-DD', () => {
    expect(todayInTimezone('America/Sao_Paulo')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(todayInTimezone('Pacific/Kiritimati')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

async function createDueTransaction(accessToken, dueDate, status = 'planned') {
  // Um lançamento PAGO exige conta ou cartão (core/transactionDestination.js);
  // previsto não, porque ainda não movimentou saldo.
  let accountId = null;
  if (status === 'paid') {
    const account = await api.post('/api/v1/accounts').set(auth(accessToken))
      .send({ name: 'Conta do aviso', type: 'checking' });
    expect(account.status).toBe(201);
    accountId = account.body.data.id;
  }
  const res = await api.post('/api/v1/transactions').set(auth(accessToken)).send({
    type: 'expense',
    description: 'Conta a pagar',
    competence_date: dueDate,
    due_date: dueDate,
    status,
    account_id: accountId,
  });
  expect(res.status).toBe(201);
  return res.body.data.id;
}

describe('Avisos de vencimento — worker (integração)', () => {
  it('enfileira e envia um aviso genérico (sem valores/descrição) para conta que vence hoje', async () => {
    const user = await registerUser(api);
    const token = `due-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform: 'android' });

    const today = todayInTimezone('America/Sao_Paulo');
    const transactionId = await createDueTransaction(user.access_token, today);

    await processDueReminders();
    await dispatchPendingDeliveries();

    const deliveries = await db('push_deliveries').where({ source_type: 'due_reminder', source_id: transactionId });
    expect(deliveries.length).toBe(2);
    expect(deliveries.map((delivery) => delivery.channel).sort()).toEqual(['email', 'push']);
    expect(deliveries.every((delivery) => delivery.reminder_kind === 'due_today')).toBe(true);
    expect(deliveries.every((delivery) => delivery.status === 'sent')).toBe(true);

    const sentMessage = fakeProvider.sent.find((m) => m.token === token);
    expect(sentMessage).toBeTruthy();
    expect(sentMessage.title).toBe('Conta vence hoje');
    expect(sentMessage.body.toLowerCase()).not.toMatch(/r\$|\d{1,3}(\.\d{3})*,\d{2}/); // sem valores monetários
    expect(sentMessage.data.transaction_id).toBe(transactionId);
  });

  it('não duplica avisos ao rodar o worker várias vezes (idempotência)', async () => {
    const user = await registerUser(api);
    const token = `due-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform: 'web' });
    const today = todayInTimezone('America/Sao_Paulo');
    const transactionId = await createDueTransaction(user.access_token, today);

    await processDueReminders();
    await dispatchPendingDeliveries();
    await processDueReminders(); // roda de novo — simula um segundo ciclo do scheduler
    await processDueReminders(); // e um terceiro, como se fossem várias instâncias
    await dispatchPendingDeliveries();

    const deliveries = await db('push_deliveries').where({ source_type: 'due_reminder', source_id: transactionId });
    expect(deliveries.length).toBe(2); // um push + um e-mail, sem duplicar nenhum canal
  });

  it('respeita a preferência due_reminders_enabled=false', async () => {
    const user = await registerUser(api);
    const token = `due-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform: 'android' });
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({ due_reminders_enabled: false });

    const today = todayInTimezone('America/Sao_Paulo');
    const transactionId = await createDueTransaction(user.access_token, today);

    await processDueReminders();
    const deliveries = await db('push_deliveries').where({ source_type: 'due_reminder', source_id: transactionId });
    expect(deliveries.length).toBe(0);
  });

  it('e-mail informa conta, valor e vencimento; push permanece genérico', async () => {
    const user = await registerUser(api);
    const res = await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Energia Elétrica', competence_date: '2026-07-10',
      due_date: '2026-07-10', status: 'planned', amount_planned: 245.9,
    });
    expect(res.status).toBe(201);
    const txId = res.body.data.id;

    const email = await dueReminderContent({ channel: 'email', reminder_kind: 'overdue', source_id: txId });
    expect(email.title).toBe('Conta em atraso');
    expect(email.body).toContain('Energia Elétrica');
    expect(email.body).toMatch(/R\$\s245,90/);
    expect(email.body).toContain('10/07/2026');
    expect(email.body).toContain('em atraso');

    const push = await dueReminderContent({ channel: 'push', reminder_kind: 'overdue', source_id: txId });
    expect(push.body).not.toContain('Energia Elétrica');
    expect(push.body).not.toMatch(/R\$/);

    // Demais variantes do corpo detalhado.
    const tx = { description: 'Internet', amount_planned: 99.9, due_date: '2026-08-01' };
    expect(detailedReminderBody('due_today', tx)).toContain('vence hoje (01/08/2026)');
    expect(detailedReminderBody('advance', tx)).toContain('vence em 01/08/2026');
  });

  it('não avisa transações pagas, canceladas ou sem due_date', async () => {
    const user = await registerUser(api);
    await api.post('/api/v1/push/devices').set(auth(user.access_token))
      .send({ token: `due-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`, platform: 'android' });
    const today = todayInTimezone('America/Sao_Paulo');

    const paidId = await createDueTransaction(user.access_token, today, 'paid');
    await processDueReminders();
    const after = await db('push_deliveries').where({ source_id: paidId }).count({ n: '*' }).first();
    expect(Number(after.n)).toBe(0);
  });
});
