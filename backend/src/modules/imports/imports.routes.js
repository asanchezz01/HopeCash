import crypto from 'node:crypto';
import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { syncRepo, applyScope, deserialize } from '../../core/syncRepo.js';
import { notFound, badRequest, conflict } from '../../utils/httpError.js';
import { now, today } from '../../utils/time.js';
import { csvToItems, ofxToItems, pdfToItems, detectInstallment } from './parsers.js';
import {
  reconcileItems, reconciliationSummary, statementEffectCents,
  toCents, transactionEffectCents, transactionValue, isCreditKind,
} from './reconciliation.js';

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const MAX_ITEMS = 5000;

/**
 * CSV/OFX de banco vem em UTF-8 ou Latin-1/CP1252. Ler Latin-1 como UTF-8
 * produz caracteres inválidos e quebra descrições e cabeçalhos acentuados
 * ("Valor (em R$)", "Descrição"), então a falha de decodificação decide a volta.
 */
const decodeUpload = (buffer) => {
  const utf8 = buffer.toString('utf-8');
  const text = utf8.includes('�') ? buffer.toString('latin1') : utf8;
  return text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text; // BOM
};

const normalizeDesc = (description) => String(description ?? '').toLowerCase().replace(/\s+/g, ' ').trim();
const likeEscape = (s) => s.replace(/[%_\\]/g, (c) => `\\${c}`);
const safeRegexTest = (pattern, value) => { try { return new RegExp(pattern, 'i').test(value); } catch { return false; } };

async function suggestCategory(auth, description) {
  const desc = normalizeDesc(description);
  if (!desc) return null;
  const rules = await applyScope(db('categorization_rules'), 'categorization_rules', auth)
    .whereNull('deleted_at').where('is_active', true).orderBy('priority');
  for (const rule of rules) {
    const value = rule.match_value.toLowerCase();
    const matched = (rule.operator === 'contains' && desc.includes(value))
      || (rule.operator === 'equals' && desc === value)
      || (rule.operator === 'starts_with' && desc.startsWith(value))
      || (rule.operator === 'regex' && safeRegexTest(rule.match_value, description));
    if (matched && rule.category_id) return rule.category_id;
  }
  const similar = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at').whereNotNull('category_id')
    .whereRaw('lower(description) like ?', [`%${likeEscape(desc.slice(0, 20))}%`])
    .orderBy('created_at', 'desc').first();
  return similar?.category_id ?? null;
}

