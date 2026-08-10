import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { notFound, badRequest } from '../../utils/httpError.js';
import { monthStart, addMonths } from '../../utils/time.js';
import { getBudgetSummary } from './budgets.service.js';

const router = Router();

/** Previsto × realizado por categoria/subcategoria do orçamento (despesas e receitas). */
router.get('/:id/summary', async (req, res) => {
  const budget = await syncRepo.findById('budgets', req.auth, req.params.id);
  if (!budget) throw notFound('Orçamento não encontrado');
  res.json({ data: await getBudgetSummary(req.auth, budget) });
});

/** Copia o orçamento (itens) de um mês anterior para um novo mês. */
router.post('/copy', validate(z.object({
  source_month: z.string().regex(/^\d{4}-\d{2}(-\d{2})?$/),
  target_month: z.string().regex(/^\d{4}-\d{2}(-\d{2})?$/),
})), async (req, res) => {
  const sourceMonth = monthStart(`${req.body.source_month.slice(0, 7)}-01`);
  const targetMonth = monthStart(`${req.body.target_month.slice(0, 7)}-01`);
  const [source] = await syncRepo.list('budgets', req.auth, { limit: 1, filters: { reference_month: sourceMonth } });
  if (!source) throw notFound('Orçamento de origem não encontrado');
  const [existing] = await syncRepo.list('budgets', req.auth, { limit: 1, filters: { reference_month: targetMonth } });
  if (existing) throw badRequest('Já existe orçamento para o mês de destino');

  const budget = await syncRepo.create('budgets', req.auth, {
    reference_month: targetMonth, scope: source.scope, notes: source.notes, family_id: source.family_id,
  }, { req });
  const items = await syncRepo.list('budget_items', req.auth, { limit: 200, filters: { budget_id: source.id } });
  for (const item of items) {
    await syncRepo.create('budget_items', req.auth, {
      budget_id: budget.id,
      category_id: item.category_id,
      subcategory_id: item.subcategory_id,
      planned_amount: item.planned_amount,
      is_fixed: !!item.is_fixed,
      due_day: item.due_day,
      account_id: item.account_id,
      card_id: item.card_id,
      family_id: item.family_id,
    }, { req });
  }
  res.status(201).json({ data: budget });
});

/** Sugestão de orçamento: média de gastos por categoria dos últimos N meses. */
router.get('/suggestion', async (req, res) => {
  const months = Math.min(Number(req.query.months || 3), 12);
  const from = addMonths(monthStart(new Date().toISOString().slice(0, 10)), -months);
  const rows = await db('transactions')
    .where({ user_id: req.auth.userId, type: 'expense' })
    .whereNull('deleted_at')
    .whereNot('status', 'canceled')
    .where('competence_date', '>=', from)
    .groupBy('category_id')
    .select('category_id')
    .sum({ total: db.raw('COALESCE(amount, amount_planned)') });
  const data = rows
    .filter((r) => r.category_id)
    .map((r) => ({
      category_id: r.category_id,
      suggested_amount: Math.round((Number(r.total ?? 0) / months) * 100) / 100,
    }));
  res.json({ data });
});

router.use('/items', crudRouter('budget_items', { filterFields: ['budget_id', 'category_id'] }));
router.use('/', crudRouter('budgets', { filterFields: ['reference_month', 'scope'] }));

export default router;
