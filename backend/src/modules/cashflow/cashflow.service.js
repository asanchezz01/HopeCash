import { db } from '../../db/knex.js';
import { applyScope } from '../../core/syncRepo.js';
import { today } from '../../utils/time.js';

const bucketKey = (date, granularity) => {
  if (granularity === 'day') return date;
  if (granularity === 'month') return date.slice(0, 7);
  if (granularity === 'year') return date.slice(0, 4);
  // Semana ISO simplificada: segunda-feira da semana.
  const d = new Date(`${date}T00:00:00Z`);
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() - day + 1);
  return d.toISOString().slice(0, 10);
};

/**
 * Fluxo de caixa: realizado + projetado por período, com saldo acumulado
 * e identificação de períodos de risco (saldo projetado negativo).
 */
export async function getCashflowProjection(auth, { from, to, granularity }) {
  // Saldo inicial: contas ativas + movimentações pagas antes do período.
  const accounts = await applyScope(db('bank_accounts'), 'bank_accounts', auth)
    .whereNull('deleted_at').where({ is_active: true, include_in_total: true });
  let opening = accounts.reduce((s, a) => s + Number(a.initial_balance), 0);
  const paidBefore = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at').where('status', 'paid').where('payment_date', '<', from)
    .whereIn('account_id', accounts.map((a) => a.id))
    .select('type', 'amount');
  for (const r of paidBefore) opening += r.type === 'income' ? Number(r.amount ?? 0) : -Number(r.amount ?? 0);
  opening = Math.round(opening * 100) / 100;

  // Movimentações do período (pagas ou previstas).
  const rows = await applyScope(db('transactions'), 'transactions', auth)
    .whereNull('deleted_at')
    .whereNot('status', 'canceled')
    .where(function () {
      this.whereBetween('payment_date', [from, to]).orWhereBetween('due_date', [from, to]);
    })
    .select('type', 'status', 'amount', 'amount_planned', 'payment_date', 'due_date', 'description');

  const buckets = new Map();
  const todayStr = today();
  let overdueCount = 0;
  let upcomingCount = 0;

  for (const r of rows) {
    const date = r.status === 'paid' ? r.payment_date : (r.due_date ?? r.payment_date);
    if (!date || date < from || date > to) continue;
    const key = bucketKey(String(date), granularity);
    if (!buckets.has(key)) {
      buckets.set(key, {
        period: key,
        income_realized: 0, expense_realized: 0,
        income_planned: 0, expense_planned: 0,
      });
    }
    const b = buckets.get(key);
    const value = Number((r.status === 'paid' ? r.amount : r.amount_planned ?? r.amount) ?? 0);
    if (r.status === 'paid') {
      if (r.type === 'income') b.income_realized += value; else b.expense_realized += value;
    } else {
      if (r.type === 'income') b.income_planned += value; else b.expense_planned += value;
      if (r.due_date && r.due_date < todayStr) overdueCount += 1; else upcomingCount += 1;
    }
  }

  const periods = [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period));
  let realizedBalance = opening;
  let projectedBalance = opening;
  const riskPeriods = [];
  for (const p of periods) {
    realizedBalance += p.income_realized - p.expense_realized;
    projectedBalance += p.income_realized - p.expense_realized + p.income_planned - p.expense_planned;
    p.balance_realized = Math.round(realizedBalance * 100) / 100;
    p.balance_projected = Math.round(projectedBalance * 100) / 100;
    if (p.balance_projected < 0) riskPeriods.push(p.period);
  }

  return {
    from, to, granularity,
    opening_balance: opening,
    periods,
    overdue_count: overdueCount,
    upcoming_count: upcomingCount,
    risk_periods: riskPeriods,
  };
}
