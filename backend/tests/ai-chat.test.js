import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';
import { addDays, addMonths, today } from '../src/utils/time.js';

let api;
let token;
let salarioId;

/** Corpo de streaming SSE como o Groq devolve (async iterable de bytes). */
const streamBody = (chunks) => (async function* () {
  const enc = new TextEncoder();
  for (const c of chunks) yield enc.encode(`data: ${JSON.stringify(c)}\n\n`);
  yield enc.encode('data: [DONE]\n\n');
})();

/** Cada chamada ao fetch consome a próxima sequência de chunks. */
const groqStream = (...calls) => {
  let i = 0;
  return vi.fn().mockImplementation(async () => ({
    ok: true,
    body: streamBody(calls[Math.min(i++, calls.length - 1)]),
  }));
};

const toolCallRound = (name, args = {}) => [
  { choices: [{ delta: { role: 'assistant', tool_calls: [{ index: 0, id: `call_${name}`, type: 'function', function: { name, arguments: JSON.stringify(args) } }] }, finish_reason: null }] },
  { choices: [{ delta: {}, finish_reason: 'tool_calls' }] },
];

const textRound = (...parts) => [
  ...parts.map((text) => ({ choices: [{ delta: { content: text }, finish_reason: null }] })),
  { choices: [{ delta: {}, finish_reason: 'stop' }] },
];

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;

  const acc = await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: 'Corrente', type: 'checking', initial_balance: 1000 });
  const salario = await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'income', description: 'Salário', amount: 4000,
    competence_date: today(), payment_date: today(),
    status: 'paid', account_id: acc.body.data.id,
  });
  salarioId = salario.body.data.id;
  const card = await api.post('/api/v1/cards').set(auth(token))
    .send({ name: 'Crédito', closing_day: 5, due_day: 12 });
  await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'expense', description: 'Compra recente no crédito', amount_planned: 123.45,
    competence_date: addDays(today(), -3), card_id: card.body.data.id,
  });
  // Compra parcelada com todas as parcelas em meses futuros: não pode aparecer
  // em perguntas por "últimas despesas".
  await api.post('/api/v1/transactions/installments').set(auth(token)).send({
    type: 'expense', description: 'Notebook parcelado', competence_date: today(),
    total_amount: 3000, installments: 10, first_due_date: addMonths(today(), 1),
    card_id: card.body.data.id,
  });
});

afterEach(() => vi.unstubAllGlobals());

