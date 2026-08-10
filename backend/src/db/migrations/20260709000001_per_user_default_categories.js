/**
 * Categorias padrão passam a ser por usuário.
 *
 * Antes, as categorias padrão eram linhas compartilhadas (is_system = true,
 * dono = usuário-sistema) e por isso nenhum usuário podia excluí-las. Agora
 * cada usuário recebe cópias próprias (editáveis/excluíveis), as referências
 * dele são reapontadas para a cópia e as linhas compartilhadas são desativadas
 * via soft delete — o tombstone chega aos dispositivos no próximo pull.
 */
import crypto from 'node:crypto';

const now = () => new Date().toISOString().slice(0, 23).replace('T', ' ');

// Tabelas com colunas que apontam para categorias, reapontadas por usuário.
const CATEGORY_REFS = [
  ['transactions', 'category_id'],
  ['subcategories', 'category_id'],
  ['budget_items', 'category_id'],
  ['debts', 'category_id'],
  ['categorization_rules', 'category_id'],
  ['import_items', 'suggested_category_id'],
];

export async function up(knex) {
  const systemCats = await knex('categories')
    .where({ is_system: true }).whereNull('deleted_at');
  if (!systemCats.length) return;

  const users = await knex('users').whereNull('deleted_at');
  const ts = now();

  for (const user of users) {
    const existing = await knex('categories')
      .where({ user_id: user.id }).whereNull('deleted_at');
    const ownByKey = new Map(
      existing.map((c) => [`${c.type}:${c.name.toLowerCase()}`, c.id]),
    );

    for (const cat of systemCats) {
      // Se o usuário já criou uma categoria homônima, reaproveita em vez de duplicar.
      let ownId = ownByKey.get(`${cat.type}:${cat.name.toLowerCase()}`);
      if (!ownId) {
        ownId = crypto.randomUUID();
        await knex('categories').insert({
          id: ownId, user_id: user.id, family_id: null,
          name: cat.name, type: cat.type, icon: cat.icon, color: cat.color,
          is_system: false, created_at: ts, updated_at: ts, deleted_at: null, version: 1,
        });
      }
      for (const [table, column] of CATEGORY_REFS) {
        await knex(table)
          .where({ user_id: user.id, [column]: cat.id })
          .update({
            [column]: ownId,
            updated_at: ts,
            version: knex.raw('version + 1'),
          });
      }
    }
  }

  await knex('categories')
    .where({ is_system: true }).whereNull('deleted_at')
    .update({ deleted_at: ts, updated_at: ts, version: knex.raw('version + 1') });
}

export async function down() {
  // Migração de dados sem retorno: as cópias por usuário permanecem válidas.
}
