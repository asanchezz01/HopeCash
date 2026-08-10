import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';
import { today, addDays, addMonths } from '../../../utils/time.js';

const BUDGET_VARIANCE_PREFIX = 'hopecash:budget_variance:';
const DEBT_PAYMENT_PREFIX = 'hopecash:debt_payment:';

const roundMoney = (value) => Math.round(Number(value ?? 0) * 100) / 100;
const monthStart = (date) => `${String(date).slice(0, 7)}-01`;
const monthEnd = (date) => addDays(addMonths(monthStart(date), 1), -1);

const dueDateForMonth = (date, dueDay) => {
  const start = monthStart(date);
  const lastDay = Number(monthEnd(start).slice(-2));
  const day = Math.min(Math.max(Number(dueDay ?? lastDay), 1), lastDay);
  return `${start.slice(0, 7)}-${String(day).padStart(2, '0')}`;
};

const parseStructuredNote = (notes, prefix) => {
  if (!notes?.startsWith(prefix)) return null;
  try {
    return JSON.parse(notes.slice(prefix.length));
  } catch {
    return null;
  }
};

const budgetVarianceData = (tx) => parseStructuredNote(tx.notes, BUDGET_VARIANCE_PREFIX);

const transactionMatchesBudgetItem = (tx, item) => {
  const variance = budgetVarianceData(tx);
  const categoryId = variance?.category_id ?? tx.category_id;
  const subcategoryId = variance?.subcategory_id ?? tx.subcategory_id;
  const accountId = variance ? variance.account_id : tx.account_id;
  const cardId = variance ? variance.card_id : tx.card_id;

  if (categoryId !== item.category_id) return false;
  if (item.subcategory_id && subcategoryId !== item.subcategory_id) return false;
  if (item.account_id && accountId !== item.account_id) return false;
  if (item.card_id && cardId !== item.card_id) return false;
  return true;
};

const transactionValueForBudget = (tx) => {
  const variance = budgetVarianceData(tx);
  if (variance) return roundMoney(variance.amount ?? tx.amount_planned);
  return roundMoney(tx.status === 'paid' ? tx.amount : (tx.amount_planned ?? tx.amount));
};

const isInvoiceSettlement = (tx) => Boolean(tx.account_id && tx.card_id);

async function transactionEntries(auth, windowEnd, type) {
  const q = applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at')
    .whereIn('status', ['planned', 'overdue'])
    .whereNotNull('due_date')
    .where('due_date', '<=', windowEnd);
  if (type) q.where('type', type);
  const rows = await q.select(
    'id', 'type', 'description', 'amount_planned', 'amount', 'due_date', 'status',
    'category_id', 'subcategory_id', 'account_id', 'card_id',
  );
  return rows
    .filter((row) => !isInvoiceSettlement(row))
    .map((row) => ({ ...row, source: 'transaction' }));
}

