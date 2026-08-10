import { z } from 'zod';
import { syncRepo } from '../../../core/syncRepo.js';
import { round2 } from './shared.js';

export default {
  name: 'get_investments',
  description: 'Investimentos do usuário: valor aplicado, valor atual e rendimento (diferença entre os dois).',
  scope: 'read',
  inputSchema: { type: 'object', properties: {}, required: [] },
  paramsSchema: z.object({}).strict(),
  async handler(auth) {
    const investments = await syncRepo.list('investments', auth, { limit: 100 });
    const total_applied = round2(investments.reduce((s, i) => s + Number(i.applied_amount), 0));
    const total_current = round2(investments.reduce((s, i) => s + Number(i.current_amount), 0));
    return {
      investments: investments.map((i) => ({
        id: i.id,
        name: i.name,
        type: i.type,
        institution: i.institution,
        applied_amount: Number(i.applied_amount),
        current_amount: Number(i.current_amount),
        yield_amount: round2(Number(i.current_amount) - Number(i.applied_amount)),
        last_quote_date: i.last_quote_date,
      })),
      total_applied,
      total_current,
      total_yield: round2(total_current - total_applied),
    };
  },
};
