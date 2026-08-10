import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';
import { round2 } from './shared.js';

export default {
  name: 'get_balances',
  description: 'Saldo atual de cada conta bancária ativa do usuário e o saldo total (soma das contas incluídas no total geral).',
  scope: 'read',
  inputSchema: { type: 'object', properties: {}, required: [] },
  paramsSchema: z.object({}).strict(),
  async handler(auth) {
    const accounts = await applyScope(db('bank_accounts'), 'bank_accounts', auth)
      .whereNull('deleted_at').where('is_active', true);
    const accountIds = accounts.map((a) => a.id);
    const paid = accountIds.length
      ? await applyScope(db('transactions'), 'transactions', auth)
          .whereNull('deleted_at').where('status', 'paid').whereIn('account_id', accountIds)
          .groupBy('account_id', 'type').select('account_id', 'type')
          .sum({ total: 'amount' })
      : [];
    const deltaByAccount = {};
    for (const r of paid) {
      deltaByAccount[r.account_id] = (deltaByAccount[r.account_id] ?? 0)
        + (r.type === 'income' ? Number(r.total ?? 0) : -Number(r.total ?? 0));
    }
    const balances = accounts.map((a) => ({
      id: a.id,
      name: a.name,
      type: a.type,
      balance: round2(Number(a.initial_balance) + (deltaByAccount[a.id] ?? 0)),
      include_in_total: !!a.include_in_total,
    }));
    const total_balance = round2(balances.filter((a) => a.include_in_total).reduce((s, a) => s + a.balance, 0));
    return { accounts: balances, total_balance };
  },
};
