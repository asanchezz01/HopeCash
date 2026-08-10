/**
 * Subcategoria sugerida para item de extrato bancário, editável no grid de
 * revisão antes de confirmar a importação — espelha suggested_category_id.
 * Item de fatura de cartão já guarda subcategoria em decision_payload; esta
 * coluna é usada apenas pelo fluxo de extrato (item_origin = 'statement' em
 * lote import_kind = 'bank_statement').
 */
export async function up(knex) {
  await knex.schema.alterTable('import_items', (t) => {
    t.uuid('suggested_subcategory_id');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('import_items', (t) => {
    t.dropColumn('suggested_subcategory_id');
  });
}