async function budgetEntries(auth, todayStr, windowEnd, type, linkedBudgetItemIds) {
  const firstMonth = monthStart(todayStr);
  const lastMonth = monthStart(windowEnd);
  const budgets = await applyScope(db('budgets'), 'budgets', auth)
    .whereNull('deleted_at')
    .whereBetween('reference_month', [firstMonth, lastMonth])
    .select('id', 'reference_month');
  if (!budgets.length) return [];

  const items = await applyScope(db('budget_items'), 'budget_items', auth)
    .whereNull('deleted_at')
    .whereIn('budget_id', budgets.map((budget) => budget.id))
    .select(
      'id', 'budget_id', 'category_id', 'subcategory_id', 'planned_amount',
      'due_day', 'account_id', 'card_id',
    );
  const visibleItems = items.filter((item) => !linkedBudgetItemIds.has(item.id));
  if (!visibleItems.length) return [];

  const categoryIds = [...new Set(visibleItems.map((item) => item.category_id).filter(Boolean))];
  const subcategoryIds = [...new Set(visibleItems.map((item) => item.subcategory_id).filter(Boolean))];
  const categories = categoryIds.length
    ? await applyScope(db('categories'), 'categories', auth)
      .whereNull('deleted_at').whereIn('id', categoryIds).select('id', 'name', 'type')
    : [];
  const subcategories = subcategoryIds.length
    ? await applyScope(db('subcategories'), 'subcategories', auth)
      .whereNull('deleted_at').whereIn('id', subcategoryIds).select('id', 'name')
    : [];
  const categoryById = new Map(categories.map((category) => [category.id, category]));
  const subcategoryById = new Map(subcategories.map((subcategory) => [subcategory.id, subcategory]));

  // Também carrega pagamentos e lançamentos previstos fora da janela curta da
  // pergunta. A Agenda usa o mês inteiro para abater o orçamento e evitar que
  // uma conta já lançada apareça novamente como uma previsão integral.
  const budgetTransactions = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at')
    .whereNot('status', 'canceled')
    .whereBetween('competence_date', [firstMonth, monthEnd(lastMonth)])
    .select(
      'id', 'type', 'amount', 'amount_planned', 'competence_date', 'due_date',
      'status', 'category_id', 'subcategory_id', 'account_id', 'card_id', 'notes',
    );

  const result = [];
  for (const budget of budgets) {
    const referenceMonth = String(budget.reference_month).slice(0, 7);
    const sortedItems = visibleItems
      .filter((item) => item.budget_id === budget.id)
      .sort((a, b) => Number(Boolean(b.subcategory_id)) - Number(Boolean(a.subcategory_id)));
    const settledByItem = new Map(sortedItems.map((item) => [item.id, 0]));

    for (const tx of budgetTransactions) {
      if (isInvoiceSettlement(tx) || !String(tx.competence_date).startsWith(referenceMonth)) continue;
      const item = sortedItems.find((candidate) => transactionMatchesBudgetItem(tx, candidate));
      if (!item) continue;
      const isSettled = tx.status === 'paid';
      const scheduleEnd = tx.card_id
        ? monthEnd(addMonths(budget.reference_month, 1))
        : monthEnd(budget.reference_month);
      const isScheduled = ['planned', 'overdue'].includes(tx.status)
        && tx.due_date && tx.due_date <= scheduleEnd;
      if (!isSettled && !isScheduled) continue;
      settledByItem.set(item.id, settledByItem.get(item.id) + transactionValueForBudget(tx));
    }

    for (const item of sortedItems) {
      const amount = roundMoney(Number(item.planned_amount) - settledByItem.get(item.id));
      if (amount <= 0) continue;
      const category = categoryById.get(item.category_id);
      const entryType = category?.type === 'income' ? 'income' : 'expense';
      if (type && entryType !== type) continue;
      const dueDate = dueDateForMonth(budget.reference_month, item.due_day);
      if (dueDate > windowEnd) continue;
      const subcategory = subcategoryById.get(item.subcategory_id);
      result.push({
        id: item.id,
        type: entryType,
        description: [category?.name ?? 'Sem categoria', subcategory?.name].filter(Boolean).join(' · '),
        amount_planned: amount,
        amount: null,
        due_date: dueDate,
        status: dueDate < todayStr ? 'overdue' : 'planned',
        category_id: item.category_id,
        subcategory_id: item.subcategory_id,
        account_id: item.account_id,
        card_id: item.card_id,
        source: 'budget',
        budget_id: item.budget_id,
      });
    }
  }
  return result;
}

const debtDueDate = (debt, todayStr, offset) => {
  if (debt.first_due_date) return addMonths(String(debt.first_due_date), debt.paid_installments + offset);
  return addMonths(dueDateForMonth(todayStr, debt.due_day ?? Number(todayStr.slice(-2))), offset);
};

const matchingOpenDebtTransaction = (transactions, debt, dueDate, amount) => transactions.some((tx) => {
  if (tx.type !== 'expense' || tx.due_date !== dueDate) return false;
  if (debt.account_id && tx.account_id !== debt.account_id) return false;
  if (roundMoney(tx.amount_planned ?? tx.amount) !== roundMoney(amount)) return false;
  const description = String(tx.description).toLowerCase();
  return description.includes(String(debt.name).toLowerCase())
    || (debt.institution && description.includes(String(debt.institution).toLowerCase()));
});

function paidDebtMonths(rows) {
  const result = new Map();
  for (const row of rows) {
    const data = parseStructuredNote(row.notes, DEBT_PAYMENT_PREFIX);
    if (!data?.debt_id || !data.due_date) continue;
    if (!result.has(data.debt_id)) result.set(data.debt_id, new Set());
    result.get(data.debt_id).add(String(data.due_date).slice(0, 7));
  }
  return result;
}

