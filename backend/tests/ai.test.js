import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { config } from '../src/config.js';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';

let api;
let token;
let categoryId;
let incomeCategoryId;
let accountId;
let cardId;

/** Simula a resposta Groq (/chat/completions com structured outputs). */
const groqReply = (payload) => vi.fn().mockResolvedValue({
  ok: true,
  json: async () => ({ choices: [{ message: { role: 'assistant', content: JSON.stringify(payload) } }] }),
});

/** Simula a listagem de modelos do Groq. */
const groqServer = ({ models = [...new Set(Object.values(config.llm.models))] } = {}) => vi.fn().mockImplementation(async (url) => {
  if (String(url).endsWith('/models')) return { ok: true, json: async () => ({ data: models.map((id) => ({ id, active: true })) }) };
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

afterEach(() => {
  config.ai.enabled = true;
  vi.unstubAllGlobals();
});

describe('IA — interpretação de lançamentos por voz', () => {
  it('devolve o lançamento estruturado com ids validados', async () => {
    vi.stubGlobal('fetch', groqReply({
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
    vi.stubGlobal('fetch', groqReply({
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

  it('responde 503 quando o Groq está fora do ar', async () => {
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
      .mockResolvedValueOnce({ ok: true, json: async () => ({ choices: [{ message: { content: JSON.stringify(payload) } }] }) });
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
  it('não consulta provedor externo quando a Hope está desabilitada', async () => {
    config.ai.enabled = false;
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.get('/api/v1/ai/health').set(auth(token));

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({ ok: false, disabled: true, reason: 'AI_DISABLED' });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('reporta ok com os modelos configurados disponíveis', async () => {
    vi.stubGlobal('fetch', groqServer());

    const res = await api.get('/api/v1/ai/health').set(auth(token));

    expect(res.status).toBe(200);
    expect(res.body.data.ok).toBe(true);
    expect(res.body.data.provider).toBe('groq');
    expect(res.body.data.installed_models[0].name).toBeTruthy();
    expect(res.body.data.configured_models.default).toBeTruthy();
  });

  it('reporta ok=false quando o Groq está fora do ar (sem erro HTTP)', async () => {
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
    vi.stubGlobal('fetch', groqServer());

    const res = await api.get('/api/v1/retaguarda/ai/health').set(auth(access_token));

    expect(res.status).toBe(200);
    expect(res.body.data.ok).toBe(true);
  });
});
