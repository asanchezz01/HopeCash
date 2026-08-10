import crypto from 'node:crypto';
import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, auth } from './helpers.js';

let api;

beforeAll(async () => {
  api = await makeApp();
});

async function setup({ withAccount = true } = {}) {
  const user = await registerUser(api);
  let accountId = null;
  if (withAccount) {
    const res = await api.post('/api/v1/accounts').set(auth(user.access_token))
      .send({ name: 'Débito', type: 'checking' });
    expect(res.status).toBe(201);
    accountId = res.body.data.id;
  }
  return { token: user.access_token, accountId };
}

const post = (token, body) => api.post('/api/v1/transactions').set(auth(token)).send({
  type: 'expense', description: 'Academia', amount: 120, competence_date: '2026-08-07', ...body,
});

const push = (token, operations) => api.post('/api/v1/sync/push').set(auth(token))
  .send({ device_id: 'test-device', operations });

describe('Destino do lançamento — REST', () => {
  it('recusa lançamento PAGO sem conta nem cartão', async () => {
    const { token } = await setup();
    const res = await post(token, { status: 'paid' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/conta ou o cartão/i);
  });

  it('aceita lançamento PREVISTO sem destino — ainda não moveu saldo', async () => {
    const { token } = await setup();
    const res = await post(token, { status: 'planned', due_date: '2026-08-20' });
    expect(res.status).toBe(201);
    expect(res.body.data.account_id).toBeNull();
  });

  it('aceita pago com conta', async () => {
    const { token, accountId } = await setup();
    const res = await post(token, { status: 'paid', account_id: accountId });
    expect(res.status).toBe(201);
  });

  it('aceita a baixa de variação de orçamento sem destino', async () => {
    const { token } = await setup();
    const res = await post(token, {
      status: 'paid',
      description: 'Baixa diferença Mercado',
      notes: `hopecash:budget_variance:${JSON.stringify({ amount: 120 })}`,
    });
    expect(res.status).toBe(201);
    expect(res.body.data.account_id).toBeNull();
  });

  it('recusa dar baixa removendo a conta num PUT', async () => {
    const { token, accountId } = await setup();
    const created = await post(token, { status: 'planned' });
    expect(created.status).toBe(201);

    const res = await api.put(`/api/v1/transactions/${created.body.data.id}`)
      .set(auth(token)).send({ status: 'paid' });
    expect(res.status).toBe(400);

    const ok = await api.put(`/api/v1/transactions/${created.body.data.id}`)
      .set(auth(token)).send({ status: 'paid', account_id: accountId });
    expect(ok.status).toBe(200);
  });

  it('patch parcial não exige repetir a conta', async () => {
    const { token, accountId } = await setup();
    const created = await post(token, { status: 'paid', account_id: accountId });

    const res = await api.put(`/api/v1/transactions/${created.body.data.id}`)
      .set(auth(token)).send({ description: 'Academia (mensalidade)' });
    expect(res.status).toBe(200);
    expect(res.body.data.account_id).toBe(accountId);
  });
});

describe('Destino do lançamento — /sync/push', () => {
  // Recusar aqui apagaria um lançamento que o usuário já viu salvo no
  // aparelho, então o servidor completa o destino em vez de rejeitar.
  it('completa com a conta de débito em vez de rejeitar', async () => {
    const { token, accountId } = await setup();
    const id = crypto.randomUUID();

    const res = await push(token, [{
      operation_id: crypto.randomUUID(),
      entity: 'transactions',
      entity_id: id,
      op: 'create',
      payload: {
        type: 'expense', description: 'Salario offline', amount: 1570.17,
        competence_date: '2026-08-03', status: 'paid',
      },
    }]);

    expect(res.status).toBe(200);
    expect(res.body.data.results[0].result).toBe('applied');
    const row = await db('transactions').where({ id }).first();
    expect(row.account_id).toBe(accountId);
  });

  it('preserva o destino quando o cliente informa a conta', async () => {
    const { token, accountId } = await setup();
    const id = crypto.randomUUID();

    await push(token, [{
      operation_id: crypto.randomUUID(),
      entity: 'transactions',
      entity_id: id,
      op: 'create',
      payload: {
        type: 'expense', description: 'Com conta', amount: 10,
        competence_date: '2026-08-03', status: 'paid', account_id: accountId,
      },
    }]);

    const row = await db('transactions').where({ id }).first();
    expect(row.account_id).toBe(accountId);
  });

  it('rejeita quando não há nenhuma conta para completar', async () => {
    const { token } = await setup({ withAccount: false });
    const id = crypto.randomUUID();

    const res = await push(token, [{
      operation_id: crypto.randomUUID(),
      entity: 'transactions',
      entity_id: id,
      op: 'create',
      payload: {
        type: 'expense', description: 'Sem conta nenhuma', amount: 10,
        competence_date: '2026-08-03', status: 'paid',
      },
    }]);

    expect(res.body.data.results[0].result).toBe('rejected');
    expect(await db('transactions').where({ id }).first()).toBeUndefined();
  });

  it('não mexe em lançamento previsto', async () => {
    const { token } = await setup();
    const id = crypto.randomUUID();

    await push(token, [{
      operation_id: crypto.randomUUID(),
      entity: 'transactions',
      entity_id: id,
      op: 'create',
      payload: {
        type: 'expense', description: 'Previsto offline', amount: 10,
        competence_date: '2026-08-03', due_date: '2026-08-20', status: 'planned',
      },
    }]);

    const row = await db('transactions').where({ id }).first();
    expect(row.account_id).toBeNull();
  });
});