export function cardDueDate(purchaseDate, closingDay, dueDay) {
  const p = new Date(`${String(purchaseDate).slice(0, 10)}T00:00:00Z`);
  let closingMonth = { y: p.getUTCFullYear(), m: p.getUTCMonth() };
  if (p.getUTCDate() > closingDay) closingMonth = nextMonth(closingMonth);
  const dueMonth = dueDay > closingDay ? closingMonth : nextMonth(closingMonth);
  const day = Math.min(dueDay, new Date(Date.UTC(dueMonth.y, dueMonth.m + 1, 0)).getUTCDate());
  return `${dueMonth.y.toString().padStart(4, '0')}-${(dueMonth.m + 1).toString().padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}
const nextMonth = ({ y, m }) => (m === 11 ? { y: y + 1, m: 0 } : { y, m: m + 1 });

/** Soma meses mantendo o dia, com clamp no fim do mês (31/01 + 1m → 28/02). */
const addMonthsClamped = (isoDate, months) => {
  const [y, m, d] = String(isoDate).slice(0, 10).split('-').map(Number);
  const zeroBased = (m - 1) + months;
  const year = y + Math.floor(zeroBased / 12);
  const month = ((zeroBased % 12) + 12) % 12;
  const last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  return `${String(year).padStart(4, '0')}-${String(month + 1).padStart(2, '0')}-${String(Math.min(d, last)).padStart(2, '0')}`;
};

/** Rótulo da parcela futura: troca o marcador original por "(k/total)". */
const futureInstallmentLabel = (description, k, total) => {
  const detected = detectInstallment(description);
  const base = detected
    ? description.replace(detected.marker, ' ').replace(/\s{2,}/g, ' ').replace(/[-(]\s*$/, '').trim()
    : String(description ?? '').trim();
  return `${base} (${k}/${total})`;
};

const dueDateForBatch = (requested, metadata, referenceMonth, card, items) => {
  if (requested) return requested;
  if (metadata.due_date) return metadata.due_date;
  if (referenceMonth) {
    const [y, m] = referenceMonth.slice(0, 7).split('-').map(Number);
    const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
    return `${referenceMonth.slice(0, 7)}-${String(Math.min(card.due_day, last)).padStart(2, '0')}`;
  }
  const counts = new Map();
  for (const item of items) {
    const due = cardDueDate(item.date, card.closing_day, card.due_day);
    counts.set(due, (counts.get(due) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? null;
};

const cycleTransactions = async (auth, cardId, dueDate, trx = db) => {
  const q = applyScope(trx('transactions'), 'transactions', auth)
    .whereNull('transactions.deleted_at').where('transactions.card_id', cardId)
    .whereNot('transactions.status', 'canceled').whereNot('transactions.type', 'transfer')
    .whereRaw("lower(transactions.description) not like '%pagamento%fatura%'");
  if (dueDate) q.where('transactions.due_date', dueDate);
  return q.orderBy('transactions.id');
};

/**
 * Janela de datas do extrato: menor/maior data do arquivo ± tolerância, a
 * mesma tolerância padrão do reconciler. Persistida no lote para que reanálise
 * e retomada comparem sempre as mesmas transações da conta.
 */
const TOLERANCE_DAYS = 3;

const addDays = (isoDate, days) => {
  const d = new Date(`${String(isoDate).slice(0, 10)}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

const statementWindow = (items) => {
  const dates = items.map((i) => i.date ?? i.item_date).filter(Boolean).sort();
  return dates.length
    ? { from: addDays(dates[0], -TOLERANCE_DAYS), to: addDays(dates[dates.length - 1], TOLERANCE_DAYS) }
    : { from: null, to: null };
};

const matchWithinScope = (batch, tx) => batch.import_kind === 'credit_card_invoice'
  ? tx.card_id === batch.card_id && tx.due_date === batch.invoice_due_date
  : tx.account_id === batch.account_id;

/**
 * Transações da conta dentro da janela. `onlyRealized` restringe a status
 * 'paid' — usado para os itens "somente no HopeCash" (planejadas futuras não
 * são discrepância de extrato); os candidatos de match usam a variante ampla
 * para permitir casar uma transação ainda 'planned' e realizá-la.
 */
const accountTransactionsInWindow = async (auth, accountId, from, to, { onlyRealized = false, trx = db } = {}) => {
  const q = applyScope(trx('transactions'), 'transactions', auth)
    .whereNull('transactions.deleted_at').where('transactions.account_id', accountId)
    .whereNot('transactions.status', 'canceled').whereNot('transactions.type', 'transfer');
  if (onlyRealized) q.where('transactions.status', 'paid');
  if (from) q.where('transactions.competence_date', '>=', from);
  if (to) q.where('transactions.competence_date', '<=', to);
  return q.orderBy('transactions.id');
};

/** kind de crédito/débito por fluxo: fatura usa card_*, conta usa debit/credit. */
const creditKindFor = (importKind) => (importKind === 'credit_card_invoice' ? 'card_credit' : 'credit');
const debitKindFor = (importKind) => (importKind === 'credit_card_invoice' ? 'card_purchase' : 'debit');

/**
 * decision_payload de um item casado com um lançamento. Para conta corrente, o
 * extrato é a prova de que a transação foi paga: quando ela ainda está
 * 'planned', o payload já carrega a realização (status, data e amount — o
 * saldo da conta soma amount, não amount_planned), aplicada na confirmação.
 */
const matchDecisionPayload = (importKind, tx, { itemDate = null } = {}) => ({
  subcategory_id: tx.subcategory_id ?? null,
  ...(importKind !== 'credit_card_invoice' && tx.status !== 'paid'
    ? { status: 'paid', payment_date: itemDate, amount: Math.abs(Number(transactionValue(tx))) } : {}),
});

const listItems = async (auth, batchId, trx = db) => {
  const rows = await applyScope(trx('import_items'), 'import_items', auth)
    .whereNull('import_items.deleted_at').where('batch_id', batchId).orderBy('created_at').limit(MAX_ITEMS);
  return rows.map((r) => deserialize('import_items', r));
};

const responseForBatch = async (auth, batch) => {
  const items = await listItems(auth, batch.id);
  const ids = [...new Set(items.flatMap((item) => [
    item.matched_transaction_id, ...(item.candidate_transaction_ids ?? []),
  ]).filter(Boolean))];
  const transactions = ids.length
    ? await applyScope(db('transactions'), 'transactions', auth).whereNull('deleted_at').whereIn('id', ids)
    : [];
  const byId = new Map(transactions.map((tx) => [tx.id, tx]));
  for (const item of items) {
    item.matched_transaction = byId.get(item.matched_transaction_id) ?? null;
    item.candidate_transactions = (item.candidate_transaction_ids ?? []).map((id) => byId.get(id)).filter(Boolean);
  }
  return { batch, items, summary: reconciliationSummary(batch, items) };
};

async function createReconciliationAnalysis(req, {
  source, fileName, fileHash, importKind, card, accountId, referenceMonth, invoiceDueDate, mapping, items, metadata,
}) {
  const isInvoice = importKind === 'credit_card_invoice';
  let dueDate = null;
  let periodStart = null;
  let periodEnd = null;
  let transactions;
  if (isInvoice) {
    dueDate = dueDateForBatch(invoiceDueDate, metadata, referenceMonth, card, items);
    transactions = await cycleTransactions(req.auth, card.id, dueDate);
  } else {
    ({ from: periodStart, to: periodEnd } = statementWindow(items));
    transactions = await accountTransactionsInWindow(req.auth, accountId, periodStart, periodEnd);
  }
  const official = metadata.official_total == null ? null : Math.abs(toCents(metadata.official_total));
  const statement = items.map((item) => ({ ...item, amount_cents: toCents(item.amount) }));
  // Com o ciclo definido, todo lançamento candidato já vence na fatura: a data
  // da compra trazida pelo arquivo não deve excluir correspondências.
  const analysis = reconcileItems(statement, transactions, { cycleBound: isInvoice && Boolean(dueDate) });
  const recognized = statement.reduce((sum, item) => sum + statementEffectCents(item), 0);
  const current = transactions.reduce((sum, tx) => sum + transactionEffectCents(tx), 0);
  const batch = await syncRepo.create('import_batches', req.auth, {
    source, file_name: fileName, file_hash: fileHash, import_kind: importKind,
    account_id: accountId, card_id: isInvoice ? card.id : null,
    invoice_due_date: isInvoice ? dueDate : null,
    reference_month: isInvoice
      ? (referenceMonth ?? metadata.reference_month ?? (dueDate ? `${dueDate.slice(0, 7)}-01` : null))
      : null,
    period_start: periodStart, period_end: periodEnd,
    column_mapping: mapping, status: 'reviewing', reconciliation_status: 'reviewing',
    total_items: statement.length, imported_items: 0, official_total_cents: official,
    recognized_total_cents: recognized, current_total_cents: current,
    projected_total_cents: current, extracted_metadata: metadata, analysis_at: now(),
  }, { req });

  for (const result of analysis.statement) {
    // Item associado adota a categoria e a subcategoria já lançadas no HopeCash
    // (editáveis na revisão); sem associação, a sugestão vem de regras e histórico.
    const suggested = result.transaction
      ? result.transaction.category_id ?? null
      : await suggestCategory(req.auth, result.item.description);
    await syncRepo.create('import_items', req.auth, {
      batch_id: batch.id, raw: { ...result.item.raw, confidence: result.item.confidence },
      item_origin: 'statement', item_date: result.item.date, description: result.item.description,
      amount: result.item.amount, amount_cents: result.item.amount_cents, kind: result.item.kind,
      fitid: result.item.fitid, suggested_category_id: suggested,
      installment_number: result.item.installment_number ?? null,
      installment_total: result.item.installment_total ?? null,
      status: result.matchType.endsWith('_match') ? 'approved' : 'pending',
      match_type: result.matchType, match_confidence: result.confidence,
      matched_transaction_id: result.transaction?.id ?? null,
      matched_transaction_version: result.transaction?.version ?? null,
      candidate_transaction_ids: result.candidates, match_reason: result.reason,
      decision: result.transaction ? 'match' : null,
      decision_payload: result.transaction
        ? matchDecisionPayload(importKind, result.transaction, { itemDate: result.item.date }) : null,
      reviewed_at: result.transaction ? now() : null,
    }, { req });
  }
  for (const tx of analysis.hopecashOnly) {
    // Conta corrente: transações 'planned' futuras não são discrepância do
    // extrato — só as já realizadas (paid) aparecem como "somente no HopeCash".
    if (!isInvoice && tx.status !== 'paid') continue;
    await syncRepo.create('import_items', req.auth, {
      batch_id: batch.id, item_origin: 'hopecash', item_date: tx.competence_date,
      description: tx.description, amount: tx.type === 'income' ? Math.abs(Number(transactionValue(tx))) : -Math.abs(Number(transactionValue(tx))),
      amount_cents: transactionEffectCents(tx),
      kind: tx.type === 'income' ? creditKindFor(importKind) : debitKindFor(importKind),
      status: 'pending', match_type: 'hopecash_only', match_confidence: 0,
      matched_transaction_id: tx.id, matched_transaction_version: tx.version,
      decision_payload: {
        category_id: tx.category_id, subcategory_id: tx.subcategory_id, notes: tx.notes,
        status: tx.status, installment_group_id: tx.installment_group_id,
        installment_number: tx.installment_number, recurrence_id: tx.recurrence_id,
      },
    }, { req });
  }
  const fresh = await syncRepo.findById('import_batches', req.auth, batch.id);
  const freshItems = await listItems(req.auth, batch.id);
  const summary = reconciliationSummary(fresh, freshItems);
  const updated = await syncRepo.update('import_batches', req.auth, batch.id, { projected_total_cents: summary.projected_total_cents }, { req });
  return responseForBatch(req.auth, updated);
}

router.post('/', upload.single('file'), async (req, res) => {
  const source = String(req.body.source || '').toLowerCase();
  const importKind = String(req.body.import_kind || 'bank_statement');
  const accountId = req.body.account_id || null;
  const cardId = req.body.card_id || null;
  const requestedDueDate = req.body.invoice_due_date || null;
  const referenceMonth = req.body.reference_month || null;
  if (!req.file) throw badRequest('Arquivo obrigatório (campo "file")');
  if (!['csv', 'ofx', 'pdf'].includes(source)) throw badRequest('source deve ser csv, ofx ou pdf');
  if (!['bank_statement', 'credit_card_invoice'].includes(importKind)) throw badRequest('import_kind inválido');

  let card = null;
  if (importKind === 'credit_card_invoice') {
    if (!cardId) throw badRequest('card_id obrigatório para fatura de cartão');
    card = await syncRepo.findById('credit_cards', req.auth, cardId);
    if (!card) throw notFound('Cartão não encontrado');
  } else {
    if (!accountId) throw badRequest('account_id obrigatório');
    if (!await syncRepo.findById('bank_accounts', req.auth, accountId)) throw notFound('Conta não encontrada');
  }
  let mapping = null;
  if (req.body.column_mapping) { try { mapping = JSON.parse(req.body.column_mapping); } catch { throw badRequest('column_mapping inválido'); } }
  const parseOpts = { importKind, referenceYear: referenceMonth ? Number(referenceMonth.slice(0, 4)) : new Date().getFullYear() };
  let items;
  if (source === 'pdf') {
    try { items = pdfToItems(req.file.buffer, parseOpts); }
    catch (e) { throw badRequest(e.friendly ?? 'Não foi possível ler o PDF enviado'); }
  } else {
    const text = decodeUpload(req.file.buffer);
    items = source === 'csv' ? csvToItems(text, mapping, parseOpts) : ofxToItems(text, parseOpts);
  }
  if (!items.length) throw badRequest('Nenhum lançamento reconhecido no arquivo');
  if (items.length > MAX_ITEMS) throw badRequest(`O arquivo excede o limite de ${MAX_ITEMS} itens`);
  const fileHash = crypto.createHash('sha256').update(req.file.buffer).digest('hex');

  // Idempotência por hash do arquivo: reenviar o mesmo arquivo (mesmo destino
  // e tipo) retoma a conciliação em andamento em vez de duplicá-la.
  const prior = await applyScope(db('import_batches'), 'import_batches', req.auth)
    .whereNull('deleted_at').where({ import_kind: importKind, file_hash: fileHash })
    .modify((q) => (importKind === 'credit_card_invoice' ? q.where('card_id', cardId) : q.where('account_id', accountId)))
    .whereNot('status', 'canceled').orderBy('created_at', 'desc').first();
  if (prior) return res.status(200).json({ data: await responseForBatch(req.auth, deserialize('import_batches', prior)), idempotent: true });
  const data = await createReconciliationAnalysis(req, {
    source, fileName: req.file.originalname, fileHash, importKind, card, accountId, referenceMonth,
    invoiceDueDate: requestedDueDate, mapping, items, metadata: items.metadata ?? {},
  });
  return res.status(201).json({ data });
});

router.get('/', async (req, res) => res.json({ data: await syncRepo.list('import_batches', req.auth, { limit: 50 }) }));

router.get('/:id', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Lote não encontrado');
  // Lote antigo de extrato sem janela: backfill + reanálise em uma vez.
  const ready = await ensureBankBackfilled(req, batch);
  if (ready !== batch) {
    res.json({ data: ready, backfilled: true });
    return;
  }
  res.json({ data: await responseForBatch(req.auth, batch) });
});

