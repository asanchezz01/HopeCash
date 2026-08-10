/**
 * Schema inicial do HopeCash.
 * Todas as tabelas de negócio carregam as colunas de sincronização offline-first:
 * id UUID, user_id, family_id, created_at, updated_at, deleted_at, version.
 * JSON é armazenado como TEXT para portabilidade MySQL/SQLite (serializado na aplicação).
 */

const syncColumns = (t, { withFamily = true } = {}) => {
  t.uuid('id').primary();
  t.uuid('user_id').notNullable().index();
  if (withFamily) t.uuid('family_id').nullable().index();
  t.datetime('created_at', { precision: 3 }).notNullable();
  t.datetime('updated_at', { precision: 3 }).notNullable().index();
  t.datetime('deleted_at', { precision: 3 }).nullable();
  t.integer('version').notNullable().defaultTo(1);
};

const money = (t, name) => t.decimal(name, 15, 2);

export async function up(knex) {
  await knex.schema.createTable('users', (t) => {
    t.uuid('id').primary();
    t.string('name', 120).notNullable();
    t.string('email', 190).notNullable().unique();
    t.string('password_hash', 100).notNullable();
    t.string('avatar_url', 500);
    t.string('locale', 10).notNullable().defaultTo('pt-BR');
    t.string('currency', 3).notNullable().defaultTo('BRL');
    t.string('status', 20).notNullable().defaultTo('active'); // active|blocked|pending_deletion
    t.string('password_reset_token', 64);
    t.datetime('password_reset_expires_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
    t.datetime('deleted_at', { precision: 3 });
    t.integer('version').notNullable().defaultTo(1);
  });

  await knex.schema.createTable('user_sessions', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').notNullable().index();
    t.string('refresh_token_hash', 64).notNullable();
    t.string('device_name', 120);
    t.string('ip', 45);
    t.string('user_agent', 300);
    t.datetime('expires_at', { precision: 3 }).notNullable();
    t.datetime('revoked_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
  });

  await knex.schema.createTable('families', (t) => {
    syncColumns(t, { withFamily: false });
    t.string('name', 120).notNullable();
    t.uuid('owner_id').notNullable();
  });

  await knex.schema.createTable('family_members', (t) => {
    syncColumns(t);
    t.uuid('member_user_id').nullable().index(); // null enquanto convite pendente
    t.string('invited_email', 190);
    t.string('invite_token', 64);
    t.string('role', 20).notNullable().defaultTo('member'); // owner|admin|member|viewer
    t.string('status', 20).notNullable().defaultTo('invited'); // invited|active|removed
    t.text('permissions'); // JSON
  });

  await knex.schema.createTable('bank_accounts', (t) => {
    syncColumns(t);
    t.string('name', 120).notNullable();
    t.string('bank_name', 120);
    t.string('bank_code', 10);
    t.string('agency', 20);
    t.string('account_number', 30);
    t.string('type', 20).notNullable().defaultTo('checking'); // checking|savings|investment|wallet|cash|digital
    money(t, 'initial_balance').notNullable().defaultTo(0);
    t.date('initial_balance_date');
    t.string('color', 9);
    t.string('icon', 40);
    t.boolean('is_active').notNullable().defaultTo(true);
    t.boolean('include_in_total').notNullable().defaultTo(true);
  });

  await knex.schema.createTable('credit_cards', (t) => {
    syncColumns(t);
    t.string('name', 120).notNullable();
    t.string('issuer', 120);
    money(t, 'limit_amount').notNullable().defaultTo(0);
    t.integer('closing_day').notNullable().defaultTo(1);
    t.integer('due_day').notNullable().defaultTo(10);
    t.string('color', 9);
    t.string('icon', 40);
    t.boolean('is_active').notNullable().defaultTo(true);
    t.uuid('default_account_id');
  });

  await knex.schema.createTable('credit_card_invoices', (t) => {
    syncColumns(t);
    t.uuid('card_id').notNullable().index();
    t.date('reference_month').notNullable();
    t.date('closing_date').notNullable();
    t.date('due_date').notNullable();
    t.string('status', 20).notNullable().defaultTo('open'); // open|closed|paid|partial
    money(t, 'total_amount').notNullable().defaultTo(0);
    money(t, 'paid_amount').notNullable().defaultTo(0);
    t.uuid('payment_transaction_id');
  });

  await knex.schema.createTable('categories', (t) => {
    syncColumns(t);
    t.string('name', 80).notNullable();
    t.string('type', 10).notNullable(); // income|expense
    t.string('icon', 40);
    t.string('color', 9);
    t.boolean('is_system').notNullable().defaultTo(false);
  });

  await knex.schema.createTable('subcategories', (t) => {
    syncColumns(t);
    t.uuid('category_id').notNullable().index();
    t.string('name', 80).notNullable();
    t.string('icon', 40);
  });

  await knex.schema.createTable('transactions', (t) => {
    syncColumns(t);
    t.string('type', 10).notNullable(); // income|expense|transfer
    t.string('description', 200).notNullable();
    t.text('notes');
    money(t, 'amount_planned');
    money(t, 'amount');
    t.date('competence_date').notNullable().index();
    t.date('due_date').index();
    t.date('payment_date');
    t.string('status', 10).notNullable().defaultTo('planned'); // planned|paid|overdue|canceled
    t.uuid('account_id').index();
    t.uuid('card_id').index();
    t.uuid('invoice_id').index();
    t.uuid('category_id').index();
    t.uuid('subcategory_id');
    t.string('cost_center', 80);
    t.uuid('responsible_member_id');
    t.uuid('transfer_account_id');
    t.uuid('transfer_group_id').index();
    t.uuid('installment_group_id').index();
    t.integer('installment_number');
    t.integer('installment_total');
    t.uuid('recurrence_id').index();
    t.text('recurrence_rule'); // JSON {freq, interval, until}
    t.text('tags'); // JSON array
    t.decimal('latitude', 10, 7);
    t.decimal('longitude', 10, 7);
    t.uuid('created_by');
    t.uuid('updated_by');
  });

  await knex.schema.createTable('transaction_attachments', (t) => {
    syncColumns(t);
    t.uuid('transaction_id').notNullable().index();
    t.string('kind', 20).notNullable().defaultTo('receipt'); // receipt|invoice|photo|document
    t.string('file_name', 200).notNullable();
    t.string('file_path', 500).notNullable();
    t.string('mime_type', 100);
    t.integer('size_bytes');
    t.text('ocr_data'); // JSON {valor, data, estabelecimento, itens}
    t.string('nfce_key', 60);
  });

  await knex.schema.createTable('budgets', (t) => {
    syncColumns(t);
    t.date('reference_month').notNullable().index();
    t.string('scope', 10).notNullable().defaultTo('personal'); // personal|family
    t.text('notes');
  });

  await knex.schema.createTable('budget_items', (t) => {
    syncColumns(t);
    t.uuid('budget_id').notNullable().index();
    t.uuid('category_id').notNullable();
    money(t, 'planned_amount').notNullable().defaultTo(0);
    t.boolean('is_fixed').notNullable().defaultTo(false);
  });

  await knex.schema.createTable('goals', (t) => {
    syncColumns(t);
    t.string('name', 120).notNullable();
    money(t, 'target_amount').notNullable();
    t.date('target_date');
    money(t, 'accumulated_amount').notNullable().defaultTo(0);
    t.uuid('linked_account_id');
    t.string('icon', 40);
    t.string('color', 9);
    t.string('status', 10).notNullable().defaultTo('active'); // active|done|paused
  });

  await knex.schema.createTable('debts', (t) => {
    syncColumns(t);
    t.string('name', 120).notNullable();
    t.string('type', 20).notNullable().defaultTo('loan'); // loan|financing|installment_plan
    t.string('institution', 120);
    money(t, 'original_amount').notNullable();
    money(t, 'outstanding_balance').notNullable();
    t.decimal('interest_rate_monthly', 8, 4).notNullable().defaultTo(0);
    t.integer('total_installments').notNullable().defaultTo(1);
    t.integer('paid_installments').notNullable().defaultTo(0);
    money(t, 'installment_amount').notNullable().defaultTo(0);
    t.date('first_due_date');
    t.integer('due_day');
    t.string('status', 20).notNullable().defaultTo('active'); // active|paid_off|renegotiated
  });

  await knex.schema.createTable('investments', (t) => {
    syncColumns(t);
    t.string('name', 120).notNullable();
    t.string('type', 20).notNullable().defaultTo('fixed_income'); // fixed_income|stocks|funds|pension|crypto|other
    t.string('institution', 120);
    money(t, 'applied_amount').notNullable().defaultTo(0);
    money(t, 'current_amount').notNullable().defaultTo(0);
    t.date('last_quote_date');
  });

  await knex.schema.createTable('investment_movements', (t) => {
    syncColumns(t);
    t.uuid('investment_id').notNullable().index();
    t.string('type', 12).notNullable(); // deposit|withdrawal|yield
    money(t, 'amount').notNullable();
    t.date('movement_date').notNullable();
  });

  await knex.schema.createTable('import_batches', (t) => {
    syncColumns(t);
    t.string('source', 10).notNullable(); // csv|ofx|pdf
    t.string('file_name', 200);
    t.uuid('account_id');
    t.text('column_mapping'); // JSON
    t.string('status', 15).notNullable().defaultTo('reviewing'); // reviewing|confirmed|canceled
    t.integer('total_items').notNullable().defaultTo(0);
    t.integer('imported_items').notNullable().defaultTo(0);
  });

  await knex.schema.createTable('import_items', (t) => {
    syncColumns(t);
    t.uuid('batch_id').notNullable().index();
    t.text('raw'); // JSON linha original
    t.date('item_date');
    t.string('description', 300);
    money(t, 'amount');
    t.string('fitid', 100); // id OFX para deduplicação
    t.uuid('suggested_category_id');
    t.uuid('duplicate_of');
    t.string('status', 12).notNullable().defaultTo('pending'); // pending|approved|ignored|duplicate
    t.uuid('transaction_id');
  });

  await knex.schema.createTable('categorization_rules', (t) => {
    syncColumns(t);
    t.string('name', 120).notNullable();
    t.string('match_field', 20).notNullable().defaultTo('description'); // description|amount|bank|card|merchant
    t.string('operator', 15).notNullable().defaultTo('contains'); // contains|equals|starts_with|regex|between
    t.string('match_value', 300).notNullable();
    t.string('match_value2', 300);
    t.uuid('category_id');
    t.uuid('subcategory_id');
    t.text('tags'); // JSON
    t.integer('priority').notNullable().defaultTo(100);
    t.boolean('is_active').notNullable().defaultTo(true);
  });

  await knex.schema.createTable('notification_rules', (t) => {
    syncColumns(t);
    t.string('bank_package', 120).notNullable();
    t.string('bank_name', 120).notNullable();
    t.string('event_type', 20).notNullable(); // pix_in|pix_out|debit|credit|payment|transfer_in|withdrawal
    t.string('pattern', 500).notNullable(); // regex com grupos nomeados
    t.boolean('is_active').notNullable().defaultTo(true);
  });

  await knex.schema.createTable('notifications', (t) => {
    syncColumns(t);
    t.string('type', 30).notNullable();
    t.string('title', 150).notNullable();
    t.string('body', 500);
    t.text('data'); // JSON
    t.datetime('read_at', { precision: 3 });
  });

  await knex.schema.createTable('sync_operations', (t) => {
    t.uuid('id').primary();
    t.string('operation_id', 64).notNullable().unique(); // idempotência
    t.uuid('user_id').notNullable().index();
    t.string('device_id', 64);
    t.string('entity', 40).notNullable();
    t.uuid('entity_id').notNullable();
    t.string('op', 10).notNullable(); // create|update|delete
    t.text('payload'); // JSON
    t.integer('base_version');
    t.string('result', 20).notNullable(); // applied|conflict_resolved|rejected
    t.text('conflict_payload'); // JSON da versão perdedora
    t.datetime('created_at', { precision: 3 }).notNullable();
  });

  await knex.schema.createTable('audit_logs', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').index();
    t.uuid('family_id');
    t.string('entity', 40).notNullable();
    t.uuid('entity_id');
    t.string('action', 20).notNullable(); // create|update|delete|login|export|...
    t.text('changes'); // JSON
    t.string('ip', 45);
    t.string('user_agent', 300);
    t.datetime('created_at', { precision: 3 }).notNullable().index();
  });
}

export async function down(knex) {
  const tables = [
    'audit_logs', 'sync_operations', 'notifications', 'notification_rules',
    'categorization_rules', 'import_items', 'import_batches', 'investment_movements',
    'investments', 'debts', 'goals', 'budget_items', 'budgets',
    'transaction_attachments', 'transactions', 'subcategories', 'categories',
    'credit_card_invoices', 'credit_cards', 'bank_accounts', 'family_members',
    'families', 'user_sessions', 'users',
  ];
  for (const table of tables) await knex.schema.dropTableIfExists(table);
}
