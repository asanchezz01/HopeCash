import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { notFound, badRequest } from '../../utils/httpError.js';
import { today } from '../../utils/time.js';

const router = Router();

/** Saldo de uma conta = saldo inicial + entradas pagas − saídas pagas + transferências. */
export async function accountBalance(auth, account, until = null) {
  const q = db('transactions')
    .where({ account_id: account.id, status: 'paid' })
    .whereNull('deleted_at');
  if (until) q.where('payment_date', '<=', until);
  const rows = await q.select('type', 'amount');
  let balance = Number(account.initial_balance);
  for (const r of rows) {
    const amount = Number(r.amount ?? 0);
    balance += r.type === 'income' ? amount : -amount;
  }
  // Transferências recebidas (lado crédito é registrado como income na conta destino).
  return Math.round(balance * 100) / 100;
}

/** Transferência entre contas: cria par atômico débito/crédito ligado por transfer_group_id. */
router.post('/transfer', validate(z.object({
  from_account_id: z.string().uuid(),
  to_account_id: z.string().uuid(),
  amount: z.coerce.number().positive(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).default(() => today()),
  description: z.string().max(200).default('Transferência entre contas'),
})), async (req, res) => {
  const { from_account_id, to_account_id, amount, date, description } = req.body;
  if (from_account_id === to_account_id) throw badRequest('Contas de origem e destino devem ser diferentes');
  const from = await syncRepo.findById('bank_accounts', req.auth, from_account_id);
  const to = await syncRepo.findById('bank_accounts', req.auth, to_account_id);
  if (!from || !to) throw notFound('Conta não encontrada');

  const groupId = crypto.randomUUID();
  const common = {
    type: 'transfer',
    competence_date: date,
    payment_date: date,
    status: 'paid',
    amount,
    transfer_group_id: groupId,
  };
  const debit = await syncRepo.create('transactions', req.auth, {
    ...common,
    type: 'expense',
    description: `${description} → ${to.name}`,
    account_id: from_account_id,
    transfer_account_id: to_account_id,
  }, { req });
  const credit = await syncRepo.create('transactions', req.auth, {
    ...common,
    type: 'income',
    description: `${description} ← ${from.name}`,
    account_id: to_account_id,
    transfer_account_id: from_account_id,
  }, { req });
  res.status(201).json({ data: { transfer_group_id: groupId, debit, credit } });
});

/** Extrato com saldo corrente linha a linha. */
router.get('/:id/statement', async (req, res) => {
  const account = await syncRepo.findById('bank_accounts', req.auth, req.params.id);
  if (!account) throw notFound('Conta não encontrada');
  const from = req.query.from || null;
  const to = req.query.to || today();

  const q = db('transactions')
    .where({ account_id: account.id, status: 'paid' })
    .whereNull('deleted_at')
    .where('payment_date', '<=', to)
    .orderBy('payment_date')
    .orderBy('created_at');
  if (from) q.where('payment_date', '>=', from);
  const rows = await q;

  // Saldo anterior ao período solicitado.
  let running = Number(account.initial_balance);
  if (from) {
    const before = await db('transactions')
      .where({ account_id: account.id, status: 'paid' })
      .whereNull('deleted_at')
      .where('payment_date', '<', from)
      .select('type', 'amount');
    for (const r of before) running += r.type === 'income' ? Number(r.amount ?? 0) : -Number(r.amount ?? 0);
  }
  const opening_balance = Math.round(running * 100) / 100;

  const entries = rows.map((r) => {
    running += r.type === 'income' ? Number(r.amount ?? 0) : -Number(r.amount ?? 0);
    return {
      id: r.id,
      date: r.payment_date,
      description: r.description,
      type: r.type,
      amount: Number(r.amount ?? 0),
      balance: Math.round(running * 100) / 100,
    };
  });

  res.json({ data: { account: { id: account.id, name: account.name }, opening_balance, entries } });
});

/** Lista de contas enriquecida com saldo atual calculado. */
router.get('/balances', async (req, res) => {
  const accounts = await syncRepo.list('bank_accounts', req.auth, { limit: 200 });
  const data = [];
  for (const acc of accounts) {
    data.push({ ...acc, current_balance: await accountBalance(req.auth, acc) });
  }
  res.json({ data });
});

// CRUD padrão por último para não capturar as rotas específicas acima.
router.use('/', crudRouter('bank_accounts', { filterFields: ['type', 'is_active'] }));

export default router;
