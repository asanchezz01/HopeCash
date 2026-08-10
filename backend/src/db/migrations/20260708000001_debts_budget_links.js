export async function up(knex) {
  await knex.schema.alterTable('debts', (t) => {
    t.uuid('category_id').index();
    t.uuid('subcategory_id').index();
    t.uuid('budget_item_id').index();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('debts', (t) => {
    t.dropColumn('budget_item_id');
    t.dropColumn('subcategory_id');
    t.dropColumn('category_id');
  });
}
