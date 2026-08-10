import crypto from 'node:crypto';
import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';
import { DEFAULT_CATEGORIES } from '../src/modules/categories/categories.service.js';

let api;
let token;

const listCategories = async () => {
  const res = await api.get('/api/v1/categories?limit=100').set(auth(token));
  expect(res.status).toBe(200);
  return res.body.data;
};

const findByName = async (name) => {
  const cat = (await listCategories()).find((c) => c.name === name);
  expect(cat).toBeDefined();
  return cat;
};

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;
});

describe('Categorias padrão por usuário', () => {
  it('registro cria cópias próprias das categorias padrão (não is_system)', async () => {
    const categories = await listCategories();
    const names = categories.map((c) => c.name);
    for (const [name] of DEFAULT_CATEGORIES) expect(names).toContain(name);
    expect(categories.every((c) => !c.is_system)).toBe(true);
  });

  it('usuário novo sem lançamentos consegue excluir categoria padrão', async () => {
    const cat = await findByName('Vestuário');
    const del = await api.delete(`/api/v1/categories/${cat.id}`).set(auth(token));
    expect(del.status).toBe(200);
    const after = await listCategories();
    expect(after.find((c) => c.id === cat.id)).toBeUndefined();
  });
});

describe('Exclusão bloqueada quando há vínculos', () => {
  it('categoria com lançamento não pode ser excluída', async () => {
    const cat = await findByName('Mercado');
    const tx = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Compra do mês',
      competence_date: '2026-07-01', category_id: cat.id,
    });
    expect(tx.status).toBe(201);

    const del = await api.delete(`/api/v1/categories/${cat.id}`).set(auth(token));
    expect(del.status).toBe(409);
    expect(del.body.error.code).toBe('CATEGORY_IN_USE');
  });

  it('categoria com item de orçamento não pode ser excluída', async () => {
    const cat = await findByName('Lazer');
    const budget = await api.post('/api/v1/budgets').set(auth(token))
      .send({ reference_month: '2026-07-01' });
    expect(budget.status).toBe(201);
    const item = await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budget.body.data.id, category_id: cat.id, planned_amount: 300,
    });
    expect(item.status).toBe(201);

    const del = await api.delete(`/api/v1/categories/${cat.id}`).set(auth(token));
    expect(del.status).toBe(409);
    expect(del.body.error.code).toBe('CATEGORY_IN_USE');
  });

  it('push de sincronização rejeita exclusão de categoria em uso', async () => {
    const cat = await findByName('Mercado'); // tem lançamento do teste anterior
    const res = await api.post('/api/v1/sync/push').set(auth(token)).send({
      device_id: 'test-device',
      operations: [{
        operation_id: crypto.randomUUID(),
        entity: 'categories', entity_id: cat.id, op: 'delete',
      }],
    });
    expect(res.status).toBe(200);
    expect(res.body.data.results[0].result).toBe('rejected');
    expect((await listCategories()).find((c) => c.id === cat.id)).toBeDefined();
  });

  it('push de sincronização aplica exclusão de categoria sem vínculos', async () => {
    const cat = await findByName('Educação');
    const res = await api.post('/api/v1/sync/push').set(auth(token)).send({
      device_id: 'test-device',
      operations: [{
        operation_id: crypto.randomUUID(),
        entity: 'categories', entity_id: cat.id, op: 'delete',
        base_version: cat.version,
      }],
    });
    expect(res.status).toBe(200);
    expect(res.body.data.results[0].result).toBe('applied');
    expect((await listCategories()).find((c) => c.id === cat.id)).toBeUndefined();
  });
});
