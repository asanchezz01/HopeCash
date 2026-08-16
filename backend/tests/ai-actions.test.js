import crypto from 'node:crypto';
import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, auth } from './helpers.js';
import { today, now } from '../src/utils/time.js';
import { callTool } from '../src/modules/ai/tools/index.js';

let api;
let token;
let accountId;
let categoryId;
let userId;
let conversationId;
let authContext;

const streamBody = (chunks) => (async function* () {
  const enc = new TextEncoder();
  for (const chunk of chunks) yield enc.encode(`data: ${JSON.stringify(chunk)}\n\n`);
  yield enc.encode('data: [DONE]\n\n');
})();

const groqStream = (...calls) => {
  let index = 0;
  return vi.fn().mockImplementation(async () => ({
    ok: true,
    body: streamBody(calls[Math.min(index++, calls.length - 1)]),
  }));
};

const toolRound = (name, args) => [
  { choices: [{ delta: { role: 'assistant', tool_calls: [{ index: 0, id: `call_${name}`, type: 'function', function: { name, arguments: JSON.stringify(args) } }] }, finish_reason: null }] },
  { choices: [{ delta: {}, finish_reason: 'tool_calls' }] },
];

const textRound = (text) => [
  { choices: [{ delta: { role: 'assistant', content: text }, finish_reason: null }] },
  { choices: [{ delta: {}, finish_reason: 'stop' }] },
];

const eventData = (body, event) => JSON.parse(body.split(`event: ${event}\ndata: `)[1].split('\n')[0]);

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;
  userId = user.user.id;
  authContext = {
    userId,
    email: user.user.email,
    familyIds: [],
    familyRoles: {},
    actorId: null,
    readOnly: false,
  };
  conversationId = crypto.randomUUID();
  const ts = now();
  await db('ai_conversations').insert({
    id: conversationId,
    user_id: userId,
    title: 'Teste das ações',
    created_at: ts,
    updated_at: ts,
  });
  const account = await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: 'Nubank', type: 'checking', initial_balance: 1000 });
  accountId = account.body.data.id;
  const category = await api.post('/api/v1/categories').set(auth(token))
    .send({ name: 'Mercado IA', type: 'expense' });
  categoryId = category.body.data.id;
});

afterEach(() => vi.unstubAllGlobals());

