import { Router } from 'express';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { notFound } from '../../utils/httpError.js';
import { ENTITIES } from '../../core/registry.js';
import { validate } from '../../middleware/validate.js';

const router = Router();

router.get('/:id/movements', async (req, res) => {
  const investment = await syncRepo.findById('investments', req.auth, req.params.id);
  if (!investment) throw notFound('Investimento não encontrado');
  const movements = await syncRepo.list('investment_movements', req.auth, {
    limit: 500, filters: { investment_id: investment.id },
  });
  res.json({ data: movements });
});

/** Aporte/resgate: registra o movimento e ajusta os totais do investimento. */
router.post('/:id/movements', validate(ENTITIES.investment_movements.schema.omit({ investment_id: true })), async (req, res) => {
  const investment = await syncRepo.findById('investments', req.auth, req.params.id);
  if (!investment) throw notFound('Investimento não encontrado');
  const movement = await syncRepo.create('investment_movements', req.auth, {
    ...req.body, investment_id: investment.id,
  }, { req });

  const amount = Number(movement.amount);
  const patch = { current_amount: Number(investment.current_amount) };
  if (movement.type === 'deposit') {
    patch.applied_amount = Number(investment.applied_amount) + amount;
    patch.current_amount += amount;
  } else if (movement.type === 'withdrawal') {
    patch.current_amount -= amount;
  } else {
    patch.current_amount += amount; // rendimento
  }
  patch.last_quote_date = movement.movement_date;
  const updated = await syncRepo.update('investments', req.auth, investment.id, patch, { req });
  res.status(201).json({ data: { movement, investment: updated } });
});

router.use('/movements', crudRouter('investment_movements', { filterFields: ['investment_id'] }));
router.use('/', crudRouter('investments', { filterFields: ['type'] }));

export default router;