router.get('/:id/items', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Lote não encontrado');
  res.json({ data: await listItems(req.auth, batch.id) });
});

const reconciliationItemPatch = z.object({
  decision: z.enum(['match', 'create', 'ignore', 'keep', 'edit', 'remove']).nullish(),
  matched_transaction_id: z.string().uuid().nullish(),
  suggested_category_id: z.string().uuid().nullish(), subcategory_id: z.string().uuid().nullish(),
  suggested_subcategory_id: z.string().uuid().nullish(),
  description: z.string().min(1).max(300).optional(), item_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  amount: z.coerce.number().positive().optional(),
  kind: z.enum(['debit', 'credit', 'card_purchase', 'card_credit']).optional(),
  notes: z.string().max(2000).nullish(), transaction_patch: z.record(z.any()).optional(),
  installment_number: z.coerce.number().int().min(1).nullish(),
  installment_total: z.coerce.number().int().min(1).nullish(),
});

router.put('/:id/items/:itemId', validate(reconciliationItemPatch), async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  const item = await syncRepo.findById('import_items', req.auth, req.params.itemId);
  if (!batch || !item || item.batch_id !== batch.id) throw notFound('Item não encontrado');
  if (batch.status !== 'reviewing') throw badRequest('A conciliação não está em revisão');
  const patch = { ...req.body };
  if (patch.amount != null || patch.kind) {
    const kind = patch.kind ?? item.kind;
    const cents = Math.abs(toCents(patch.amount ?? Math.abs(Number(item.amount))));
    patch.amount_cents = isCreditKind(kind) ? cents : -cents;
    patch.amount = patch.amount_cents / 100;
  }
  patch.decision_payload = { ...(item.decision_payload ?? {}),
    ...(patch.subcategory_id !== undefined ? { subcategory_id: patch.subcategory_id } : {}),
    ...(patch.notes !== undefined ? { notes: patch.notes } : {}),
    // Categoria trocada na revisão de um item associado tem de chegar ao
    // lançamento, e decision_payload é o que a conclusão aplica na transação.
    // Só a escolha explícita entra aqui: item que nunca foi editado não mexe
    // na categoria do lançamento.
    ...(patch.suggested_category_id !== undefined
      ? { category_id: patch.suggested_category_id ?? null } : {}),
    ...(patch.transaction_patch ?? {}),
  };
  delete patch.subcategory_id; delete patch.notes; delete patch.transaction_patch;
  if (patch.decision === 'match') {
    const txId = patch.matched_transaction_id ?? item.matched_transaction_id;
    const tx = txId && await syncRepo.findById('transactions', req.auth, txId);
    if (!tx || !matchWithinScope(batch, tx)) throw badRequest('Lançamento não pertence à conta/cartão e ciclo da conciliação');
    if (transactionEffectCents(tx) !== statementEffectCents({ ...item, ...patch })) throw badRequest('O tipo ou valor do lançamento não corresponde ao item');
    const used = await applyScope(db('import_items'), 'import_items', req.auth).whereNull('deleted_at')
      .where('batch_id', batch.id).whereNot('id', item.id).where('decision', 'match').where('matched_transaction_id', tx.id).first();
    if (used) throw conflict('Este lançamento já participa de outra correspondência');
    patch.matched_transaction_id = tx.id; patch.matched_transaction_version = tx.version;
    patch.match_type = 'probable_match'; patch.status = 'approved';
    patch.decision_payload = { ...patch.decision_payload, manual_match: true,
      // Associação manual em conta corrente também realiza a transação.
      ...(batch.import_kind !== 'credit_card_invoice' && tx.status !== 'paid'
        ? { status: 'paid', payment_date: item.item_date, amount: Math.abs(Number(transactionValue(tx))) } : {}),
    };
    // A associação manual também traz a categoria e a subcategoria do
    // lançamento, a menos que o usuário as informe na mesma requisição.
    if (patch.suggested_category_id === undefined) patch.suggested_category_id = tx.category_id ?? null;
    if (patch.decision_payload.subcategory_id == null) {
      patch.decision_payload.subcategory_id = tx.subcategory_id ?? null;
    }
    const counterpart = await applyScope(db('import_items'), 'import_items', req.auth).whereNull('deleted_at')
      .where({ batch_id: batch.id, item_origin: 'hopecash', matched_transaction_id: tx.id }).first();
    if (counterpart) await syncRepo.update('import_items', req.auth, counterpart.id, { decision: 'keep', status: 'ignored', reviewed_at: now() }, { req });
  }
  if (patch.decision) { patch.reviewed_at = now(); patch.status = patch.decision === 'ignore' ? 'ignored' : 'approved'; }
  const updated = await syncRepo.update('import_items', req.auth, item.id, patch, { req });
  const summary = reconciliationSummary(batch, await listItems(req.auth, batch.id));
  await syncRepo.update('import_batches', req.auth, batch.id, { projected_total_cents: summary.projected_total_cents }, { req });
  res.json({ data: { item: updated, summary } });
});