describe('Ações da Hope — confirmação em duas fases', () => {
  const propose = (name, params) => callTool(
    name,
    authContext,
    params,
    { conversationId },
  );

  const confirm = async (proposal) => {
    const res = await api.post(`/api/v1/ai/actions/${proposal.action.id}/confirm`).set(auth(token));
    expect(res.status).toBe(200);
    return res.body.data;
  };

  it('lançamento simples vira proposta pela rota determinística (extração estruturada)', async () => {
    const parseOut = {
      type: 'expense', amount: 50, description: 'Compra de mercado', date: today(),
      category_id: categoryId, account_id: accountId, card_id: null,
      installments: 1, paid: true, confidence: 'high',
    };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [{ message: { content: JSON.stringify(parseOut) } }] }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const chat = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'lança 50 reais de mercado hoje no Nubank' });
    expect(chat.status).toBe(200);
    expect(chat.text).toContain('event: action');
    expect(chat.text).toContain('Confirmar ou Recusar');
    // Uma única chamada ao modelo: a extração estruturada, não o loop de tools.
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const action = eventData(chat.text, 'action');
    expect(action).toMatchObject({ status: 'proposed', tool_name: 'create_transaction' });
    expect(action.summary.title).toBe('Nova despesa');

    const before = await db('transactions').where({ description: 'Compra de mercado' });
    expect(before).toHaveLength(0);

    const confirmed = await api.post(`/api/v1/ai/actions/${action.id}/confirm`).set(auth(token));
    expect(confirmed.status).toBe(200);
    expect(confirmed.body.data.status).toBe('confirmed');
    expect(confirmed.body.data.result).toMatchObject({
      description: 'Compra de mercado', amount: 50, account_id: accountId, category_id: categoryId,
    });

    const duplicate = await api.post(`/api/v1/ai/actions/${action.id}/confirm`).set(auth(token));
    expect(duplicate.status).toBe(400);
    const audit = await db('audit_logs').where({ entity: 'transactions', entity_id: confirmed.body.data.result.id });
    expect(audit.some((row) => row.action === 'create')).toBe(true);
  });

  it('extração indisponível cai para o loop do agente e ainda propõe', async () => {
    // 1ª chamada (parse): resposta sem .json() → erro tratado, rota cai para o loop.
    vi.stubGlobal('fetch', groqStream(
      textRound('consumida pela tentativa de extração'),
      toolRound('create_transaction', {
        type: 'expense', description: 'Padaria', amount: 30,
        date: today(), account_id: 'Nubank', category_id: 'Mercado IA', paid: true,
      }),
      textRound('Revise os dados no card e confirme se estiver tudo certo.'),
    ));

    const chat = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'registra 30 reais de padaria hoje no Nubank' });
    expect(chat.status).toBe(200);
    expect(chat.text).toContain('event: action');
    const action = eventData(chat.text, 'action');
    expect(action).toMatchObject({ status: 'proposed', tool_name: 'create_transaction' });
  });

  it('bloqueia promessa de card e exige pay_transaction em continuação curta', async () => {
    const planned = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Unimed', amount_planned: 3152.63,
      competence_date: today(), due_date: today(), status: 'planned',
      account_id: accountId, category_id: categoryId,
    });

    vi.stubGlobal('fetch', groqStream(
      toolRound('list_transactions', { text: 'Unimed', status: 'planned' }),
      textRound('Encontrei a Unimed. Posso gerar o card para confirmar o pagamento.'),
    ));
    const first = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'analise o lançamento da Unimed' });
    expect(first.status).toBe(200);
    const continuedConversationId = eventData(first.text, 'meta').conversation_id;

    vi.stubGlobal('fetch', groqStream(
      toolRound('list_transactions', { text: 'Unimed', status: 'planned' }),
      textRound('Vou gerar a proposta. Revise o card que aparecerá.'),
      toolRound('pay_transaction', {
        transaction_id: planned.body.data.id,
        amount: 3152.63,
        date: today(),
      }),
      textRound('A proposta foi criada. Revise o card e confirme se estiver tudo certo.'),
    ));
    const second = await api.post('/api/v1/ai/chat').set(auth(token)).send({
      conversation_id: continuedConversationId,
      message: 'tente de novo',
    });

    expect(second.status).toBe(200);
    expect(second.text).toContain('event: action');
    expect(second.text).not.toContain('Vou gerar a proposta');
    const action = eventData(second.text, 'action');
    expect(action).toMatchObject({ status: 'proposed', tool_name: 'pay_transaction' });
    expect(action.summary.title).toBe('Dar baixa no lançamento');
  });

  it('recusar preserva os dados e fica registrado no histórico', async () => {
    vi.stubGlobal('fetch', groqStream(
      toolRound('create_category', { name: 'Pets', type: 'expense' }),
      textRound('A categoria está pronta para sua revisão.'),
    ));
    const chat = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'crie a categoria Pets' });
    const action = eventData(chat.text, 'action');
    const rejected = await api.post(`/api/v1/ai/actions/${action.id}/reject`).set(auth(token));
    expect(rejected.body.data.status).toBe('rejected');
    expect(await db('categories').where({ name: 'Pets' })).toHaveLength(0);

    const conversationId = eventData(chat.text, 'meta').conversation_id;
    const history = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    const assistant = history.body.data.messages.find((message) => message.role === 'assistant');
    expect(assistant.actions[0]).toMatchObject({ id: action.id, status: 'rejected' });
  });

  it('proposta expirada não pode ser confirmada', async () => {
    vi.stubGlobal('fetch', groqStream(
      toolRound('create_goal', { name: 'Viagem', target_amount: 5000 }),
      textRound('Confira a proposta.'),
    ));
    const chat = await api.post('/api/v1/ai/chat').set(auth(token)).send({ message: 'crie uma meta de viagem' });
    const action = eventData(chat.text, 'action');
    await db('ai_actions').where({ id: action.id }).update({ expires_at: '2000-01-01 00:00:00.000' });
    const res = await api.post(`/api/v1/ai/actions/${action.id}/confirm`).set(auth(token));
    expect(res.status).toBe(400);
    expect(res.body.error.message).toContain('expirou');
  });

  it('viewer de família não pode propor escrita familiar', async () => {
    const familyId = crypto.randomUUID();
    await expect(callTool(
      'create_category',
      {
        ...authContext,
        familyIds: [familyId],
        familyRoles: { [familyId]: 'viewer' },
      },
      { name: 'Bloqueada', type: 'expense', family_id: familyId },
      { conversationId },
    )).rejects.toMatchObject({ status: 403 });
  });

  it('executa as demais write tools somente depois da confirmação', async () => {
    const planned = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Conta de teste', amount_planned: 100,
      competence_date: today(), due_date: today(), status: 'planned',
      account_id: accountId, category_id: categoryId,
    });

    const updated = await confirm(await propose('update_transaction', {
      transaction_id: planned.body.data.id,
      description: 'Conta atualizada',
      amount: 100,
    }));
    expect(updated.result.description).toBe('Conta atualizada');

    const paid = await confirm(await propose('pay_transaction', {
      transaction_id: planned.body.data.id,
      amount: 110,
      interest_amount: 10,
      date: today(),
    }));
    expect(paid.result.transaction).toMatchObject({ status: 'paid', amount: 100 });
    expect(paid.result.interest_transaction).toMatchObject({ amount: 10, status: 'paid' });

    const destination = await api.post('/api/v1/accounts').set(auth(token))
      .send({ name: 'Reserva', type: 'savings' });
    const transfer = await confirm(await propose('create_transfer', {
      from_account_id: accountId,
      to_account_id: destination.body.data.id,
      amount: 75,
      date: today(),
    }));
    expect(transfer.result.debit.amount).toBe(75);
    expect(transfer.result.credit.amount).toBe(75);
    expect(transfer.result.debit.transfer_group_id).toBe(transfer.result.credit.transfer_group_id);

    const budget = await confirm(await propose('upsert_budget_item', {
      month: today().slice(0, 7),
      category_id: categoryId,
      planned_amount: 450,
      due_day: Number(today().slice(-2)),
      account_id: accountId,
    }));
    expect(budget.result).toMatchObject({ category_id: categoryId, planned_amount: 450 });

    const card = await api.post('/api/v1/cards').set(auth(token))
      .send({ name: 'Crédito orçamento', closing_day: 1, due_day: 10 });
    const creditBudget = await confirm(await propose('upsert_budget_item', {
      month: today().slice(0, 7),
      category_id: categoryId,
      planned_amount: 250,
      card_id: card.body.data.id,
    }));
    expect(creditBudget.result).toMatchObject({
      category_id: categoryId,
      card_id: card.body.data.id,
      planned_amount: 250,
    });
    expect(creditBudget.result.id).not.toBe(budget.result.id);

    const goal = await confirm(await propose('create_goal', {
      name: 'Reserva da Hope',
      target_amount: 2000,
      linked_account_id: destination.body.data.id,
    }));
    expect(goal.result).toMatchObject({ name: 'Reserva da Hope', accumulated_amount: 0 });

    const contribution = await confirm(await propose('add_goal_contribution', {
      goal_id: goal.result.id,
      amount: 200,
      date: today(),
      account_id: destination.body.data.id,
    }));
    expect(contribution.result.goal.accumulated_amount).toBe(200);
    expect(contribution.result.transaction.description).toBe('Aporte Reserva da Hope');

    const category = await confirm(await propose('create_category', {
      name: 'Categoria pela Hope',
      type: 'expense',
    }));
    expect(category.result).toMatchObject({ name: 'Categoria pela Hope', type: 'expense' });
  });
});