async function debtEntries(auth, todayStr, windowEnd, type, debts, openTransactions) {
  if (type === 'income') return [];
  const activeDebts = debts.filter((debt) => debt.status === 'active'
    && Number(debt.outstanding_balance) > 0);
  if (!activeDebts.length) return [];

  const payments = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at').where('status', 'paid')
    .where('notes', 'like', `${DEBT_PAYMENT_PREFIX}%`)
    .select('notes');
  const paidMonths = paidDebtMonths(payments);
  const result = [];

  for (const debt of activeDebts) {
    const remainingInstallments = Math.max(Number(debt.total_installments) - Number(debt.paid_installments), 0);
    if (!remainingInstallments) continue;
    const defaultAmount = Number(debt.installment_amount) > 0
      ? Number(debt.installment_amount)
      : Number(debt.outstanding_balance) / remainingInstallments;
    let remainingBalance = Number(debt.outstanding_balance);
    let monthShift = 0;

    for (let i = 0; i < remainingInstallments; i += 1) {
      const installmentNumber = Number(debt.paid_installments) + i + 1;
      let dueDate = debtDueDate(debt, todayStr, i + monthShift);
      while (paidMonths.get(debt.id)?.has(dueDate.slice(0, 7))) {
        monthShift += 1;
        dueDate = debtDueDate(debt, todayStr, i + monthShift);
      }
      if (dueDate > windowEnd) break;
      const amount = roundMoney(Math.min(defaultAmount, remainingBalance));
      if (amount <= 0) break;
      remainingBalance = roundMoney(remainingBalance - amount);
      if (matchingOpenDebtTransaction(openTransactions, debt, dueDate, amount)) continue;
      result.push({
        id: `${debt.id}:${installmentNumber}`,
        type: 'expense',
        description: `${debt.name} · parcela ${installmentNumber}/${debt.total_installments}`,
        amount_planned: amount,
        amount: null,
        due_date: dueDate,
        status: dueDate < todayStr ? 'overdue' : 'planned',
        category_id: debt.category_id,
        subcategory_id: debt.subcategory_id,
        account_id: debt.account_id,
        card_id: null,
        source: 'debt',
        debt_id: debt.id,
        installment_number: installmentNumber,
      });
    }
  }
  return result;
}

export default {
  name: 'get_upcoming_bills',
  description: 'Contas a pagar e a receber nos próximos N dias. Unifica lançamentos previstos/vencidos, lacunas do orçamento com dia de vencimento e parcelas projetadas de dívidas.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      days: { type: 'integer', description: 'Janela em dias a partir de hoje (padrão 30, máx 90)' },
      type: { type: 'string', enum: ['income', 'expense'], description: 'Filtra só contas a pagar (expense) ou a receber (income)' },
    },
    required: [],
  },
  paramsSchema: z.object({
    days: z.coerce.number().int().min(1).max(90).default(30),
    type: z.enum(['income', 'expense']).optional(),
  }),
  async handler(auth, { days, type }) {
    const todayStr = today();
    const windowEnd = addDays(todayStr, days);
    const transactions = await transactionEntries(auth, windowEnd, type);
    const debts = await applyScope(db('debts'), 'debts', auth)
      .whereNull('deleted_at')
      .select(
        'id', 'name', 'institution', 'outstanding_balance', 'total_installments',
        'paid_installments', 'installment_amount', 'first_due_date', 'due_day',
        'account_id', 'category_id', 'subcategory_id', 'budget_item_id', 'status',
      );
    const linkedBudgetItemIds = new Set(debts.map((debt) => debt.budget_item_id).filter(Boolean));
    const [budgets, projectedDebts] = await Promise.all([
      budgetEntries(auth, todayStr, windowEnd, type, linkedBudgetItemIds),
      debtEntries(auth, todayStr, windowEnd, type, debts, transactions),
    ]);

    const entries = [...transactions, ...budgets, ...projectedDebts]
      .sort((a, b) => a.due_date.localeCompare(b.due_date))
      .slice(0, 100);
    const overdue = entries.filter((entry) => entry.due_date < todayStr);
    const upcoming = entries.filter((entry) => entry.due_date >= todayStr);
    return {
      window_days: days,
      overdue_count: overdue.length,
      upcoming_count: upcoming.length,
      overdue,
      upcoming,
    };
  },
};
