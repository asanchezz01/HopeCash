/**
 * Janela de datas da conciliação de extrato bancário: menor/maior data do
 * arquivo ± tolerância. Espelha o ciclo (invoice_due_date) da fatura de
 * cartão, ancorando reanálise/resume sobre as mesmas transações da conta.
 */
export async function up(knex) {
  await knex.schema.alterTable('import_batches', (t) => {
    t.date('period_start');
    t.date('period_end');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('import_batches', (t) => {
    t.dropColumn('period_start');
    t.dropColumn('period_end');
  });
}
