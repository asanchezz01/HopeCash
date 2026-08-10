import { z } from 'zod';
import { today, addDays } from '../../../utils/time.js';
import { getCashflowProjection } from '../../cashflow/cashflow.service.js';
import { isoDate } from './shared.js';

export default {
  name: 'get_cashflow_projection',
  description: 'Fluxo de caixa realizado e projetado por período (saldo acumulado, contas vencidas/a vencer, e períodos com risco de saldo negativo).',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      from: { type: 'string', description: 'Data inicial YYYY-MM-DD (padrão: hoje)' },
      to: { type: 'string', description: 'Data final YYYY-MM-DD (padrão: hoje + 90 dias)' },
      granularity: { type: 'string', enum: ['day', 'week', 'month', 'year'], description: 'Padrão: month' },
    },
    required: [],
  },
  paramsSchema: z.object({
    from: isoDate.default(() => today()),
    to: isoDate.default(() => addDays(today(), 90)),
    granularity: z.enum(['day', 'week', 'month', 'year']).default('month'),
  }),
  async handler(auth, params) {
    return getCashflowProjection(auth, params);
  },
};
