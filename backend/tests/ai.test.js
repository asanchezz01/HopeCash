import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';

let api;
let token;
let categoryId;
let incomeCategoryId;
let accountId;
let cardId;

/** Simula a resposta do Ollama (/api/chat com structured outputs). */
const ollamaReply = (payload) => vi.fn().mockResolvedValue({
  ok: true,
  json: async () => ({ message: { content: JSON.stringify(payload) } }),
});

/** Simula o servidor Ollama para as rotas de health (/api/version, /api/tags). */
const ollamaServer = ({ version = '0.9.0', models = [] } = {}) => vi.fn().mockImplementation(async (url) => {
  if (String(url).endsWith('/api/version')) return { ok: true, json: async () => ({ version }) };
  if (String(url).endsWith('/api/tags')) return { ok: true, json: async () => ({ models }) };
  return { ok: false, status: 404 };
});

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;

  const cat = await api.post('/api/v1/categories').set(auth(token))
    .send({ name: 'Alimentação', type: 'expense' });
  categoryId = cat.body.data.id;
  const incomeCat = await api.post('/api/v1/categories').set(auth(token))
    .send({ name: 'Salário', type: 'income' });
  incomeCategoryId = incomeCat.body.data.id;
  const acc = await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: 'Corrente', type: 'checking' });
  accountId = acc.body.data.id;
  const card = await api.post('/api/v1/cards').set(auth(token))
    .send({ name: 'Nubank', closing_day: 1, due_day: 10 });
  cardId = card.body.data.id;
});

afterEach(() => vi.unstubAllGlobals());

describe('IA — interpretação de lançamentos por voz', () => {
  it('devolve o lançamento estruturado com ids validados', async () => {
    vi.stubGlobal('fetch', ollamaReply({
      type: 'expense', amount: 45.5, description: 'Mercado',
      date: '2026-07-04', category_id: categoryId, account_id: null,
      card_id: cardId, installments: 3, paid: true, confidence: 'high',
    }));

    const res = await api.post('/api/v1/ai/parse-transaction').set(auth(token))
      .send({ transcript: 'gastei 45 e 50 no mercado ontem no nubank em 3 vezes' });

    expect(res.status).toBe(200);
    const d = res.body.data;
    expect(d.type).toBe('expense');
    expect(d.amount).toBe(45.5);
    expect(d.category_id).toBe(categoryId);
    expect(d.card_id).toBe(cardId);
    expect(d.account_id).toBeNull();
    expect(d.installments).toBe(3);
  });

  it('descarta ids inventados ou de tipo incompatível', async () => {
    vi.stubGlobal('fetch', ollamaReply({
      type: 'expense', amount: 10, description: 'Pipoca',
      date: '2026-07-04', category_id: incomeCategoryId,
      account_id: 'id-inventado', card_id: null,
      installments: 1, paid: true, confidence: 'medium',
    }));

    const res = await api.post('/api/v1/ai/parse-transaction').set(auth(token))
      .send({ transcript: 'dez reais de pipoca' });

    expect(res.status).toBe(200);
    expect(res.body.data.category_id).toBeNull(); // categoria de receita em despesa
    expect(res.body.data.account_id).toBeNull(); // id não pertence ao usuário
  });

  it('responde 503 quando o Ollama está fora do ar', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));

    const res = await api.post('/api/v1/ai/parse-transaction').set(auth(token))
      .send({ transcript: 'gastei 20 reais no uber' });

    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('AI_UNAVAILABLE');
  });

  it('rejeita transcrição vazia', async () => {
    const res = await api.post('/api/v1/ai/parse-transaction').set(auth(token))
      .send({ transcript: ' ' });
    expect(res.status).toBe(422);
  });

  it('re-tenta uma vez após falha de rede transiente', async () => {
    const payload = {
      type: 'expense', amount: 10, description: 'Pipoca', date: '2026-07-04',
      category_id: null, account_id: null, card_id: null,
      installments: 1, paid: true, confidence: 'high',
    };
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new Error('ECONNREFUSED'))
      .mockResolvedValueOnce({ ok: true, json: async () => ({ message: { content: JSON.stringify(payload) } }) });
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.post('/api/v1/ai/parse-transaction').set(auth(token))
      .send({ transcript: 'dez reais de pipoca' });

    expect(res.status).toBe(200);
    expect(res.body.data.amount).toBe(10);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('não re-tenta após timeout (evita dobrar a espera no app)', async () => {
    const timeoutError = new Error('The operation was aborted due to timeout');
    timeoutError.name = 'TimeoutError';
    const fetchMock = vi.fn().mockRejectedValue(timeoutError);
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.post('/api/v1/ai/parse-transaction').set(auth(token))
      .send({ transcript: 'gastei 20 reais no uber' });

    expect(res.status).toBe(503);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe('IA — health', () => {
  it('reporta ok com versão e modelos instalados', async () => {
    vi.stubGlobal('fetch', ollamaServer({
      version: '0.9.2',
      models: [{ name: 'llama3.1:latest', size: 4_900_000_000, details: { parameter_size: '8.0B', family: 'llama' } }],
    }));

    const res = await api.get('/api/v1/ai/health').set(auth(token));

    expect(res.status).toBe(200);
    expect(res.body.data.ok).toBe(true);
    expect(res.body.data.version).toBe('0.9.2');
    expect(res.body.data.installed_models[0].name).toBe('llama3.1:latest');
    expect(res.body.data.configured_models.default).toBeTruthy();
  });

  it('reporta ok=false quando o Ollama está fora do ar (sem erro HTTP)', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));

    const res = await api.get('/api/v1/ai/health').set(auth(token));

    expect(res.status).toBe(200);
    expect(res.body.data.ok).toBe(false);
    expect(res.body.data.error).toBeTruthy();
  });

  it('exige autenticação do app', async () => {
    const res = await api.get('/api/v1/ai/health');
    expect(res.status).toBe(401);
  });

  it('responde também na retaguarda com token próprio', async () => {
    const { access_token } = await loginSuperuser(api);
    vi.stubGlobal('fetch', ollamaServer());

    const res = await api.get('/api/v1/retaguarda/ai/health').set(auth(access_token));

    expect(res.status).toBe(200);
    expect(res.body.data.ok).toBe(true);
  });
});
