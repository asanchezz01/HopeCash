import crypto from 'node:crypto';
import { describe, it, expect, beforeEach } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, auth } from './helpers.js';
import { now, today } from '../src/utils/time.js';
import { callTool } from '../src/modules/ai/tools/index.js';

let api;

/**
 * Um lançamento sem conta nem cartão não afeta saldo nenhum — vira registro
 * órfão no extrato. Aconteceu de verdade via ChatGPT em 2026-08-07 (uma
 * "Academia" de R$ 120 ficou com account_id nulo na conta da Nicole), então
 * `create_transaction` passou a garantir sempre um destino.
 */
async function setup({ accounts }) {
  const user = await registerUser(api);
  const row = await db('users').where({ email: user.email }).first();
  const authContext = {
    userId: row.id,
    email: user.email,
    familyIds: [],
    familyRoles: {},
    actorId: null,
    readOnly: false,
  };

  const conversationId = crypto.randomUUID();
  const ts = now();
  await db('ai_conversations').insert({
    id: conversationId, user_id: row.id, title: 'Hope MCP', created_at: ts, updated_at: ts,
  });

  const created = {};
  for (const account of accounts) {
    const res = await api.post('/api/v1/accounts').set(auth(user.access_token)).send({
      name: account.name, type: account.type, initial_balance: 0,
    });
    expect(res.status).toBe(201);
    created[account.name] = res.body.data.id;
    if (account.inactive) {
      await db('bank_accounts').where({ id: res.body.data.id }).update({ is_active: false });
    }
  }

  return { authContext, conversationId, accounts: created, token: user.access_token };
}

const createTransaction = (ctx, params) => callTool(
  'create_transaction',
  ctx.authContext,
  { type: 'expense', description: 'Academia', amount: 120, date: today(), ...params },
  { conversationId: ctx.conversationId },
);

beforeEach(async () => {
  api = await makeApp();
});

describe('create_transaction — conta de destino obrigatória', () => {
  it('sem conta informada, cai na conta corrente e avisa', async () => {
    const ctx = await setup({ accounts: [{ name: 'Nubank', type: 'checking' }] });

    const result = await createTransaction(ctx, {});

    expect(result.action.payload.account_id).toBe(ctx.accounts.Nubank);
    expect(result.assumed_account).toEqual({
      name: 'Nubank',
      reason: 'nenhuma conta foi informada',
    });
  });

  it('com conta inexistente, cai na padrão em vez de falhar', async () => {
    const ctx = await setup({ accounts: [{ name: 'Nubank', type: 'checking' }] });

    const result = await createTransaction(ctx, { account_id: 'Banco Inventado' });

    expect(result.action.payload.account_id).toBe(ctx.accounts.Nubank);
    expect(result.assumed_account.reason).toContain('Banco Inventado');
  });

  it('com conta informada e válida, não assume nada', async () => {
    const ctx = await setup({
      accounts: [{ name: 'Nubank', type: 'checking' }, { name: 'Carteira', type: 'wallet' }],
    });

    const result = await createTransaction(ctx, { account_id: 'Carteira' });

    expect(result.action.payload.account_id).toBe(ctx.accounts.Carteira);
    expect(result.assumed_account).toBeNull();
  });

  it('prefere conta corrente à carteira quando não sabe qual usar', async () => {
    const ctx = await setup({
      accounts: [{ name: 'Carteira', type: 'wallet' }, { name: 'Itaú', type: 'checking' }],
    });

    const result = await createTransaction(ctx, {});

    expect(result.action.payload.account_id).toBe(ctx.accounts['Itaú']);
  });

  it('nunca escolhe conta de investimento como destino padrão', async () => {
    const ctx = await setup({
      accounts: [{ name: 'Tesouro', type: 'investment' }, { name: 'Dinheiro', type: 'cash' }],
    });

    const result = await createTransaction(ctx, {});

    expect(result.action.payload.account_id).toBe(ctx.accounts.Dinheiro);
  });

  it('ignora conta inativa', async () => {
    const ctx = await setup({
      accounts: [
        { name: 'Antiga', type: 'checking', inactive: true },
        { name: 'Atual', type: 'digital' },
      ],
    });

    const result = await createTransaction(ctx, {});

    expect(result.action.payload.account_id).toBe(ctx.accounts.Atual);
  });

  it('sem nenhuma conta utilizável, recusa com instrução clara', async () => {
    const ctx = await setup({ accounts: [{ name: 'Tesouro', type: 'investment' }] });

    await expect(createTransaction(ctx, {})).rejects.toThrow(/cadastrar uma conta/i);
  });

  it('via MCP o aviso da conta assumida volta na resposta da tool', async () => {
    const ctx = await setup({ accounts: [{ name: 'Nubank', type: 'checking' }] });
    const pat = await api.post('/api/v1/pat').set(auth(ctx.token))
      .send({ name: 'ChatGPT', kind: 'mcp_write' });
    expect(pat.status).toBe(201);

    const res = await api.post('/api/v1/ai/mcp').set(auth(pat.body.data.token)).send({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'create_transaction',
        arguments: { type: 'expense', description: 'Academia', amount: 120, date: today() },
      },
    });

    expect(res.status).toBe(200);
    const payload = JSON.parse(res.body.result.content[0].text);
    // O host executa sem card de confirmação, então o aviso tem que viajar no
    // resultado — é a única chance de o usuário saber qual conta foi usada.
    expect(payload.status).toBe('confirmed');
    expect(payload.assumed_account.name).toBe('Nubank');
    expect(payload.notice).toContain('Nubank');

    const tx = await db('transactions').where({ user_id: ctx.authContext.userId }).first();
    expect(tx.account_id).toBe(ctx.accounts.Nubank);
  });

  it('compra no cartão continua sem conta — o destino é a fatura', async () => {
    const ctx = await setup({ accounts: [{ name: 'Nubank', type: 'checking' }] });
    const card = await api.post('/api/v1/cards').set(auth(ctx.token)).send({
      name: 'Cartão Hope', limit_amount: 5000, closing_day: 25, due_day: 5,
    });
    expect(card.status).toBe(201);

    const result = await createTransaction(ctx, { card_id: 'Cartão Hope' });

    expect(result.action.payload.card_id).toBe(card.body.data.id);
    expect(result.action.payload.account_id).toBeNull();
    expect(result.assumed_account).toBeNull();
  });
});
