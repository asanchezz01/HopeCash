import { z } from 'zod';
import { syncRepo } from '../../../core/syncRepo.js';
import { round2 } from './shared.js';

export default {
  name: 'get_debts',
  description: 'Dívidas e financiamentos do usuário: saldo devedor, parcelas pagas/totais, valor da parcela e taxa de juros mensal.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: { status: { type: 'string', enum: ['active', 'paid_off', 'renegotiated'], description: 'Padrão: active' } },
    required: [],
  },
  paramsSchema: z.object({ status: z.enum(['active', 'paid_off', 'renegotiated']).default('active') }),
  async handler(auth, { status }) {
    const debts = await syncRepo.list('debts', auth, { limit: 100, filters: { status } });
    const total_outstanding = round2(debts.reduce((s, d) => s + Number(d.outstanding_balance), 0));
    return {
      debts: debts.map((d) => ({
        id: d.id,
        name: d.name,
        type: d.type,
        institution: d.institution,
        outstanding_balance: Number(d.outstanding_balance),
        installment_amount: Number(d.installment_amount),
        paid_installments: d.paid_installments,
        total_installments: d.total_installments,
        interest_rate_monthly: Number(d.interest_rate_monthly),
        due_day: d.due_day,
        status: d.status,
      })),
      total_outstanding,
    };
  },
};