router.post('/:id/decisions/bulk', validate(z.object({ item_ids: z.array(z.string().uuid()).min(1).max(1000),
  decision: z.enum(['create', 'ignore', 'keep', 'remove']), suggested_category_id: z.string().uuid().nullish() })), async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Conciliação não encontrada');
  for (const id of req.body.item_ids) {
    const item = await syncRepo.findById('import_items', req.auth, id);
    if (!item || item.batch_id !== batch.id) throw notFound('Item não encontrado');
    const allowed = item.item_origin === 'hopecash' ? ['keep', 'remove'] : ['create', 'ignore'];
    if (!allowed.includes(req.body.decision)) throw badRequest('Decisão incompatível com o grupo do item');
    await syncRepo.update('import_items', req.auth, id, {
      decision: req.body.decision, status: req.body.decision === 'ignore' ? 'ignored' : 'approved',
      suggested_category_id: req.body.suggested_category_id ?? item.suggested_category_id, reviewed_at: now(),
    }, { req });
  }
  const items = await listItems(req.auth, batch.id);
  const summary = reconciliationSummary(batch, items);
  await syncRepo.update('import_batches', req.auth, batch.id, { projected_total_cents: summary.projected_total_cents }, { req });
  res.json({ data: { items, summary } });
});

router.put('/:id/official-total', validate(z.object({ official_total_cents: z.coerce.number().int().min(0) })), async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Conciliação não encontrada');
  const updated = await syncRepo.update('import_batches', req.auth, batch.id, { official_total_cents: req.body.official_total_cents }, { req });
  res.json({ data: { batch: updated, summary: reconciliationSummary(updated, await listItems(req.auth, batch.id)) } });
});

