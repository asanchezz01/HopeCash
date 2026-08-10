import { z } from 'zod';
import { today } from '../../../utils/time.js';
import { idOrName, isoDate } from './shared.js';
import { proposeAction } from '../actions/service.js';

const money = z.coerce.number().positive();
const nullableRef = idOrName.nullish();
const familyId = z.string().uuid().nullish();

const writeTool = ({ name, description, inputSchema, paramsSchema }) => ({
  name,
  description: `${description} A ação sempre vira uma proposta e só é executada após confirmação explícita do usuário.`,
  scope: 'write',
  inputSchema,
  paramsSchema,
  handler: (auth, params, context) => proposeAction(name, auth, params, context),
});

export const createTransaction = writeTool({
  name: 'create_transaction',
  description: 'Propõe criar uma receita ou despesa, paga ou prevista.',
  inputSchema: {
    type: 'object',
    properties: {
      type: { type: 'string', enum: ['income', 'expense'] }, description: { type: 'string' },
      amount: { type: 'number' }, date: { type: 'string', description: 'Data YYYY-MM-DD' },
      due_date: { type: 'string', description: 'Vencimento YYYY-MM-DD, opcional' },
      paid: { type: 'boolean', description: 'Padrão true; compras no cartão ficam previstas' },
      account_id: {
        type: 'string',
        description: 'Id ou nome da conta de onde sai/entra o dinheiro. '
          + 'Informe sempre que souber: se ficar vazio ou não corresponder a '
          + 'nenhuma conta, o lançamento vai para a conta de débito principal '
          + 'do usuário e a resposta avisa qual foi usada.',
      },
      card_id: { type: 'string', description: 'Id ou nome do cartão' },
      category_id: { type: 'string', description: 'Id ou nome da categoria' },
      subcategory_id: { type: 'string', description: 'Id ou nome da subcategoria' },
      category_splits: { type: 'array', description: 'Rateio opcional; as partes devem somar amount', items: { type: 'object', properties: { category_id: { type: 'string', description: 'Id ou nome da categoria' }, subcategory_id: { type: 'string', description: 'Id ou nome da subcategoria' }, amount: { type: 'number' } }, required: ['category_id', 'amount'] } },
      notes: { type: 'string' }, family_id: { type: 'string' },
    },
    required: ['type', 'description', 'amount', 'date'],
  },
  paramsSchema: z.object({
    type: z.enum(['income', 'expense']), description: z.string().trim().min(1).max(200),
    amount: money, date: isoDate.default(() => today()), due_date: isoDate.nullish(),
    paid: z.coerce.boolean().default(true), account_id: nullableRef, card_id: nullableRef,
    category_id: nullableRef, subcategory_id: nullableRef,
    category_splits: z.array(z.object({ category_id: idOrName, subcategory_id: nullableRef, amount: money })).min(2).max(20).optional(),
    notes: z.string().max(2000).nullish(), family_id: familyId,
  }),
});

export const updateTransaction = writeTool({
  name: 'update_transaction',
  description: 'Propõe alterar um lançamento existente.',
  inputSchema: {
    type: 'object',
    properties: {
      transaction_id: { type: 'string', description: 'Id ou descrição do lançamento' },
      description: { type: 'string' }, amount: { type: 'number' }, date: { type: 'string' },
      due_date: { type: ['string', 'null'] }, notes: { type: ['string', 'null'] },
      account_id: { type: ['string', 'null'] }, card_id: { type: ['string', 'null'] },
      category_id: { type: ['string', 'null'] }, subcategory_id: { type: ['string', 'null'] },
      category_splits: { type: ['array', 'null'], items: { type: 'object', properties: { category_id: { type: 'string' }, subcategory_id: { type: 'string' }, amount: { type: 'number' } }, required: ['category_id', 'amount'] } },
    },
    required: ['transaction_id'],
  },
  paramsSchema: z.object({
    transaction_id: idOrName, description: z.string().trim().min(1).max(200).optional(),
    amount: money.optional(), date: isoDate.optional(), due_date: isoDate.nullish().optional(),
    notes: z.string().max(2000).nullish().optional(), account_id: nullableRef.optional(),
    card_id: nullableRef.optional(), category_id: nullableRef.optional(),
    subcategory_id: nullableRef.optional(),
    category_splits: z.array(z.object({ category_id: idOrName, subcategory_id: nullableRef, amount: money })).min(2).max(20).nullish().optional(),
  }),
});