describe('Chat da Hope — agente com tools (SSE)', () => {
  let conversationId;

  it('executa a tool pedida pelo modelo e transmite a resposta em SSE', async () => {
    vi.stubGlobal('fetch', groqStream(
      toolCallRound('get_balances'),
      textRound('Seu saldo total é ', '**R$ 5.000,00**.'),
    ));

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'qual é o meu saldo?' });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/event-stream');
    expect(res.text).toContain('event: meta');
    expect(res.text).toContain('event: tool');
    expect(res.text).toContain('get_balances');
    expect(res.text).toContain('event: delta');
    expect(res.text).toContain('Seu saldo total é ');
    expect(res.text).toContain('event: done');

    conversationId = JSON.parse(
      res.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;
    expect(conversationId).toBeTruthy();
  });

  it('persistiu a conversa com título, mensagens e log de tools', async () => {
    const list = await api.get('/api/v1/ai/conversations').set(auth(token));
    expect(list.status).toBe(200);
    const convo = list.body.data.find((c) => c.id === conversationId);
    expect(convo.title).toBe('qual é o meu saldo?');

    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    expect(detail.status).toBe(200);
    const messages = detail.body.data.messages;
    expect(messages).toHaveLength(2);
    expect(messages[0]).toMatchObject({ role: 'user', content: 'qual é o meu saldo?' });
    expect(messages[1].role).toBe('assistant');
    expect(messages[1].content).toBe('Seu saldo total é **R$ 5.000,00**.');
    expect(messages[1].tool_calls[0].name).toBe('get_balances');
    // A tool executou de verdade: o resultado registrado tem o saldo real.
    expect(messages[1].tool_calls[0].result).toContain('5000');
  });

  it('continua a mesma conversa mantendo o histórico', async () => {
    vi.stubGlobal('fetch', groqStream(
      toolCallRound('get_balances'),
      textRound('Claro! Posso detalhar por conta.'),
    ));

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ conversation_id: conversationId, message: 'pode detalhar?' });
    expect(res.status).toBe(200);
    expect(res.text).toContain('Claro! Posso detalhar por conta.');

    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    expect(detail.body.data.messages).toHaveLength(4);
  });

  it('erro de tool vira dado para o modelo se corrigir, sem derrubar o stream', async () => {
    vi.stubGlobal('fetch', groqStream(
      toolCallRound('list_transactions', { type: 'invalido' }),
      toolCallRound('list_transactions', { type: 'expense' }),
      textRound('Não consegui filtrar por esse tipo.'),
    ));

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'minhas transações do tipo X' });
    expect(res.status).toBe(200);
    expect(res.text).toContain('event: done');
    expect(res.text).toContain('Não consegui filtrar por esse tipo.');
  });

  it('roteia consulta diária vazia sem permitir que o modelo invente resultados', async () => {
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'teve alguma despesa com farmácia hoje?' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('event: tool');
    expect(res.text).toContain('Não encontrei despesas com farmácia hoje.');
    expect(res.text).not.toContain('R$ 150,00');
    expect(model).not.toHaveBeenCalled();

    const conversationId = JSON.parse(
      res.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;
    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    const assistant = detail.body.data.messages.find((message) => message.role === 'assistant');
    expect(assistant.tool_calls).toHaveLength(1);
    expect(assistant.tool_calls[0]).toMatchObject({ name: 'list_transactions' });
    expect(assistant.tool_calls[0].result).toContain('"count":0');
  });

  it('repete lançamentos de hoje com roteamento determinístico nas duas consultas', async () => {
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const first = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'quais os lançamentos de hoje?' });
    expect(first.status).toBe(200);
    expect(first.text).toContain('Salário');
    expect(first.text).toContain('event: tool');
    const routedConversationId = JSON.parse(
      first.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;

    const second = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ conversation_id: routedConversationId, message: 'quais os lançamentos de hoje?' });
    expect(second.status).toBe(200);
    expect(second.text).toContain('Salário');
    expect(second.text).not.toContain('Não consegui consultar dados suficientes');
    expect(model).not.toHaveBeenCalled();

    const detail = await api.get(`/api/v1/ai/conversations/${routedConversationId}`).set(auth(token));
    const assistantMessages = detail.body.data.messages.filter((message) => message.role === 'assistant');
    expect(assistantMessages).toHaveLength(2);
    expect(assistantMessages.every((message) => message.tool_calls[0].name === 'list_transactions')).toBe(true);
  });

  it('lista qualquer cartão de crédito nos últimos 7 dias sem usar o nome genérico como card_id', async () => {
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const res = await api.post('/api/v1/ai/chat').set(auth(token)).send({
      message: 'liste os lançamentos no cartão de crédito nos ultimos 7 dias.',
    });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Compra recente no crédito');
    expect(res.text).toContain('nos últimos 7 dias');
    expect(res.text).not.toContain('Não consegui consultar dados suficientes');
    expect(model).not.toHaveBeenCalled();

    const conversationId = JSON.parse(
      res.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;
    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    const assistant = detail.body.data.messages.find((message) => message.role === 'assistant');
    expect(assistant.tool_calls[0]).toMatchObject({
      name: 'list_transactions',
      arguments: {
        from: addDays(today(), -6), to: today(), on_credit_card: true,
      },
    });
  });

  it('"últimas despesas no cartão" traz só lançamentos até hoje, sem parcelas futuras', async () => {
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'quais as últimas despesas no cartão de crédito?' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Despesas no cartão de crédito mais recentes');
    expect(res.text).toContain('Compra recente no crédito');
    expect(res.text).not.toContain('Notebook parcelado');
    expect(model).not.toHaveBeenCalled();

    const conversationId = JSON.parse(
      res.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;
    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    const assistant = detail.body.data.messages.find((message) => message.role === 'assistant');
    expect(assistant.tool_calls[0]).toMatchObject({
      name: 'list_transactions',
      arguments: { to: today(), on_credit_card: true, type: 'expense' },
    });
  });

  it('"quanto recebi este mês" responde o total do mês sem chamar o modelo', async () => {
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'Quanto recebi este mês?' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Receitas este mês');
    // Intl.NumberFormat usa espaço não separável entre "R$" e o valor.
    expect(res.text).toContain('4.000,00');
    expect(res.text).not.toContain('Não consegui consultar dados suficientes');
    expect(model).not.toHaveBeenCalled();

    const conversationId = JSON.parse(
      res.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;
    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    const assistant = detail.body.data.messages.find((message) => message.role === 'assistant');
    expect(assistant.tool_calls[0]).toMatchObject({
      name: 'spending_by_category',
      arguments: { from: `${today().slice(0, 7)}-01`, type: 'income' },
    });
  });

  it('"Quanto gastei este mês?" sem lançamentos diz que não encontrou, sem modelo', async () => {
    const fresh = await registerUser(api);
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const res = await api.post('/api/v1/ai/chat').set(auth(fresh.access_token))
      .send({ message: 'Quanto gastei este mês?' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Não encontrei despesas neste mês.');
    expect(model).not.toHaveBeenCalled();
  });

  it('erro de nome não encontrado libera pergunta de esclarecimento em vez do fallback', async () => {
    vi.stubGlobal('fetch', groqStream(
      toolCallRound('create_transaction', {
        type: 'expense', description: 'Teste', amount: 80,
        date: today(), account_id: 'Conta Inexistente',
      }),
      textRound('Não encontrei essa conta. Você quis dizer Corrente?'),
    ));

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'crie uma despesa de 80 reais na conta inexistente' });

    expect(res.status).toBe(200);
    expect(res.text).toContain('Você quis dizer Corrente?');
    expect(res.text).not.toContain('Não consegui consultar dados suficientes');
  });

  it('lançamentos citados no roteamento determinístico viram referências clicáveis', async () => {
    const model = vi.fn().mockRejectedValue(new Error('O modelo não deveria ser chamado'));
    vi.stubGlobal('fetch', model);

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'quais os lançamentos de hoje?' });
    expect(res.status).toBe(200);
    expect(res.text).toContain('event: references');
    expect(res.text).toContain(salarioId);

    const conversationId = JSON.parse(
      res.text.split('event: meta\ndata: ')[1].split('\n')[0],
    ).conversation_id;
    const detail = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    const assistant = detail.body.data.messages.find((message) => message.role === 'assistant');
    expect(assistant.references).toContainEqual({ id: salarioId, label: 'Salário' });
  });

  it('Groq fora do ar → evento de erro no stream (nunca 5xx)', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));

    const res = await api.post('/api/v1/ai/chat').set(auth(token))
      .send({ message: 'oi' });
    expect(res.status).toBe(200);
    expect(res.text).toContain('event: error');
    expect(res.text).not.toContain('event: done');
  });

  it('valida a mensagem antes de abrir o stream', async () => {
    const res = await api.post('/api/v1/ai/chat').set(auth(token)).send({ message: ' ' });
    expect(res.status).toBe(422);
  });

  it('conversa de outro usuário é invisível (404) e exclusão é definitiva', async () => {
    const other = await registerUser(api);
    const crossed = await api.get(`/api/v1/ai/conversations/${conversationId}`)
      .set(auth(other.access_token));
    expect(crossed.status).toBe(404);

    const del = await api.delete(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    expect(del.status).toBe(200);
    const gone = await api.get(`/api/v1/ai/conversations/${conversationId}`).set(auth(token));
    expect(gone.status).toBe(404);
  });
});