router.post('/:id/difference-item', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Conciliação não encontrada');
  if (batch.status !== 'reviewing') throw badRequest('A conciliação não está em revisão');
  const items = await listItems(req.auth, batch.id);
  const summary = reconciliationSummary(batch, items);
  if (summary.difference_cents == null) {
    throw badRequest(
      batch.import_kind === 'credit_card_invoice'
        ? 'Informe o total oficial da fatura antes de lançar a diferença'
        : 'Informe o total do extrato antes de lançar a diferença',
    );
  }
  if (summary.difference_cents === 0) throw badRequest('Não há diferença pendente para lançar');
  const pendingAdjustment = items.find((item) => item.item_origin === 'statement'
    && item.description === 'Ajuste de diferença da fatura' && !item.decision);
  if (pendingAdjustment) throw conflict('Já existe um item de ajuste pendente; decida-o antes de lançar outro');
  const cents = Math.abs(summary.difference_cents);
  const isExpense = summary.difference_cents > 0;
  const kind = isExpense ? debitKindFor(batch.import_kind) : creditKindFor(batch.import_kind);
  await syncRepo.create('import_items', req.auth, {
    batch_id: batch.id, item_origin: 'statement',
    item_date: batch.import_kind === 'credit_card_invoice'
      ? (batch.invoice_due_date ?? today())
      : (batch.period_end ?? today()),
    description: 'Ajuste de diferença da fatura',
    amount: (isExpense ? -cents : cents) / 100,
    amount_cents: isExpense ? -cents : cents, kind,
    status: 'pending', match_type: 'statement_only', match_confidence: 0,
  }, { req });
  const freshItems = await listItems(req.auth, batch.id);
  const freshSummary = reconciliationSummary(batch, freshItems);
  const updated = await syncRepo.update('import_batches', req.auth, batch.id, { projected_total_cents: freshSummary.projected_total_cents }, { req });
  res.json({ data: { batch: updated, items: freshItems, summary: freshSummary } });
});

