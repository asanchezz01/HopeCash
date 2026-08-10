import { z } from 'zod';
import { syncRepo } from '../../../core/syncRepo.js';

export default {
  name: 'get_goals',
  description: 'Metas financeiras do usuário: valor alvo, valor acumulado, percentual atingido e prazo.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: { status: { type: 'string', enum: ['active', 'done', 'paused'], description: 'Padrão: active' } },
    required: [],
  },
  paramsSchema: z.object({ status: z.enum(['active', 'done', 'paused']).default('active') }),
  async handler(auth, { status }) {
    const goals = await syncRepo.list('goals', auth, { limit: 100, filters: { status } });
    return {
      goals: goals.map((g) => ({
        id: g.id,
        name: g.name,
        target_amount: Number(g.target_amount),
        accumulated_amount: Number(g.accumulated_amount),
        percent: g.target_amount > 0 ? Math.round((g.accumulated_amount / g.target_amount) * 100) : 0,
        target_date: g.target_date,
        status: g.status,
      })),
    };
  },
};
