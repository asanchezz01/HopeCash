import { z } from 'zod';

/**
 * Registro central de entidades sincronizáveis.
 * Alimenta os CRUDs REST, o push/pull de sincronização e a exportação LGPD.
 */

const uuid = z.string().uuid();
const money = z.coerce.number().finite();
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Data no formato YYYY-MM-DD');
const color = z.string().regex(/^#[0-9a-fA-F]{6,8}$/).nullish();

const base = { id: uuid.optional(), family_id: uuid.nullish() };

export const ENTITIES = {
  bank_accounts: {
    table: 'bank_accounts',
    schema: z.object({
      ...base,
      name: z.string().min(1).max(120),
      bank_name: z.string().max(120).nullish(),
      bank_code: z.string().max(10).nullish(),
      agency: z.string().max(20).nullish(),
      account_number: z.string().max(30).nullish(),
      type: z.enum(['checking', 'savings', 'investment', 'wallet', 'cash', 'digital']).default('checking'),
      initial_balance: money.default(0),
      initial_balance_date: isoDate.nullish(),
      color,
      icon: z.string().max(40).nullish(),
      is_active: z.coerce.boolean().default(true),
      include_in_total: z.coerce.boolean().default(true),
    }),
  },

  credit_cards: {
    table: 'credit_cards',
    schema: z.object({
      ...base,
      name: z.string().min(1).max(120),
      issuer: z.string().max(120).nullish(),
      limit_amount: money.default(0),
      closing_day: z.coerce.number().int().min(1).max(31),
      due_day: z.coerce.number().int().min(1).max(31),
      color,
      icon: z.string().max(40).nullish(),
      is_active: z.coerce.boolean().default(true),
      default_account_id: uuid.nullish(),
    }),
  },

  credit_card_invoices: {
    table: 'credit_card_invoices',
    schema: z.object({
      ...base,
      card_id: uuid,
      reference_month: isoDate,
      closing_date: isoDate,
      due_date: isoDate,
      status: z.enum(['open', 'closed', 'paid', 'partial']).default('open'),
      total_amount: money.default(0),
      paid_amount: money.default(0),
      payment_transaction_id: uuid.nullish(),
    }),
  },

  categories: {
    table: 'categories',
    includeSystem: true,
    schema: z.object({
      ...base,
      name: z.string().min(1).max(80),
      type: z.enum(['income', 'expense']),
      icon: z.string().max(40).nullish(),
      color,
    }),
  },

  subcategories: {
    table: 'subcategories',
    schema: z.object({
      ...base,
      category_id: uuid,
      name: z.string().min(1).max(80),
      icon: z.string().max(40).nullish(),
    }),
  },

  transactions: {
    table: 'transactions',
    jsonFields: ['tags', 'recurrence_rule', 'category_splits'],
    schema: z.object({
      ...base,
      type: z.enum(['income', 'expense', 'transfer']),
      description: z.string().min(1).max(200),
      notes: z.string().max(2000).nullish(),
      amount_planned: money.nullish(),
      amount: money.nullish(),
      competence_date: isoDate,
      due_date: isoDate.nullish(),
      payment_date: isoDate.nullish(),
      status: z.enum(['planned', 'paid', 'overdue', 'canceled']).default('planned'),
      account_id: uuid.nullish(),
      card_id: uuid.nullish(),
      invoice_id: uuid.nullish(),
      category_id: uuid.nullish(),
      subcategory_id: uuid.nullish(),
      category_splits: z.array(z.object({
        category_id: uuid,
        subcategory_id: uuid.nullish(),
        amount: money.positive(),
      })).max(20).nullish(),
      cost_center: z.string().max(80).nullish(),
      responsible_member_id: uuid.nullish(),
      transfer_account_id: uuid.nullish(),
      transfer_group_id: uuid.nullish(),
      installment_group_id: uuid.nullish(),
      installment_number: z.coerce.number().int().min(1).nullish(),
      installment_total: z.coerce.number().int().min(1).nullish(),
      recurrence_id: uuid.nullish(),
      recurrence_rule: z.object({
        freq: z.enum(['daily', 'weekly', 'monthly', 'yearly']),
        interval: z.number().int().min(1).default(1),
        until: isoDate.nullish(),
      }).nullish(),
      tags: z.array(z.string().max(40)).nullish(),
      latitude: z.coerce.number().nullish(),
      longitude: z.coerce.number().nullish(),
    }),
  },

  transaction_attachments: {
    table: 'transaction_attachments',
    jsonFields: ['ocr_data'],
    schema: z.object({
      ...base,
      transaction_id: uuid,
      kind: z.enum(['receipt', 'invoice', 'photo', 'document']).default('receipt'),
      file_name: z.string().max(200),
      file_path: z.string().max(500),
      mime_type: z.string().max(100).nullish(),
      size_bytes: z.coerce.number().int().nullish(),
      ocr_data: z.record(z.any()).nullish(),
      nfce_key: z.string().max(60).nullish(),
    }),
  },

  budgets: {
    table: 'budgets',
    schema: z.object({
      ...base,
      reference_month: isoDate,
      scope: z.enum(['personal', 'family']).default('personal'),
      notes: z.string().max(2000).nullish(),
    }),
  },

  budget_items: {
    table: 'budget_items',
    schema: z.object({
      ...base,
      budget_id: uuid,
      category_id: uuid,
      subcategory_id: uuid.nullish(),
      planned_amount: money.default(0),
      is_fixed: z.coerce.boolean().default(false),
      due_day: z.coerce.number().int().min(1).max(31).nullish(),
      account_id: uuid.nullish(),
      card_id: uuid.nullish(),
    }),
  },

  goals: {
    table: 'goals',
    schema: z.object({
      ...base,
      name: z.string().min(1).max(120),
      target_amount: money.positive(),
      target_date: isoDate.nullish(),
      accumulated_amount: money.default(0),
      linked_account_id: uuid.nullish(),
      icon: z.string().max(40).nullish(),
      color,
      status: z.enum(['active', 'done', 'paused']).default('active'),
    }),
  },

  debts: {
    table: 'debts',
    schema: z.object({
      ...base,
      name: z.string().min(1).max(120),
      type: z.enum(['loan', 'financing', 'installment_plan']).default('loan'),
      institution: z.string().max(120).nullish(),
      original_amount: money.positive(),
      outstanding_balance: money.min(0),
      interest_rate_monthly: money.min(0).default(0),
      total_installments: z.coerce.number().int().min(1).default(1),
      paid_installments: z.coerce.number().int().min(0).default(0),
      installment_amount: money.default(0),
      first_due_date: isoDate.nullish(),
      due_day: z.coerce.number().int().min(1).max(31).nullish(),
      account_id: uuid.nullish(),
      category_id: uuid.nullish(),
      subcategory_id: uuid.nullish(),
      budget_item_id: uuid.nullish(),
      status: z.enum(['active', 'paid_off', 'renegotiated']).default('active'),
    }),
  },

  investments: {
    table: 'investments',
    schema: z.object({
      ...base,
      name: z.string().min(1).max(120),
      type: z.enum(['fixed_income', 'stocks', 'funds', 'pension', 'crypto', 'other']).default('fixed_income'),
      institution: z.string().max(120).nullish(),
      applied_amount: money.default(0),
      current_amount: money.default(0),
      last_quote_date: isoDate.nullish(),
    }),
  },

  investment_movements: {
    table: 'investment_movements',
    schema: z.object({
      ...base,
      investment_id: uuid,
      type: z.enum(['deposit', 'withdrawal', 'yield']),
      amount: money,
      movement_date: isoDate,
    }),
  },

  import_batches: {
    table: 'import_batches',
    jsonFields: ['column_mapping', 'extracted_metadata'],
    schema: z.object({
      ...base,
      source: z.enum(['csv', 'ofx', 'pdf']),
      file_name: z.string().max(200).nullish(),
      import_kind: z.enum(['bank_statement', 'credit_card_invoice']).default('bank_statement'),
      account_id: uuid.nullish(),
      card_id: uuid.nullish(),
      invoice_due_date: isoDate.nullish(),
      reference_month: isoDate.nullish(),
      period_start: isoDate.nullish(),
      period_end: isoDate.nullish(),
      column_mapping: z.any().nullish(),
      status: z.enum(['analyzing', 'reviewing', 'confirmed', 'canceled']).default('reviewing'),
      total_items: z.coerce.number().int().default(0),
      imported_items: z.coerce.number().int().default(0),
      file_hash: z.string().length(64).nullish(),
      official_total_cents: z.coerce.number().int().nullish(),
      recognized_total_cents: z.coerce.number().int().nullish(),
      current_total_cents: z.coerce.number().int().nullish(),
      projected_total_cents: z.coerce.number().int().nullish(),
      final_difference_cents: z.coerce.number().int().nullish(),
      extracted_metadata: z.any().nullish(),
      reconciliation_status: z.enum(['not_applicable', 'reviewing', 'completed', 'canceled']).default('not_applicable'),
      analysis_at: z.string().nullish(),
      completed_at: z.string().nullish(),
    }),
  },

  import_items: {
    table: 'import_items',
    jsonFields: ['raw', 'candidate_transaction_ids', 'decision_payload'],
    schema: z.object({
      ...base,
      batch_id: uuid,
      raw: z.any().nullish(),
      item_date: isoDate.nullish(),
      description: z.string().max(300).nullish(),
      amount: money.nullish(),
      kind: z.enum(['debit', 'credit', 'card_purchase', 'card_credit']).nullish(),
      fitid: z.string().max(100).nullish(),
      suggested_category_id: uuid.nullish(),
      suggested_subcategory_id: uuid.nullish(),
      duplicate_of: uuid.nullish(),
      status: z.enum(['pending', 'approved', 'ignored', 'duplicate']).default('pending'),
      transaction_id: uuid.nullish(),
      item_origin: z.enum(['statement', 'hopecash']).default('statement'),
      amount_cents: z.coerce.number().int().nullish(),
      match_type: z.enum(['exact_match', 'probable_match', 'ambiguous', 'statement_only', 'hopecash_only']).nullish(),
      match_confidence: z.coerce.number().int().min(0).max(100).nullish(),
      matched_transaction_id: uuid.nullish(),
      matched_transaction_version: z.coerce.number().int().nullish(),
      candidate_transaction_ids: z.array(uuid).nullish(),
      decision: z.enum(['match', 'create', 'ignore', 'keep', 'edit', 'remove']).nullish(),
      decision_payload: z.any().nullish(),
      match_reason: z.string().max(500).nullish(),
      reviewed_at: z.string().nullish(),
      installment_number: z.coerce.number().int().min(1).nullish(),
      installment_total: z.coerce.number().int().min(1).nullish(),
    }),
  },

  categorization_rules: {
    table: 'categorization_rules',
    jsonFields: ['tags'],
    schema: z.object({
      ...base,
      name: z.string().min(1).max(120),
      match_field: z.enum(['description', 'amount', 'bank', 'card', 'merchant']).default('description'),
      operator: z.enum(['contains', 'equals', 'starts_with', 'regex', 'between']).default('contains'),
      match_value: z.string().max(300),
      match_value2: z.string().max(300).nullish(),
      category_id: uuid.nullish(),
      subcategory_id: uuid.nullish(),
      tags: z.array(z.string().max(40)).nullish(),
      priority: z.coerce.number().int().default(100),
      is_active: z.coerce.boolean().default(true),
    }),
  },

  notification_rules: {
    table: 'notification_rules',
    schema: z.object({
      ...base,
      bank_package: z.string().max(120),
      bank_name: z.string().max(120),
      event_type: z.enum(['pix_in', 'pix_out', 'debit', 'credit', 'payment', 'transfer_in', 'withdrawal']),
      pattern: z.string().max(500),
      is_active: z.coerce.boolean().default(true),
    }),
  },

  notifications: {
    table: 'notifications',
    jsonFields: ['data'],
    schema: z.object({
      ...base,
      type: z.string().max(30),
      title: z.string().max(150),
      body: z.string().max(500).nullish(),
      data: z.record(z.any()).nullish(),
      read_at: z.string().nullish(),
    }),
  },
};

export const ENTITY_NAMES = Object.keys(ENTITIES);