/**
 * Reanálise determinística da conciliação: preserva associações manuais,
 * recomputa correspondências automáticas e recria os itens "somente no
 * HopeCash". Usada pelo POST /analyze e pelo backfill de lotes antigos.
 */
async function reanalyzeBatch(req, batch) {
  const isInvoice = batch.import_kind === 'credit_card_invoice';
  const all = await listItems(req.auth, batch.id);
  const statement = all.filter((item) => item.item_origin === 'statement');
  const manual = statement.filter((item) => item.decision === 'match' && item.decision_payload?.manual_match);
  const manualIds = new Set(manual.map((item) => item.matched_transaction_id));
  const transactions = isInvoice
    ? await cycleTransactions(req.auth, batch.card_id, batch.invoice_due_date)
    : await accountTransactionsInWindow(req.auth, batch.account_id, batch.period_start, batch.period_end);
  for (const item of manual) {
    const tx = transactions.find((candidate) => candidate.id === item.matched_transaction_id);
    if (!tx) throw conflict('Uma associação manual não está mais disponível');
    await syncRepo.update('import_items', req.auth, item.id, { matched_transaction_version: tx.version }, { req });
  }
  const available = transactions.filter((tx) => !manualIds.has(tx.id));
  const automatic = statement.filter((item) => !manual.includes(item));
  const analysis = reconcileItems(automatic, available, { cycleBound: isInvoice && Boolean(batch.invoice_due_date) });
  for (const result of analysis.statement) {
    await syncRepo.update('import_items', req.auth, result.item.id, {
      match_type: result.matchType, match_confidence: result.confidence,
      matched_transaction_id: result.transaction?.id ?? null,
      matched_transaction_version: result.transaction?.version ?? null,
      candidate_transaction_ids: result.candidates, match_reason: result.reason,
      decision: result.transaction ? 'match' : null,
      // Reanálise: só quem passou a ter associação adota a categoria do
      // lançamento; itens sem match mantêm a categoria já escolhida na revisão.
      ...(result.transaction ? { suggested_category_id: result.transaction.category_id ?? null } : {}),
      decision_payload: result.transaction
        ? matchDecisionPayload(batch.import_kind, result.transaction, { itemDate: result.item.item_date }) : null,
      status: result.transaction ? 'approved' : 'pending',
      reviewed_at: result.transaction ? now() : null,
    }, { req });
  }
  for (const item of all.filter((candidate) => candidate.item_origin === 'hopecash')) {
    await syncRepo.softDelete('import_items', req.auth, item.id, { req });
  }
  for (const tx of analysis.hopecashOnly) {
    if (!isInvoice && tx.status !== 'paid') continue;
    await syncRepo.create('import_items', req.auth, {
      batch_id: batch.id, item_origin: 'hopecash', item_date: tx.competence_date,
      description: tx.description, amount_cents: transactionEffectCents(tx),
      amount: tx.type === 'income' ? Math.abs(Number(transactionValue(tx))) : -Math.abs(Number(transactionValue(tx))),
      kind: tx.type === 'income' ? creditKindFor(batch.import_kind) : debitKindFor(batch.import_kind),
      status: 'pending', match_type: 'hopecash_only', match_confidence: 0,
      matched_transaction_id: tx.id, matched_transaction_version: tx.version,
      decision_payload: { category_id: tx.category_id, subcategory_id: tx.subcategory_id, notes: tx.notes,
        status: tx.status, installment_group_id: tx.installment_group_id,
        installment_number: tx.installment_number, recurrence_id: tx.recurrence_id },
    }, { req });
  }
  const current = transactions.reduce((sum, tx) => sum + transactionEffectCents(tx), 0);
  const updated = await syncRepo.update('import_batches', req.auth, batch.id, {
    current_total_cents: current, analysis_at: now(),
  }, { req });
  const response = await responseForBatch(req.auth, updated);
  response.batch = await syncRepo.update('import_batches', req.auth, batch.id, {
    projected_total_cents: response.summary.projected_total_cents,
  }, { req });
  return response;
}

