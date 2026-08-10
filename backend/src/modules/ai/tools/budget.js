import { z } from 'zod';
import { today } from '../../../utils/time.js';
import { findBudgetForMonth, getBudgetSummary } from '../../budgets/budgets.service.js';
import { round2 } from './shared.js';

const monthSchema = z.string().regex(/^\d{4}-\d{2}$/, 'Mês no formato YYYY-MM');

export default {
  name: 'get_budget_status',
  description: 'Orçamento previsto × realizado por categoria para um mês. Retorna TODAS as categorias orçadas; ao apresentar o orçamento, cite cada uma delas. Use para responder sobre orçamento estourado, quanto falta gastar em uma categoria, etc.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      month: { type: 'string', description: 'Mês no formato YYYY-MM (padrão: mês atual)' },
    },
    required: [],
  },
  paramsSchema: z.object({ month: monthSchema.optional() }),
  async handler(auth, { month }) {
    const targetMonth = month ?? today().slice(0, 7);
    const budget = await findBudgetForMonth(auth, targetMonth);
    if (!budget) {
      return { month: targetMonth, has_budget: false, message: 'Nenhum orçamento cadastrado para este mês.' };
    }
    const summary = await getBudgetSummary(auth, budget);
    // Saída enxuta (sem ids, ícones ou campos de sincronização): o agente
    // trunca resultados longos e o JSON completo cortava categorias do fim.
    return {
      month: targetMonth,
      has_budget: true,
      total_planned: round2(summary.total_planned),
      total_realized: round2(summary.total_realized),
      total_planned_income: round2(summary.total_planned_income),
      total_realized_income: round2(summary.total_realized_income),
      items: summary.items.map((item) => ({
        category: item.category?.name ?? 'Sem categoria',
        ...(item.subcategory ? { subcategory: item.subcategory.name ?? null } : {}),
        type: item.category?.type ?? 'expense',
        planned: round2(item.planned),
        realized: round2(item.realized),
        percent_used: item.percent_used,
        exceeded: item.exceeded,
      })),
    };
  },
};