export const payTransaction = writeTool({
  name: 'pay_transaction',
  description: 'Propõe dar baixa em um lançamento previsto, incluindo juros ou multa opcionais.',
  inputSchema: {
    type: 'object',
    properties: {
      transaction_id: { type: 'string', description: 'Id ou descrição do lançamento' },
      amount: { type: 'number', description: 'Total pago, incluindo juros/multa' },
      interest_amount: { type: 'number', description: 'Parcela do total referente a juros/multa' },
      date: { type: 'string', description: 'Data de pagamento YYYY-MM-DD' },
    },
    required: ['transaction_id', 'date'],
  },
  paramsSchema: z.object({
    transaction_id: idOrName, amount: money.optional(),
    interest_amount: z.coerce.number().min(0).default(0), date: isoDate.default(() => today()),
  }),
});

export const createTransfer = writeTool({
  name: 'create_transfer',
  description: 'Propõe uma transferência entre duas contas.',
  inputSchema: {
    type: 'object',
    properties: {
      from_account_id: { type: 'string', description: 'Id ou nome da conta de origem' },
      to_account_id: { type: 'string', description: 'Id ou nome da conta de destino' },
      amount: { type: 'number' }, date: { type: 'string' }, description: { type: 'string' },
    },
    required: ['from_account_id', 'to_account_id', 'amount', 'date'],
  },
  paramsSchema: z.object({
    from_account_id: idOrName, to_account_id: idOrName, amount: money,
    date: isoDate.default(() => today()),
    description: z.string().trim().min(1).max(200).default('Transferência entre contas'),
  }),
});

export const upsertBudgetItem = writeTool({
  name: 'upsert_budget_item',
  description: 'Propõe criar ou atualizar um item do orçamento mensal.',
  inputSchema: {
    type: 'object',
    properties: {
      month: { type: 'string', description: 'Mês YYYY-MM' },
      category_id: { type: 'string', description: 'Id ou nome da categoria' },
      subcategory_id: { type: 'string' }, planned_amount: { type: 'number' },
      is_fixed: { type: 'boolean' }, due_day: { type: 'integer' },
      account_id: { type: 'string' }, card_id: { type: 'string' }, family_id: { type: 'string' },
    },
    required: ['month', 'category_id', 'planned_amount'],
  },
  paramsSchema: z.object({
    month: z.string().regex(/^\d{4}-\d{2}$/), category_id: idOrName,
    subcategory_id: nullableRef, planned_amount: money,
    is_fixed: z.coerce.boolean().default(false), due_day: z.coerce.number().int().min(1).max(31).nullish(),
    account_id: nullableRef, card_id: nullableRef, family_id: familyId,
  }),
});

export const createGoal = writeTool({
  name: 'create_goal',
  description: 'Propõe criar uma meta financeira.',
  inputSchema: {
    type: 'object',
    properties: {
      name: { type: 'string' }, target_amount: { type: 'number' }, target_date: { type: 'string' },
      accumulated_amount: { type: 'number' }, linked_account_id: { type: 'string' }, family_id: { type: 'string' },
    },
    required: ['name', 'target_amount'],
  },
  paramsSchema: z.object({
    name: z.string().trim().min(1).max(120), target_amount: money, target_date: isoDate.nullish(),
    accumulated_amount: z.coerce.number().min(0).default(0), linked_account_id: nullableRef,
    family_id: familyId,
  }),
});

export const addGoalContribution = writeTool({
  name: 'add_goal_contribution',
  description: 'Propõe adicionar um aporte a uma meta financeira.',
  inputSchema: {
    type: 'object',
    properties: {
      goal_id: { type: 'string', description: 'Id ou nome da meta' }, amount: { type: 'number' },
      date: { type: 'string' }, account_id: { type: 'string' }, card_id: { type: 'string' },
    },
    required: ['goal_id', 'amount', 'date'],
  },
  paramsSchema: z.object({
    goal_id: idOrName, amount: money, date: isoDate.default(() => today()),
    account_id: nullableRef, card_id: nullableRef,
  }),
});

export const createCategory = writeTool({
  name: 'create_category',
  description: 'Propõe criar uma categoria de receita ou despesa.',
  inputSchema: {
    type: 'object',
    properties: {
      name: { type: 'string' }, type: { type: 'string', enum: ['income', 'expense'] },
      icon: { type: 'string' }, color: { type: 'string' }, family_id: { type: 'string' },
    },
    required: ['name', 'type'],
  },
  paramsSchema: z.object({
    name: z.string().trim().min(1).max(80), type: z.enum(['income', 'expense']),
    icon: z.string().max(40).nullish(), color: z.string().regex(/^#[0-9a-fA-F]{6,8}$/).nullish(),
    family_id: familyId,
  }),
});

export const WRITE_TOOLS = [
  createTransaction, updateTransaction, payTransaction, createTransfer,
  upsertBudgetItem, createGoal, addGoalContribution, createCategory,
];
