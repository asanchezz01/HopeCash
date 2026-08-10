export async function up(knex) {
  await knex.schema.alterTable('debts', (t) => {
    t.uuid('account_id').index();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('debts', (t) => {
    t.dropColumn('account_id');
  });
}
