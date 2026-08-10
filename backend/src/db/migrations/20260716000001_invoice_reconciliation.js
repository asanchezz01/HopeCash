/**
 * Estado persistente da conciliação de faturas. Valores usados para decisões
 * financeiras são inteiros em centavos; as colunas decimais antigas permanecem
 * para compatibilidade com importações de extrato.
 */
export async function up(knex) {
  await knex.schema.alterTable('import_batches', (t) => {
    t.string('file_hash', 64).index();
    t.bigInteger('official_total_cents');
    t.bigInteger('recognized_total_cents');
    t.bigInteger('current_total_cents');
    t.bigInteger('projected_total_cents');
    t.bigInteger('final_difference_cents');
    t.text('extracted_metadata');
    t.string('reconciliation_status', 20).defaultTo('not_applicable');
    t.timestamp('analysis_at');
    t.timestamp('completed_at');
  });

  await knex.schema.alterTable('import_items', (t) => {
    t.string('item_origin', 20).defaultTo('statement');
    t.bigInteger('amount_cents');
    t.string('match_type', 25);
    t.integer('match_confidence');
    t.uuid('matched_transaction_id');
    t.integer('matched_transaction_version');
    t.text('candidate_transaction_ids');
    t.string('decision', 25);
    t.text('decision_payload');
    t.text('match_reason');
    t.timestamp('reviewed_at');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('import_items', (t) => {
    t.dropColumn('reviewed_at');
    t.dropColumn('match_reason');
    t.dropColumn('decision_payload');
    t.dropColumn('decision');
    t.dropColumn('candidate_transaction_ids');
    t.dropColumn('matched_transaction_version');
    t.dropColumn('matched_transaction_id');
    t.dropColumn('match_confidence');
    t.dropColumn('match_type');
    t.dropColumn('amount_cents');
    t.dropColumn('item_origin');
  });
  await knex.schema.alterTable('import_batches', (t) => {
    t.dropColumn('completed_at');
    t.dropColumn('analysis_at');
    t.dropColumn('reconciliation_status');
    t.dropColumn('extracted_metadata');
    t.dropColumn('final_difference_cents');
    t.dropColumn('projected_total_cents');
    t.dropColumn('current_total_cents');
    t.dropColumn('recognized_total_cents');
    t.dropColumn('official_total_cents');
    t.dropColumn('file_hash');
  });
}
