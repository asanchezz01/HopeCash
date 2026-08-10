import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';

let api;
let token;
let accountId;

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;
  const acc = await api.post('/api/v1/accounts').set(auth(token)).send({
    name: 'Conta Teste', type: 'checking', initial_balance: 1000,
  });
  accountId = acc.body.data.id;
});

describe('Transações', () => {
  it('cria, lista, atualiza e exclui (soft) um lançamento', async () => {
    const created = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense',
      description: 'Mercado',
      amount: 250.5,
      competence_date: '2026-07-01',
      payment_date: '2026-07-01',
      status: 'paid',
      account_id: accountId,
      tags: ['casa', 'essencial'],
    });
    expect(created.status).toBe(201);
    const tx = created.body.data;
    expect(tx.version).toBe(1);
    expect(tx.tags).toEqual(['casa', 'essencial']);

    const list = await api.get('/api/v1/transactions').set(auth(token));
    expect(list.body.data.some((t) => t.id === tx.id)).toBe(true);

    const updated = await api.put(`/api/v1/transactions/${tx.id}`).set(auth(token))
      .send({ description: 'Mercado Central', version: 1 });
    expect(updated.status).toBe(200);
    expect(updated.body.data.version).toBe(2);

    // Versão defasada → 409 (controle otimista).
    const stale = await api.put(`/api/v1/transactions/${tx.id}`).set(auth(token))
      .send({ description: 'Outra coisa', version: 1 });
    expect(stale.status).toBe(409);

    const del = await api.delete(`/api/v1/transactions/${tx.id}`).set(auth(token));
    expect(del.status).toBe(200);
    const after = await api.get(`/api/v1/transactions/${tx.id}`).set(auth(token));
    expect(after.status).toBe(404);
  });

  it('isola dados entre usuários', async () => {
    const other = await registerUser(api);
    const created = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'income', description: 'Salário', amount: 5000,
      competence_date: '2026-07-05', status: 'paid', account_id: accountId,
    });
    const foreign = await api.get(`/api/v1/transactions/${created.body.data.id}`)
      .set(auth(other.access_token));
    expect(foreign.status).toBe(404);
  });

  it('cria compra parcelada com rateio de centavos', async () => {
    const res = await api.post('/api/v1/transactions/installments').set(auth(token)).send({
      type: 'expense',
      description: 'Notebook',
      competence_date: '2026-07-10',
      total_amount: 1000.01,
      installments: 3,
      first_due_date: '2026-08-10',
    });
    expect(res.status).toBe(201);
    const parts = res.body.data.transactions;
    expect(parts).toHaveLength(3);
    const total = parts.reduce((s, p) => s + Number(p.amount_planned), 0);
    expect(Math.round(total * 100)).toBe(100001);
    expect(parts[0].installment_number).toBe(1);
    expect(parts[2].due_date).toBe('2026-10-10');
  });

  it('mantém um lançamento único ao ratear categorias', async () => {
    const created = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'PIX Coagru', amount: 756.57,
      competence_date: '2026-08-01', payment_date: '2026-08-01', status: 'paid', account_id: accountId,
      category_splits: [
        { category_id: '11111111-1111-4111-8111-111111111111', amount: 669.57 },
        { category_id: '22222222-2222-4222-8222-222222222222', amount: 87 },
      ],
    });
    // A referência de categoria é validada pelo schema, não precisa existir
    // para manter compatibilidade com categorias removidas/importadas.
    expect(created.status).toBe(201);
    expect(created.body.data.amount).toBe(756.57);
    expect(created.body.data.category_splits).toEqual([
      { category_id: '11111111-1111-4111-8111-111111111111', amount: 669.57 },
      { category_id: '22222222-2222-4222-8222-222222222222', amount: 87 },
    ]);

    const invalid = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Rateio incorreto', amount: 100,
      competence_date: '2026-08-01', status: 'paid', account_id: accountId,
      category_splits: [{ category_id: '11111111-1111-4111-8111-111111111111', amount: 99 }],
    });
    expect(invalid.status).toBe(400);
  });

  it('faz transferência entre contas e reflete no extrato', async () => {
    const acc2 = await api.post('/api/v1/accounts').set(auth(token)).send({
      name: 'Poupança', type: 'savings', initial_balance: 0,
    });
    const transfer = await api.post('/api/v1/accounts/transfer').set(auth(token)).send({
      from_account_id: accountId,
      to_account_id: acc2.body.data.id,
      amount: 300,
      date: '2026-07-02',
    });
    expect(transfer.status).toBe(201);
    expect(transfer.body.data.debit.transfer_group_id).toBe(transfer.body.data.credit.transfer_group_id);

    const statement = await api.get(`/api/v1/accounts/${acc2.body.data.id}/statement`).set(auth(token));
    expect(statement.status).toBe(200);
    const last = statement.body.data.entries.at(-1);
    expect(last.balance).toBe(300);
  });
});
