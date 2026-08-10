import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';
import { today } from '../../../utils/time.js';
import { isoDate, idOrName, resolveRefId } from './shared.js';

export default {
  name: 'list_transactions',
  description: 'Lista lançamentos (receitas, despesas ou transferências) do usuário com filtros por período, tipo, categoria, conta, cartão, status e busca por texto na descrição. Ordenado do mais recente para o mais antigo. Por padrão traz apenas lançamentos com competência até hoje — parcelas e lançamentos de meses futuros só aparecem com um período explícito (to), status "planned" ou include_future=true.',
  scope: 'read',
  inputSchema: {
    type: 'object',
    properties: {
      from: { type: 'string', description: 'Data de competência inicial YYYY-MM-DD' },
      to: { type: 'string', description: 'Data de competência final YYYY-MM-DD' },
      type: { type: 'string', enum: ['income', 'expense', 'transfer'] },
      status: { type: 'string', enum: ['planned', 'paid', 'overdue', 'canceled'] },
      category_id: { type: 'string', description: 'Id OU nome da categoria (ex.: "Mercado")' },
      account_id: { type: 'string', description: 'Id OU nome da conta (ex.: "Nubank")' },
      card_id: { type: 'string', description: 'Id OU nome do cartão' },
      on_credit_card: { type: 'boolean', description: 'true filtra lançamentos de qualquer cartão; use quando o usuário disser apenas "no cartão de crédito" sem citar um cartão específico' },
      include_future: { type: 'boolean', description: 'true inclui lançamentos com competência futura (ex.: parcelas a vencer); use apenas quando o usuário pedir explicitamente lançamentos futuros' },
      text: { type: 'string', description: 'Busca por trecho da descrição' },
      limit: { type: 'integer', description: 'Máximo de resultados (padrão 20, máx 100)' },
    },
    required: [],
  },
  paramsSchema: z.object({
    from: isoDate.optional(),
    to: isoDate.optional(),
    type: z.enum(['income', 'expense', 'transfer']).optional(),
    status: z.enum(['planned', 'paid', 'overdue', 'canceled']).optional(),
    category_id: idOrName.optional(),
    account_id: idOrName.optional(),
    card_id: idOrName.optional(),
    on_credit_card: z.coerce.boolean().optional(),
    include_future: z.coerce.boolean().optional(),
    text: z.string().max(200).optional(),
    limit: z.coerce.number().int().min(1).max(100).default(20),
  }),
  async handler(auth, params) {
    const [categoryId, accountId, cardId] = await Promise.all([
      resolveRefId(auth, 'categories', params.category_id),
      resolveRefId(auth, 'bank_accounts', params.account_id),
      resolveRefId(auth, 'credit_cards', params.card_id),
    ]);
    const q = applyScope(db('transactions'), 'transactions', auth).whereNull('deleted_at');
    if (params.from) q.where('competence_date', '>=', params.from);
    if (params.to) q.where('competence_date', '<=', params.to);
    // "Últimos lançamentos" são os já competentes: sem um teto explícito, as
    // parcelas futuras de compras parceladas apareceriam antes de tudo na
    // ordenação decrescente. Quem pede o futuro diz isso via to, include_future
    // ou status planned.
    if (!params.to && !params.include_future && params.status !== 'planned') {
      q.where('competence_date', '<=', today());
    }
    if (params.type) q.where('type', params.type);
    if (params.status) q.where('status', params.status);
    if (categoryId) q.where('category_id', categoryId);
    if (accountId) q.where('account_id', accountId);
    if (cardId) q.where('card_id', cardId);
    if (!cardId && params.on_credit_card === true) q.whereNotNull('card_id');
    if (!cardId && params.on_credit_card === false) q.whereNull('card_id');
    if (params.text) q.where('description', 'like', `%${params.text}%`);
    const rows = await q.orderBy('competence_date', 'desc').limit(params.limit).select(
      'id', 'type', 'description', 'amount', 'amount_planned',
      'competence_date', 'due_date', 'payment_date', 'status',
      'category_id', 'account_id', 'card_id',
    );
    return { transactions: rows, count: rows.length };
  },
};
