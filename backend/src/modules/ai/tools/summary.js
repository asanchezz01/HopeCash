import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';
import { today } from '../../../utils/time.js';
import { round2 } from './shared.js';

const monthSchema = z.string().regex(/^\d{4}-\d{2}$/, 'Mês no formato YYYY-MM');

export default {
  name: 'get_month_summary',
  description: 'Resumo de um mês: receitas e despesas realizadas e previstas, resultado (saldo) e taxa de poupança.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: { month: { type: 'string', description: 'Mês no formato YYYY-MM (padrão: mês atual)' } },
    required: [],
  },
  paramsSchema: z.object({ month: monthSchema.optional() }),
  async handler(auth, { month }) {
    const targetMonth = month ?? today().slice(0, 7);
    const rows = await applyScope(db('transactions'), 'transactions', auth)
      .whereNull('deleted_at').whereNot('status', 'canceled')
      .whereRaw('substr(competence_date, 1, 7) = ?', [targetMonth])
      .select('type', 'status', 'amount', 'amount_planned');

    let incomeRealized = 0; let expenseRealized = 0; let incomePlanned = 0; let expensePlanned = 0;
    for (const r of rows) {
      const value = Number((r.status === 'paid' ? r.amount : r.amount_planned ?? r.amount) ?? 0);
      if (r.status === 'paid') {
        if (r.type === 'income') incomeRealized += value; else if (r.type === 'expense') expenseRealized += value;
      } else if (r.type === 'income') incomePlanned += value; else if (r.type === 'expense') expensePlanned += value;
    }
    const result = incomeRealized - expenseRealized;
    return {
      month: targetMonth,
      income_realized: round2(incomeRealized),
      expense_realized: round2(expenseRealized),
      income_planned: round2(incomePlanned),
      expense_planned: round2(expensePlanned),
      result: round2(result),
      savings_rate_percent: incomeRealized > 0 ? Math.round((result / incomeRealized) * 100) : null,
    };
  },
};
