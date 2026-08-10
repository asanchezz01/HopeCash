import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { ENTITIES } from '../../core/registry.js';
import { notFound, badRequest } from '../../utils/httpError.js';
import { today } from '../../utils/time.js';

const router = Router();

/** Faturas de um cartão, com total calculado a partir das transações vinculadas. */
router.get('/:cardId/invoices', async (req, res) => {
  const card = await syncRepo.findById('credit_cards', req.auth, req.params.cardId);
  if (!card) throw notFound('Cartão não encontrado');
  const invoices = await syncRepo.list('credit_card_invoices', req.auth, {
    limit: 100, filters: { card_id: card.id },
  });
  for (const inv of invoices) {
    const [{ total }] = await db('transactions')
      .where({ invoice_id: inv.id }).whereNull('deleted_at').whereNot('status', 'canceled')
      .sum({ total: 'amount_planned' });
    inv.computed_total = Number(total ?? 0);
  }
  res.json({ data: invoices });
});

router.post('/:cardId/invoices', validate(ENTITIES.credit_card_invoices.schema.omit({ card_id: true })), async (req, res) => {
  const card = await syncRepo.findById('credit_cards', req.auth, req.params.cardId);
  if (!card) throw notFound('Cartão não encontrado');
  const invoice = await syncRepo.create('credit_card_invoices', req.auth, {
    ...req.body, card_id: card.id,
  }, { req });
  res.status(201).json({ data: invoice });
});

/** Pagamento de fatura: cria a despesa na conta indicada e atualiza o status da fatura. */
router.post('/:cardId/invoices/:invoiceId/pay', validate(z.object({
  account_id: z.string().uuid(),
  amount: z.coerce.number().positive(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).default(() => today()),
})), async (req, res) => {
  const card = await syncRepo.findById('credit_cards', req.auth, req.params.cardId);
  if (!card) throw notFound('Cartão não encontrado');
  const invoice = await syncRepo.findById('credit_card_invoices', req.auth, req.params.invoiceId);
  if (!invoice || invoice.card_id !== card.id) throw notFound('Fatura não encontrada');
  if (invoice.status === 'paid') throw badRequest('Fatura já está paga');

  const payment = await syncRepo.create('transactions', req.auth, {
    type: 'expense',
    description: `Pagamento fatura ${card.name}`,
    amount: req.body.amount,
    amount_planned: req.body.amount,
    competence_date: req.body.date,
    payment_date: req.body.date,
    status: 'paid',
    account_id: req.body.account_id,
  }, { req });

  const paidTotal = Number(invoice.paid_amount) + req.body.amount;
  const status = paidTotal >= Number(invoice.total_amount) ? 'paid' : 'partial';
  const updated = await syncRepo.update('credit_card_invoices', req.auth, invoice.id, {
    paid_amount: paidTotal,
    status,
    payment_transaction_id: payment.id,
  }, { req });

  res.json({ data: { invoice: updated, payment } });
});

router.use('/invoices', crudRouter('credit_card_invoices', { filterFields: ['card_id', 'status'] }));
router.use('/', crudRouter('credit_cards', { filterFields: ['is_active'] }));

export default router;
