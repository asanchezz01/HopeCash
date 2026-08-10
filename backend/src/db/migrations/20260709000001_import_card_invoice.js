/**
 * Importador unificado: extrato bancário OU fatura de cartão.
 * - import_batches ganha o modo (import_kind), o cartão de destino e os
 *   metadados da fatura (vencimento e mês de referência).
 * - import_items ganha o tipo detectado (kind) de cada linha.
 * Lotes antigos continuam válidos: import_kind default 'bank_statement'.
 */
export async function up(knex) {
  await knex.schema.alterTable('import_batches', (t) => {
    t.string('import_kind', 25).notNullable().defaultTo('bank_statement'); // bank_statement|credit_card_invoice
    t.uuid('card_id');
    t.date('invoice_due_date');
    t.date('reference_month');
  });
  await knex.schema.alterTable('import_items', (t) => {
    t.string('kind', 15); // debit|credit|card_purchase|card_credit
  });
}

export async function down(knex) {
  await knex.schema.alterTable('import_batches', (t) => {
    t.dropColumn('import_kind');
    t.dropColumn('card_id');
    t.dropColumn('invoice_due_date');
    t.dropColumn('reference_month');
  });
  await knex.schema.alterTable('import_items', (t) => {
    t.dropColumn('kind');
  });
}
