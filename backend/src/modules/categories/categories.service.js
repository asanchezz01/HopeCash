import crypto from 'node:crypto';
import { db } from '../../db/knex.js';
import { now } from '../../utils/time.js';

/**
 * Categorias padrão criadas para cada novo usuário. São cópias próprias
 * (is_system = false), então o usuário pode renomear ou excluir livremente.
 */
export const DEFAULT_CATEGORIES = [
  ['Salário', 'income', 'payments', '#2E7D32'],
  ['Renda extra', 'income', 'trending_up', '#388E3C'],
  ['Rendimentos', 'income', 'savings', '#43A047'],
  ['Alimentação', 'expense', 'restaurant', '#E65100'],
  ['Mercado', 'expense', 'shopping_cart', '#F57C00'],
  ['Moradia', 'expense', 'home', '#5D4037'],
  ['Transporte', 'expense', 'directions_car', '#1565C0'],
  ['Saúde', 'expense', 'favorite', '#C62828'],
  ['Educação', 'expense', 'school', '#6A1B9A'],
  ['Lazer', 'expense', 'sports_esports', '#00838F'],
  ['Assinaturas', 'expense', 'subscriptions', '#4527A0'],
  ['Vestuário', 'expense', 'checkroom', '#AD1457'],
  ['Impostos e taxas', 'expense', 'receipt_long', '#455A64'],
  ['Outros', 'expense', 'category', '#616161'],
];

/** Insere as categorias padrão para um usuário e devolve o mapa nome → id. */
export async function insertDefaultCategories(knex, userId) {
  const ts = now();
  const ids = {};
  for (const [name, type, icon, color] of DEFAULT_CATEGORIES) {
    const id = crypto.randomUUID();
    ids[name] = id;
    await knex('categories').insert({
      id, user_id: userId, name, type, icon, color, is_system: false,
      created_at: ts, updated_at: ts, deleted_at: null, version: 1,
    });
  }
  return ids;
}

/** Uma categoria só pode ser excluída se não tiver lançamentos nem orçamentos. */
export async function categoryInUse(categoryId) {
  const tx = await db('transactions')
    .where({ category_id: categoryId }).whereNull('deleted_at').first();
  if (tx) return true;
  const budgetItem = await db('budget_items')
    .where({ category_id: categoryId }).whereNull('deleted_at').first();
  return Boolean(budgetItem);
}
