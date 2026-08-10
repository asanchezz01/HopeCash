import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';

export const searchCategories = {
  name: 'search_categories',
  description: 'Busca categorias pelo nome (correspondência parcial) para resolver o id a partir do que o usuário citou na frase. Inclui categorias padrão do sistema.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      query: { type: 'string', description: 'Trecho do nome da categoria' },
      type: { type: 'string', enum: ['income', 'expense'] },
    },
    required: ['query'],
  },
  paramsSchema: z.object({
    query: z.string().min(1).max(80),
    type: z.enum(['income', 'expense']).optional(),
  }),
  async handler(auth, { query, type }) {
    const q = applyScope(db('categories'), 'categories', auth)
      .whereNull('deleted_at').where('name', 'like', `%${query}%`);
    if (type) q.where('type', type);
    const rows = await q.limit(20).select('id', 'name', 'type', 'icon', 'color');
    return { categories: rows };
  },
};

export const searchAccounts = {
  name: 'search_accounts',
  description: 'Busca contas bancárias ou carteiras pelo nome (correspondência parcial) para resolver o id a partir do que o usuário citou na frase.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: { query: { type: 'string', description: 'Trecho do nome da conta' } },
    required: ['query'],
  },
  paramsSchema: z.object({ query: z.string().min(1).max(80) }),
  async handler(auth, { query }) {
    const rows = await applyScope(db('bank_accounts'), 'bank_accounts', auth)
      .whereNull('deleted_at').where('name', 'like', `%${query}%`)
      .limit(20).select('id', 'name', 'type', 'is_active');
    return { accounts: rows };
  },
};

export default [searchCategories, searchAccounts];
