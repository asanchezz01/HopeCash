import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';

let api;
let token;

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;

  const acc = await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: 'Principal', type: 'checking', initial_balance: 1000 });
  const accountId = acc.body.data.id;
  const month = new Date().toISOString().slice(0, 7);

  await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'income', description: 'Salário', amount: 5000,
    competence_date: `${month}-05`, payment_date: `${month}-05`,
    status: 'paid', account_id: accountId,
  });
  await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'expense', description: 'Aluguel', amount: 2000,
    competence_date: `${month}-10`, payment_date: `${month}-10`,
    status: 'paid', account_id: accountId,
  });
});

describe('Dashboard e fluxo de caixa', () => {
  it('consolida saldo, resultado do mês, patrimônio e score', async () => {
    const res = await api.get('/api/v1/dashboard').set(auth(token));
    expect(res.status).toBe(200);
    const d = res.body.data;
    expect(d.total_balance).toBe(4000); // 1000 + 5000 - 2000
    expect(d.month.income_realized).toBe(5000);
    expect(d.month.expense_realized).toBe(2000);
    expect(d.month.result).toBe(3000);
    expect(d.net_worth).toBe(4000);
    expect(d.health_score).toBeGreaterThan(50);
  });

  it('projeta o fluxo de caixa com períodos e saldo acumulado', async () => {
    const res = await api.get('/api/v1/cashflow?granularity=month').set(auth(token));
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data.periods)).toBe(true);
    expect(typeof res.body.data.opening_balance).toBe('number');
  });
});
