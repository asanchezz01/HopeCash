import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';
import { today, monthStart, addMonths, addDays } from '../../../utils/time.js';
import { isoDate, round2, daysBetween } from './shared.js';

const defaultMonthRange = () => {
  const from = monthStart(today());
  const to = addDays(addMonths(from, 1), -1);
  return { from, to };
};

export default {
  name: 'spending_by_category',
  description: 'Total gasto (ou recebido) por categoria em um período, com comparação contra o período anterior de mesma duração. Use para "quanto gastei com X" ou "como estão minhas categorias este mês".',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      from: { type: 'string', description: 'Data inicial YYYY-MM-DD (padrão: início do mês atual)' },
      to: { type: 'string', description: 'Data final YYYY-MM-DD (padrão: fim do mês atual)' },
      type: { type: 'string', enum: ['income', 'expense'], description: 'Padrão: expense' },
    },
    required: [],
  },
  paramsSchema: z.object({
    from: isoDate.optional(),
    to: isoDate.optional(),
    type: z.enum(['income', 'expense']).default('expense'),
  }),
  async handler(auth, params) {
    const defaults = defaultMonthRange();
    const from = params.from ?? defaults.from;
    const to = params.to ?? defaults.to;

    const totalsFor = async (rangeFrom, rangeTo) => {
      const rows = await applyScope(db('transactions'), 'transactions', auth)
        .whereNull('deleted_at').whereNot('status', 'canceled')
        .where('type', params.type)
        .whereBetween('competence_date', [rangeFrom, rangeTo])
        .groupBy('category_id')
        .select('category_id')
        .sum({ total: db.raw('COALESCE(amount, amount_planned)') });
      return Object.fromEntries(rows.map((r) => [r.category_id ?? 'uncategorized', Number(r.total ?? 0)]));
    };

    const current = await totalsFor(from, to);
    const span = daysBetween(from, to);
    const prevTo = addDays(from, -1);
    const prevFrom = addDays(prevTo, -(span - 1));
    const previous = await totalsFor(prevFrom, prevTo);

    const categoryIds = Object.keys(current).filter((id) => id !== 'uncategorized');
    const categories = categoryIds.length
      ? await db('categories').whereIn('id', categoryIds).select('id', 'name', 'icon', 'color')
      : [];
    const catById = Object.fromEntries(categories.map((c) => [c.id, c]));

    const rows = Object.entries(current)
      .map(([id, total]) => ({
        category: id === 'uncategorized' ? null : (catById[id] ?? { id }),
        total: round2(total),
        previous_total: round2(previous[id] ?? 0),
      }))
      .sort((a, b) => b.total - a.total);

    const total = round2(Object.values(current).reduce((s, v) => s + v, 0));
    const previousTotal = round2(Object.values(previous).reduce((s, v) => s + v, 0));

    return {
      from,
      to,
      type: params.type,
      categories: rows,
      total,
      previous_period: { from: prevFrom, to: prevTo, total: previousTotal },
      change_percent: previousTotal > 0 ? Math.round(((total - previousTotal) / previousTotal) * 100) : null,
    };
  },
};
