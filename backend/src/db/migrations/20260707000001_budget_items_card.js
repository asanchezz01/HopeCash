/**
 * Itens de orçamento: cartão de crédito previsto de saída, para orçar
 * despesas recorrentes cobradas no cartão (ex.: assinaturas).
 */
export async function up(knex) {
  await knex.schema.alterTable('budget_items', (t) => {
    t.uuid('card_id').index();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('budget_items', (t) => {
    t.dropColumn('card_id');
  });
}
