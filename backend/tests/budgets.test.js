import { beforeAll, describe, expect, it } from 'vitest';
import { auth, makeApp, registerUser } from './helpers.js';

let api;
let token;

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;
});

describe('Controle orçamentário por conta', () => {
  it('permite a mesma categoria em conta e cartão diferentes e separa o realizado', async () => {
    const account = await api.post('/api/v1/accounts').set(auth(token)).send({
      name: 'Débito', type: 'checking', initial_balance: 0,
    });
    const card = await api.post('/api/v1/cards').set(auth(token)).send({
      name: 'Crédito', closing_day: 1, due_day: 10,
    });
    const category = await api.post('/api/v1/categories').set(auth(token)).send({
      name: 'Mercado dividido', type: 'expense',
    });
    const budget = await api.post('/api/v1/budgets').set(auth(token)).send({
      reference_month: '2026-07-01',
    });

    const debitItem = await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budget.body.data.id,
      category_id: category.body.data.id,
      account_id: account.body.data.id,
      planned_amount: 1000,
    });
    const creditItem = await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budget.body.data.id,
      category_id: category.body.data.id,
      card_id: card.body.data.id,
      planned_amount: 500,
    });

    expect(debitItem.status).toBe(201);
    expect(creditItem.status).toBe(201);
    expect(creditItem.body.data.id).not.toBe(debitItem.body.data.id);

    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Mercado no débito', amount: 320,
      competence_date: '2026-07-10', payment_date: '2026-07-10', status: 'paid',
      account_id: account.body.data.id, category_id: category.body.data.id,
    });
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Mercado no crédito', amount_planned: 180,
      competence_date: '2026-07-12', status: 'planned',
      card_id: card.body.data.id, category_id: category.body.data.id,
    });

    const summary = await api
      .get(`/api/v1/budgets/${budget.body.data.id}/summary`)
      .set(auth(token));
    expect(summary.status).toBe(200);
    expect(summary.body.data.total_planned).toBe(1500);
    expect(summary.body.data.total_realized).toBe(500);
    expect(summary.body.data.items).toEqual(expect.arrayContaining([
      expect.objectContaining({
        item_id: debitItem.body.data.id,
        account_id: account.body.data.id,
        planned: 1000,
        realized: 320,
      }),
      expect.objectContaining({
        item_id: creditItem.body.data.id,
        card_id: card.body.data.id,
        planned: 500,
        realized: 180,
      }),
    ]));
  });
});
