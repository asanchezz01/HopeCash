import { db } from '../../db/knex.js';
import { syncRepo } from '../../core/syncRepo.js';
import { addMonths } from '../../utils/time.js';

/** Previsto × realizado por categoria/subcategoria de um orçamento já carregado. */
export async function getBudgetSummary(auth, budget) {
  const items = await syncRepo.list('budget_items', auth, { limit: 200, filters: { budget_id: budget.id } });

  const month = String(budget.reference_month).slice(0, 7);
  const monthStart = `${month}-01`;
  const transactions = await db('transactions')
    .where({ user_id: budget.user_id })
    .whereIn('type', ['income', 'expense'])
    .whereNull('deleted_at')
    .whereNot('status', 'canceled')
    .where('competence_date', '>=', monthStart)
    .where('competence_date', '<', addMonths(monthStart, 1));

  // Um lançamento pertence a no máximo um item. A maior especificidade
  // (subcategoria e conta/cartão) vence, evitando duplicidade quando a mesma
  // categoria possui limites em meios de pagamento diferentes.
  const sortedItems = [...items].sort((a, b) => {
    const specificity = (item) => (item.subcategory_id ? 2 : 0) + (item.account_id || item.card_id ? 1 : 0);
    return specificity(b) - specificity(a) || String(a.id).localeCompare(String(b.id));
  });
  const realizedByItemId = Object.fromEntries(items.map((item) => [item.id, 0]));
  for (const transaction of transactions) {
    // Pagamento de fatura movimenta a conta, mas não é um novo gasto.
    if (transaction.account_id && transaction.card_id) continue;
    const item = sortedItems.find((candidate) => {
      if (candidate.category_id !== transaction.category_id) return false;
      if (candidate.subcategory_id && candidate.subcategory_id !== transaction.subcategory_id) return false;
      if (candidate.account_id && candidate.account_id !== transaction.account_id) return false;
      if (candidate.card_id && candidate.card_id !== transaction.card_id) return false;
      return true;
    });
    if (!item) continue;
    realizedByItemId[item.id] += Number(transaction.amount ?? transaction.amount_planned ?? 0);
  }

  const categories = await db('categories').whereIn('id', items.map((i) => i.category_id)).select('id', 'name', 'type', 'icon', 'color');
  const catById = Object.fromEntries(categories.map((c) => [c.id, c]));
  const subIds = items.map((i) => i.subcategory_id).filter(Boolean);
  const subcategories = subIds.length
    ? await db('subcategories').whereIn('id', subIds).select('id', 'name', 'icon')
    : [];
  const subById = Object.fromEntries(subcategories.map((s) => [s.id, s]));

  let totalPlanned = 0;
  let totalRealized = 0;
  let totalPlannedIncome = 0;
  let totalRealizedIncome = 0;
  const rows = items.map((item) => {
    const category = catById[item.category_id] ?? { id: item.category_id };
    const spent = realizedByItemId[item.id] ?? 0;
    const isIncome = category.type === 'income';
    if (isIncome) {
      totalPlannedIncome += Number(item.planned_amount);
      totalRealizedIncome += spent;
    } else {
      totalPlanned += Number(item.planned_amount);
      totalRealized += spent;
    }
    return {
      item_id: item.id,
      category,
      subcategory: item.subcategory_id
        ? subById[item.subcategory_id] ?? { id: item.subcategory_id }
        : null,
      is_fixed: !!item.is_fixed,
      due_day: item.due_day ?? null,
      account_id: item.account_id ?? null,
      card_id: item.card_id ?? null,
      planned: Number(item.planned_amount),
      realized: spent,
      percent_used: item.planned_amount > 0 ? Math.round((spent / item.planned_amount) * 100) : null,
      exceeded: !isIncome && spent > Number(item.planned_amount),
    };
  });

  return {
    budget,
    total_planned: totalPlanned,
    total_realized: totalRealized,
    total_planned_income: totalPlannedIncome,
    total_realized_income: totalRealizedIncome,
    items: rows,
  };
}

/** Orçamento do usuário para um mês (YYYY-MM), ou null se não existir. */
export async function findBudgetForMonth(auth, month) {
  const referenceMonth = `${month}-01`;
  const [budget] = await syncRepo.list('budgets', auth, { limit: 1, filters: { reference_month: referenceMonth } });
  return budget ?? null;
}