/**
 * Backfill preguiçoso de lotes de extrato criados antes da conciliação
 * bidirecional: deriva a janela das datas dos itens, converte antigos
 * status 'ignored' em decisão e roda a reanálise. Idempotente (uma vez).
 */
async function ensureBankBackfilled(req, batch) {
  if (batch.import_kind !== 'bank_statement' || batch.period_start != null) return batch;
  const items = await listItems(req.auth, batch.id);
  const dates = items
    .filter((i) => i.item_origin === 'statement')
    .map((i) => i.item_date).filter(Boolean).sort();
  if (!dates.length) return batch;
  let updated = await syncRepo.update('import_batches', req.auth, batch.id, {
    period_start: addDays(dates[0], -TOLERANCE_DAYS),
    period_end: addDays(dates[dates.length - 1], TOLERANCE_DAYS),
  }, { req });
  for (const item of items) {
    if (item.status === 'ignored' && !item.decision) {
      await syncRepo.update('import_items', req.auth, item.id, { decision: 'ignore', reviewed_at: now() }, { req });
    }
  }
  return reanalyzeBatch(req, updated);
}

router.post('/:id/analyze', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Conciliação não encontrada');
  if (batch.status !== 'reviewing') throw badRequest('Somente conciliações em revisão podem ser reanalisadas');
  res.json({ data: await reanalyzeBatch(req, batch) });
});

router.post('/:id/cancel', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Lote não encontrado');
  if (batch.status === 'confirmed') throw badRequest('Uma conciliação concluída não pode ser cancelada');
  res.json({ data: await syncRepo.update('import_batches', req.auth, batch.id, { status: 'canceled', reconciliation_status: 'canceled' }, { req }) });
});

router.post('/:id/resume', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Lote não encontrado');
  if (batch.status !== 'canceled') throw badRequest('Somente conciliações canceladas podem ser retomadas');
  const updated = await syncRepo.update('import_batches', req.auth, batch.id, { status: 'reviewing', reconciliation_status: 'reviewing' }, { req });
  const ready = await ensureBankBackfilled(req, updated);
  if (ready !== updated) {
    res.json({ data: ready, backfilled: true });
    return;
  }
  res.json({ data: await responseForBatch(req.auth, updated) });
});

const safeTransactionPatch = (payload = {}) => Object.fromEntries(Object.entries(payload).filter(([key]) => [
  'description', 'notes', 'amount_planned', 'amount', 'competence_date', 'due_date',
  'payment_date', 'status', 'category_id', 'subcategory_id', 'cost_center',
  'responsible_member_id',
].includes(key)));

/**
 * Mantém no patch só o que difere do lançamento atual: como o item associado
 * nasce com a categoria e a subcategoria do próprio lançamento, confirmar sem
 * alterar nada não deve versionar transações nem contar como edição.
 */
const changedFields = (patch, transaction) => Object.fromEntries(Object.entries(patch)
  .filter(([key, value]) => String(transaction[key] ?? '') !== String(value ?? '')));

