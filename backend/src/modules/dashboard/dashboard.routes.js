import { Router } from 'express';
import { db } from '../../db/knex.js';
import { applyScope } from '../../core/syncRepo.js';
import { today, addDays, monthStart, addMonths } from '../../utils/time.js';

const router = Router();

const round2 = (n) => Math.round(n * 100) / 100;

/** Todos os indicadores do painel principal em uma única chamada. */
router.get('/', async (req, res) => {
  const auth = req.auth;
  const todayStr = today();
  const month = todayStr.slice(0, 7);

  // ----- Saldos por conta -----
  const accounts = await applyScope(db('bank_accounts'), 'bank_accounts', auth)
    .whereNull('deleted_at').where('is_active', true);
  const accountIds = accounts.map((a) => a.id);
  const paid = accountIds.length
    ? await applyScope(db('transactions'), 'transactions', auth)
        .whereNull('deleted_at').where('status', 'paid').whereIn('account_id', accountIds)
        .groupBy('account_id', 'type').select('account_id', 'type')
        .sum({ total: 'amount' })
    : [];
  const deltaByAccount = {};
  for (const r of paid) {
    deltaByAccount[r.account_id] = (deltaByAccount[r.account_id] ?? 0)
      + (r.type === 'income' ? Number(r.total ?? 0) : -Number(r.total ?? 0));
  }
  const accountBalances = accounts.map((a) => ({
    id: a.id, name: a.name, type: a.type, color: a.color, icon: a.icon,
    balance: round2(Number(a.initial_balance) + (deltaByAccount[a.id] ?? 0)),
    include_in_total: !!a.include_in_total,
  }));
  const totalBalance = round2(accountBalances.filter((a) => a.include_in_total).reduce((s, a) => s + a.balance, 0));

  // ----- Receitas/despesas do mês (realizado e previsto) -----
  const monthRows = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at').whereNot('status', 'canceled')
    .where('competence_date', '>=', `${month}-01`)
    .where('competence_date', '<', addMonths(`${month}-01`, 1))
    .select('type', 'status', 'amount', 'amount_planned', 'category_id');
  let incomeRealized = 0; let expenseRealized = 0; let incomePlanned = 0; let expensePlanned = 0;
  const spentByCategory = {};
  for (const r of monthRows) {
    const value = Number((r.status === 'paid' ? r.amount : r.amount_planned ?? r.amount) ?? 0);
    if (r.status === 'paid') {
      if (r.type === 'income') incomeRealized += value; else if (r.type === 'expense') expenseRealized += value;
    } else if (r.type === 'income') incomePlanned += value; else if (r.type === 'expense') expensePlanned += value;
    if (r.type === 'expense' && r.category_id) {
      spentByCategory[r.category_id] = (spentByCategory[r.category_id] ?? 0) + value;
    }
  }

  // ----- Top categorias do mês -----
  const catIds = Object.keys(spentByCategory);
  const cats = catIds.length ? await db('categories').whereIn('id', catIds).select('id', 'name', 'icon', 'color') : [];
  const catById = Object.fromEntries(cats.map((c) => [c.id, c]));
  const topCategories = catIds
    .map((id) => ({ category: catById[id] ?? { id }, total: round2(spentByCategory[id]) }))
    .sort((a, b) => b.total - a.total)
    .slice(0, 6);

  // ----- Contas a pagar/receber e vencidas -----
  const pending = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at').whereIn('status', ['planned', 'overdue'])
    .where('due_date', '<=', addDays(todayStr, 30))
    .orderBy('due_date')
    .select('id', 'type', 'description', 'amount_planned', 'amount', 'due_date', 'status')
    .limit(50);
  const payable = pending.filter((t) => t.type === 'expense');
  const receivable = pending.filter((t) => t.type === 'income');
  const overdue = pending.filter((t) => t.due_date && t.due_date < todayStr);

  // ----- Orçamento do mês -----
  const [budget] = await applyScope(db('budgets'), 'budgets', auth)
    .whereNull('deleted_at').where('reference_month', `${month}-01`).limit(1);
  let budgetSummary = null;
  if (budget) {
    const items = await db('budget_items').where({ budget_id: budget.id }).whereNull('deleted_at');
    const plannedTotal = items.reduce((s, i) => s + Number(i.planned_amount), 0);
    const realizedTotal = items.reduce((s, i) => s + (spentByCategory[i.category_id] ?? 0), 0);
    budgetSummary = {
      budget_id: budget.id,
      planned: round2(plannedTotal),
      realized: round2(realizedTotal),
      percent_used: plannedTotal > 0 ? Math.round((realizedTotal / plannedTotal) * 100) : null,
      exceeded_categories: items.filter((i) => (spentByCategory[i.category_id] ?? 0) > Number(i.planned_amount)).length,
    };
  }

  // ----- Evolução mensal (últimos 6 meses) -----
  const evolutionFrom = addMonths(monthStart(todayStr), -5);
  const evoRows = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at').where('status', 'paid')
    .where('competence_date', '>=', evolutionFrom)
    .select('type', 'amount', 'competence_date');
  const evolution = {};
  for (const r of evoRows) {
    const key = String(r.competence_date).slice(0, 7);
    evolution[key] ??= { month: key, income: 0, expense: 0 };
    if (r.type === 'income') evolution[key].income += Number(r.amount ?? 0);
    else if (r.type === 'expense') evolution[key].expense += Number(r.amount ?? 0);
  }
  const monthlyEvolution = Object.values(evolution).sort((a, b) => a.month.localeCompare(b.month))
    .map((m) => ({ ...m, income: round2(m.income), expense: round2(m.expense), result: round2(m.income - m.expense) }));

  // ----- Metas, dívidas, investimentos, patrimônio -----
  const goals = await applyScope(db('goals'), 'goals', auth).whereNull('deleted_at').where('status', 'active');
  const debts = await applyScope(db('debts'), 'debts', auth).whereNull('deleted_at').where('status', 'active');
  const investments = await applyScope(db('investments'), 'investments', auth).whereNull('deleted_at');
  const totalDebts = round2(debts.reduce((s, d) => s + Number(d.outstanding_balance), 0));
  const totalInvestments = round2(investments.reduce((s, i) => s + Number(i.current_amount), 0));
  const netWorth = round2(totalBalance + totalInvestments - totalDebts);

  // ----- Faturas de cartão a vencer -----
  const upcomingInvoices = await applyScope(db('credit_card_invoices'), 'credit_card_invoices', auth)
    .whereNull('deleted_at').whereIn('status', ['open', 'closed', 'partial'])
    .where('due_date', '<=', addDays(todayStr, 15))
    .orderBy('due_date').limit(10);

  // ----- Score de saúde financeira (heurística 0–100) -----
  let score = 50;
  const monthResult = incomeRealized - expenseRealized;
  if (incomeRealized > 0) {
    const savingsRate = monthResult / incomeRealized;
    score += Math.max(-25, Math.min(25, savingsRate * 100));
    const debtPressure = totalDebts / (incomeRealized * 12);
    score -= Math.min(15, debtPressure * 30);
  }
  score -= Math.min(15, overdue.length * 3);
  if (budgetSummary?.percent_used != null && budgetSummary.percent_used <= 100) score += 10;
  if (totalBalance > expenseRealized * 3) score += 10; // reserva de emergência ~3 meses
  score = Math.max(0, Math.min(100, Math.round(score)));

  res.json({
    data: {
      total_balance: totalBalance,
      accounts: accountBalances,
      month: {
        reference: month,
        income_realized: round2(incomeRealized),
        expense_realized: round2(expenseRealized),
        income_planned: round2(incomePlanned),
        expense_planned: round2(expensePlanned),
        result: round2(incomeRealized - expenseRealized),
      },
      payable_next_30_days: payable,
      receivable_next_30_days: receivable,
      overdue_count: overdue.length,
      upcoming_invoices: upcomingInvoices,
      budget: budgetSummary,
      top_categories: topCategories,
      monthly_evolution: monthlyEvolution,
      goals: goals.map((g) => ({
        id: g.id, name: g.name, target_amount: Number(g.target_amount),
        accumulated_amount: Number(g.accumulated_amount),
        percent: g.target_amount > 0 ? Math.round((g.accumulated_amount / g.target_amount) * 100) : 0,
        target_date: g.target_date,
      })),
      total_debts: totalDebts,
      total_investments: totalInvestments,
      net_worth: netWorth,
      health_score: score,
    },
  });
});

export default router;
