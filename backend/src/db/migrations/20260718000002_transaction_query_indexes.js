/**
 * Composite indexes for the transaction read paths that grow with imported
 * history: sync cursor, monthly summaries, pending items and account balance.
 *
 * The original single-column indexes are intentionally retained because they
 * also serve administrative/global queries that are not scoped by user.
 */
export async function up(knex) {
  await knex.schema.alterTable('transactions', (table) => {
    table.index(['user_id', 'updated_at'], 'idx_tx_user_updated');
    table.index(
      ['user_id', 'competence_date', 'status', 'deleted_at'],
      'idx_tx_user_competence_status_deleted',
    );
    table.index(
      ['user_id', 'status', 'due_date', 'deleted_at'],
      'idx_tx_user_status_due_deleted',
    );
    table.index(
      ['user_id', 'account_id', 'status', 'deleted_at'],
      'idx_tx_user_account_status_deleted',
    );
  });
}

export async function down(knex) {
  await knex.schema.alterTable('transactions', (table) => {
    table.dropIndex([], 'idx_tx_user_updated');
    table.dropIndex([], 'idx_tx_user_competence_status_deleted');
    table.dropIndex([], 'idx_tx_user_status_due_deleted');
    table.dropIndex([], 'idx_tx_user_account_status_deleted');
  });
}