router.post('/:id/confirm', async (req, res) => {
  const batch = await syncRepo.findById('import_batches', req.auth, req.params.id);
  if (!batch) throw notFound('Lote não encontrado');
  if (batch.status === 'confirmed') return res.json({ data: { batch, imported: batch.imported_items, idempotent: true } });
  if (batch.status !== 'reviewing') throw badRequest('Lote cancelado ou indisponível');

  const result = await db.transaction(async (trx) => {
    const locked = await syncRepo.findById('import_batches', req.auth, batch.id, { trx });
    if (locked.status === 'confirmed') return { batch: locked, imported: locked.imported_items, idempotent: true };
    const items = await listItems(req.auth, batch.id, trx);
    const before = reconciliationSummary(locked, items);
    if (!before.can_complete) {
      throw badRequest(
        locked.import_kind === 'credit_card_invoice'
          ? 'A conciliação só pode ser concluída com diferença de R$ 0,00 e todas as decisões revisadas'
          : 'Revise todas as decisões (e o total, se informado) antes de concluir',
        before,
      );
    }
    const matched = new Set();
    let created = 0; let edited = 0; let removed = 0; let futureInstallments = 0;
    for (const item of items) {
      if (item.item_origin === 'statement' && item.decision === 'match') {
        if (matched.has(item.matched_transaction_id)) throw conflict('Um lançamento participa de mais de uma correspondência');
        matched.add(item.matched_transaction_id);
        const tx = await syncRepo.findById('transactions', req.auth, item.matched_transaction_id, { trx });
        if (!tx || tx.version !== item.matched_transaction_version) throw conflict('Um lançamento mudou após a análise; reanalise a conciliação');
        const txPatch = changedFields(safeTransactionPatch(item.decision_payload), tx);
        if (Object.keys(txPatch).length) {
          await syncRepo.update('transactions', req.auth, tx.id, txPatch, { trx, req, expectedVersion: tx.version }); edited += 1;
        }
        await syncRepo.update('import_items', req.auth, item.id, { transaction_id: tx.id, status: 'approved' }, { trx, req });
      } else if (item.item_origin === 'statement' && item.decision === 'create') {
        const effect = statementEffectCents(item);
        const isExpense = effect >= 0;
        const payload = item.decision_payload ?? {};
        const categoryId = payload.category_id ?? item.suggested_category_id;
        // Paridade com a fatura: despesa nova exige categoria.
        if (isExpense && !categoryId) throw badRequest(`Categoria obrigatória no item ${item.description}`);
        const number = Number(item.installment_number);
        const total = Number(item.installment_total);
        const isInstallment = locked.import_kind === 'credit_card_invoice' && isExpense
          && Number.isInteger(total) && total > 1
          && Number.isInteger(number) && number >= 1 && number <= total
          && Boolean(item.item_date) && Boolean(locked.invoice_due_date);
        const groupId = isInstallment ? crypto.randomUUID() : null;
        const isBank = locked.import_kind !== 'credit_card_invoice';
        const tx = await syncRepo.create('transactions', req.auth, {
          type: isExpense ? 'expense' : 'income', description: item.description,
          notes: payload.notes ?? null, amount_planned: Math.abs(effect) / 100,
          competence_date: item.item_date, category_id: categoryId,
          subcategory_id: payload.subcategory_id ?? item.suggested_subcategory_id ?? null,
          // Fatura cria a compra no cartão (planned, vencendo na fatura);
          // extrato cria o lançamento já pago na conta, com amount preenchido.
          ...(isBank
            ? { account_id: locked.account_id, status: 'paid', payment_date: item.item_date, amount: Math.abs(effect) / 100 }
            : { due_date: locked.invoice_due_date, status: 'planned', card_id: locked.card_id }),
          installment_group_id: groupId,
          installment_number: isInstallment ? number : null,
          installment_total: isInstallment ? total : null,
        }, { trx, req });
        await syncRepo.update('import_items', req.auth, item.id, { transaction_id: tx.id, status: 'approved' }, { trx, req }); created += 1;
        if (isInstallment) {
          // As parcelas restantes entram nas próximas faturas (uma por mês) e
          // passam a compor o limite comprometido do cartão. Faturas futuras
          // importadas depois vão conciliar com estes lançamentos.
          for (let k = number + 1; k <= total; k += 1) {
            const offset = k - number;
            await syncRepo.create('transactions', req.auth, {
              type: 'expense', description: futureInstallmentLabel(item.description, k, total),
              amount_planned: Math.abs(effect) / 100,
              competence_date: addMonthsClamped(item.item_date, offset),
              due_date: addMonthsClamped(locked.invoice_due_date, offset), status: 'planned',
              card_id: locked.card_id, category_id: categoryId, subcategory_id: payload.subcategory_id ?? null,
              installment_group_id: groupId, installment_number: k, installment_total: total,
            }, { trx, req });
            futureInstallments += 1;
          }
        }
      } else if (item.item_origin === 'hopecash' && !matched.has(item.matched_transaction_id)) {
        const tx = await syncRepo.findById('transactions', req.auth, item.matched_transaction_id, { trx });
        if (!tx || tx.version !== item.matched_transaction_version) throw conflict('Um lançamento mudou após a análise; reanalise a conciliação');
        if (item.decision === 'remove') { await syncRepo.softDelete('transactions', req.auth, tx.id, { trx, req, expectedVersion: tx.version }); removed += 1; }
        else if (item.decision === 'edit') { await syncRepo.update('transactions', req.auth, tx.id, safeTransactionPatch(item.decision_payload), { trx, req, expectedVersion: tx.version }); edited += 1; }
      }
    }
    const finalTransactions = locked.import_kind === 'credit_card_invoice'
      ? await cycleTransactions(req.auth, locked.card_id, locked.invoice_due_date, trx)
      : await accountTransactionsInWindow(req.auth, locked.account_id, locked.period_start, locked.period_end, { trx });
    const finalTotal = finalTransactions.reduce((sum, tx) => sum + transactionEffectCents(tx), 0);
    // Extrato sem total oficial não exige conferência de diferença; nunca
    // comparar Number(null) (=== 0) — isso faria a checagem "passar" por acidente.
    if (locked.official_total_cents != null) {
      const difference = Number(locked.official_total_cents) - finalTotal;
      if (difference !== 0) throw conflict('O total mudou durante a aplicação; a diferença precisa voltar a R$ 0,00', { difference_cents: difference });
    }
    const updated = await syncRepo.update('import_batches', req.auth, locked.id, {
      status: 'confirmed', reconciliation_status: 'completed', imported_items: created,
      current_total_cents: finalTotal, projected_total_cents: finalTotal,
      final_difference_cents: locked.official_total_cents != null ? 0 : null, completed_at: now(),
    }, { trx, req, expectedVersion: locked.version });
    return {
      batch: updated, imported: created, created, edited, removed,
      future_installments: futureInstallments,
      difference_cents: locked.official_total_cents != null ? 0 : null,
    };
  });
  res.json({ data: result });
});

export default router;
