import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { ENTITIES } from '../../core/registry.js';
import { addMonths } from '../../utils/time.js';
import { badRequest, forbidden } from '../../utils/httpError.js';

const router = Router();

// Restrição de PAT: PATs só podem criar transações (POST), nunca atualizar ou excluir.
router.use((req, _res, next) => {
  if (req.auth?.isPat) {
    if (req.method === 'POST') return next(); // Permitir criação
    if (['PUT', 'PATCH', 'DELETE'].includes(req.method)) {
      return next(forbidden('PATs só podem criar transações'));
    }
  }
  next();
});

// O rateio classifica um único lançamento; por isso nunca pode alterar o valor
// que a conciliação usa. Garante isso também para clientes antigos/offline.
router.use((req, _res, next) => {
  const splits = req.body?.category_splits;
  if (!Array.isArray(splits) || splits.length === 0) return next();
  const total = Number(req.body.amount ?? req.body.amount_planned);
  const splitCents = splits.reduce((sum, split) => sum + Math.round(Number(split.amount) * 100), 0);
  if (!Number.isFinite(total) || splitCents !== Math.round(total * 100)) {
    return next(badRequest('As partes do rateio devem somar exatamente o valor do lançamento'));
  }
  next();
});

/**
 * Compra parcelada: cria N transações mensais ligadas por installment_group_id.
 * O valor é dividido igualmente e a sobra de centavos vai para a primeira parcela.
 */
router.post('/installments', validate(ENTITIES.transactions.schema.extend({
  total_amount: z.coerce.number().positive(),
  installments: z.coerce.number().int().min(2).max(120),
  first_due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
})), async (req, res) => {
  const { total_amount, installments, first_due_date, ...tx } = req.body;
  const groupId = crypto.randomUUID();
  const cents = Math.round(total_amount * 100);
  const perInstallment = Math.floor(cents / installments);
  const remainder = cents - perInstallment * installments;

  const created = [];
  for (let i = 0; i < installments; i++) {
    const amountCents = perInstallment + (i === 0 ? remainder : 0);
    const dueDate = addMonths(first_due_date, i);
    created.push(await syncRepo.create('transactions', req.auth, {
      ...tx,
      id: undefined,
      description: `${tx.description} (${i + 1}/${installments})`,
      amount_planned: amountCents / 100,
      amount: tx.status === 'paid' ? amountCents / 100 : null,
      competence_date: dueDate,
      due_date: dueDate,
      installment_group_id: groupId,
      installment_number: i + 1,
      installment_total: installments,
    }, { req }));
  }
  res.status(201).json({ data: { installment_group_id: groupId, transactions: created } });
});

router.use('/', crudRouter('transactions', {
  filterFields: ['type', 'status', 'account_id', 'card_id', 'category_id', 'invoice_id', 'competence_date'],
}));

export default router;
