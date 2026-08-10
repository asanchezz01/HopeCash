import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { syncRepo } from '../../../core/syncRepo.js';
import { idOrName, resolveRefId } from './shared.js';

export default {
  name: 'get_invoices',
  description: 'Faturas de cartão de crédito (aberta, fechada, paga ou parcial), com total calculado e vencimento. Use para responder sobre valor e vencimento da fatura.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      card_id: { type: 'string', description: 'Id OU nome do cartão (ex.: "Nubank")' },
      status: { type: 'string', enum: ['open', 'closed', 'paid', 'partial'] },
    },
    required: [],
  },
  paramsSchema: z.object({
    card_id: idOrName.optional(),
    status: z.enum(['open', 'closed', 'paid', 'partial']).optional(),
  }),
  async handler(auth, { card_id, status }) {
    const filters = {};
    if (card_id) filters.card_id = await resolveRefId(auth, 'credit_cards', card_id);
    if (status) filters.status = status;
    const invoices = await syncRepo.list('credit_card_invoices', auth, { limit: 50, filters });
    const cards = await syncRepo.list('credit_cards', auth, { limit: 50 });
    const cardById = Object.fromEntries(cards.map((c) => [c.id, c]));

    for (const inv of invoices) {
      const [{ total }] = await db('transactions')
        .where({ invoice_id: inv.id }).whereNull('deleted_at').whereNot('status', 'canceled')
        .sum({ total: 'amount_planned' });
      inv.computed_total = Number(total ?? 0);
      inv.card = cardById[inv.card_id] ? { id: inv.card_id, name: cardById[inv.card_id].name } : null;
    }
    return { invoices };
  },
};
