/**
 * Itens de orçamento: subcategoria opcional e dia de vencimento
 * para despesas fixas.
 */
export async function up(knex) {
  await knex.schema.alterTable('budget_items', (t) => {
    t.uuid('subcategory_id').index();
    t.integer('due_day');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('budget_items', (t) => {
    t.dropColumn('subcategory_id');
    t.dropColumn('due_day');
  });
}
