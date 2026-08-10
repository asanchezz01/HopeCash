/**
 * Rateio de um lançamento em várias categorias. O lançamento continua único
 * (e portanto conciliável pelo valor integral); o JSON só detalha como esse
 * valor deve compor os relatórios/orçamentos.
 */
export async function up(knex) {
  await knex.schema.alterTable('transactions', (t) => {
    t.text('category_splits');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('transactions', (t) => {
    t.dropColumn('category_splits');
  });
}
