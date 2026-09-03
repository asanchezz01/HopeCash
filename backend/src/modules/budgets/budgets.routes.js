import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { notFound, badRequest } from '../../utils/httpError.js';
import { monthStart, addMonths } from '../../utils/time.js';
import { getBudgetSummary, realizedBudgetSeed } from './budgets.service.js';

const router = Router();

/** Previsto × realizado por categoria/subcategoria do orçamento (despesas e receitas). */
router.get('/:id/summary', async (req, res) => {
  const budget = await syncRepo.findById('budgets', req.auth, req.params.id);
  if (!budget) throw notFound('Orçamento não encontrado');
  res.json({ data: await getBudgetSummary(req.auth, budget) });
});

/**
 * Gera o orçamento de um mês a partir de outro: os itens saem do orçamento do
 * mês de origem (`source: 'budget'`) ou do que foi de fato gasto/recebido nele
 * (`source: 'realized'`). Com `replace`, um orçamento já existente no destino
 * é reescrito no lugar de recusar.
 */
router.post('/copy', validate(z.object({
  source_month: z.string().regex(/^\d{4}-\d{2}(-\d{2})?$/),
  target_month: z.string().regex(/^\d{4}-\d{2}(-\d{2})?$/),
  source: z.enum(['budget', 'realized']).default('budget'),
  replace: z.boolean().default(false),
})), async (req, res) => {
  const sourceMonth = monthStart(`${req.body.source_month.slice(0, 7)}-01`);
  const targetMonth = monthStart(`${req.body.target_month.slice(0, 7)}-01`);
  const fromRealized = req.body.source === 'realized';

  const [origin] = await syncRepo.list('budgets', req.auth, { limit: 1, filters: { reference_month: sourceMonth } });
  if (!origin && !fromRealized) throw notFound('Orçamento de origem não encontrado');
  const seed = fromRealized
    ? await realizedBudgetSeed(req.auth, sourceMonth)
    : (await syncRepo.list('budget_items', req.auth, { limit: 200, filters: { budget_id: origin.id } })).map((item) => ({
      category_id: item.category_id,
      subcategory_id: item.subcategory_id,
      planned_amount: item.planned_amount,
      is_fixed: !!item.is_fixed,
      due_day: item.due_day,
      account_id: item.account_id,
      card_id: item.card_id,
      family_id: item.family_id,
    }));
  if (!seed.length) throw notFound('Nada a copiar no mês de origem');

  const [existing] = await syncRepo.list('budgets', req.auth, { limit: 1, filters: { reference_month: targetMonth } });
  if (existing && !req.body.replace) throw badRequest('Já existe orçamento para o mês de destino');

  const budget = existing ?? await syncRepo.create('budgets', req.auth, {
    reference_month: targetMonth, scope: origin?.scope ?? 'personal', notes: origin?.notes, family_id: origin?.family_id,
  }, { req });
  if (existing) {
    const old = await syncRepo.list('budget_items', req.auth, { limit: 200, filters: { budget_id: existing.id } });
    for (const item of old) await syncRepo.softDelete('budget_items', req.auth, item.id, { req });
  }
  for (const item of seed) {
    await syncRepo.create('budget_items', req.auth, { budget_id: budget.id, ...item }, { req });
  }
  res.status(existing ? 200 : 201).json({ data: budget });
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
