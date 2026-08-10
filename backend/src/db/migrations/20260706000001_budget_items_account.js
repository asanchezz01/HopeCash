/**
 * Itens de orçamento: conta prevista de entrada (receita) ou saída (despesa).
 * Quando definida, a previsão compõe o saldo futuro dessa conta.
 */
export async function up(knex) {
  await knex.schema.alterTable('budget_items', (t) => {
    t.uuid('account_id').index();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('budget_items', (t) => {
    t.dropColumn('account_id');
  });
}
