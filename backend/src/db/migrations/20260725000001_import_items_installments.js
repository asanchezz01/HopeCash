/**
 * Parcelamento detectado na descrição dos itens de fatura (ex.: "LOJA 2/5").
 * Usado na conclusão da conciliação para lançar as parcelas futuras nas
 * próximas faturas e assim compor o limite comprometido do cartão.
 */
export async function up(knex) {
  await knex.schema.alterTable('import_items', (t) => {
    t.integer('installment_number');
    t.integer('installment_total');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('import_items', (t) => {
    t.dropColumn('installment_total');
    t.dropColumn('installment_number');
  });
}
