import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { logger } from '../../../logger.js';
import { addMonths, today } from '../../../utils/time.js';
import { HttpError, notFound } from '../../../utils/httpError.js';
import { llm, LlmError } from '../../ai/llm.js';

const TIP_OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'body'],
  properties: {
    title: { type: 'string', minLength: 3, maxLength: 60 },
    body: { type: 'string', minLength: 20, maxLength: 220 },
  },
};

const tipOutputSchema = z.object({
  title: z.string().trim().min(3).max(60),
  body: z.string().trim().min(20).max(220),
});

const SYSTEM_PROMPT = `Você é a Hope, uma especialista brasileira em finanças pessoais, educação financeira comportamental e comunicação para aplicativos.

Sua tarefa é escrever UMA dica financeira excelente para uma notificação push. A dica precisa ser correta, prática, acolhedora e útil hoje — nunca genérica, moralista ou alarmista.

Regras obrigatórias:
- Escreva em português do Brasil, com linguagem simples, humana e positiva.
- Entregue uma única ação concreta, pequena e executável. Explique brevemente o benefício.
- Não recomende produtos, instituições, investimentos específicos, crédito ou promessas de retorno.
- Não use culpa, medo, julgamento, ordens agressivas, clichês ou garantias de resultado.
- Não faça diagnóstico financeiro e não se apresente como consultoria individual.
- Não use emojis, hashtags, markdown, listas, quebras de linha ou chamada para comprar algo.
- O título deve ter no máximo 60 caracteres e despertar interesse sem sensacionalismo.
- O corpo deve ter entre 20 e 220 caracteres, ser autossuficiente e caber bem em uma notificação.
- Retorne somente JSON válido com as chaves "title" e "body".

Quando houver um resumo financeiro:
- Baseie a dica no sinal mais relevante e acionável presente nos dados; não invente fatos ausentes.
- Preserve a privacidade da tela bloqueada: não cite nome, valores exatos, saldo, renda, dívida, instituição, conta, descrição de lançamento ou qualquer dado identificável.
- Você pode mencionar tendências ou categorias somente quando isso tornar a ação claramente mais útil.
- Se os dados forem insuficientes, produza uma dica geral segura em vez de fingir personalização.`;

const round2 = (value) => Math.round(Number(value ?? 0) * 100) / 100;

async function buildFinancialSnapshot(userId) {
  const user = await db('users')
    .where({ id: userId, status: 'active' })
    .whereNull('deleted_at')
    .first('id');
  if (!user) throw notFound('Usuário ativo não encontrado');

  const referenceMonth = today().slice(0, 7);
  const referenceMonthStart = `${referenceMonth}-01`;
  const [transactions, debts, goals, accounts, accountMovements, budget] = await Promise.all([
    db('transactions')
      .where({ user_id: userId })
      .whereNull('deleted_at')
      .whereNot('status', 'canceled')
      .where('competence_date', '>=', referenceMonthStart)
      .where('competence_date', '<', addMonths(referenceMonthStart, 1))
      .select('type', 'status', 'amount', 'amount_planned', 'category_id', 'due_date'),
    db('debts').where({ user_id: userId, status: 'active' }).whereNull('deleted_at')
      .select('outstanding_balance', 'interest_rate_monthly', 'installment_amount'),
    db('goals').where({ user_id: userId, status: 'active' }).whereNull('deleted_at')
      .select('target_amount', 'accumulated_amount', 'target_date'),
    db('bank_accounts').where({ user_id: userId, is_active: true, include_in_total: true })
      .whereNull('deleted_at').select('id', 'initial_balance'),
    db('transactions').where({ user_id: userId, status: 'paid' }).whereNull('deleted_at')
      .whereNotNull('account_id').select('account_id', 'type', 'amount'),
    db('budgets').where({ user_id: userId, reference_month: `${referenceMonth}-01` })
      .whereNull('deleted_at').first('id'),
  ]);

  let income = 0;
  let expense = 0;
  let overdueCount = 0;
  const categoryTotals = new Map();
  for (const row of transactions) {
    const amount = Number((row.status === 'paid' ? row.amount : row.amount_planned ?? row.amount) ?? 0);
    if (row.type === 'income') income += amount;
    if (row.type === 'expense') {
      expense += amount;
      if (row.category_id) categoryTotals.set(row.category_id, (categoryTotals.get(row.category_id) ?? 0) + amount);
    }
    if (row.status === 'overdue' || (row.status === 'planned' && row.due_date && String(row.due_date) < today())) {
      overdueCount += 1;
    }
  }

  const categoryIds = [...categoryTotals.keys()];
  const categories = categoryIds.length
    ? await db('categories').whereIn('id', categoryIds).select('id', 'name')
    : [];
  const categoryNames = new Map(categories.map((row) => [row.id, row.name]));
  const topExpenseCategories = categoryIds
    .map((id) => ({ category: categoryNames.get(id) ?? 'Sem categoria', amount: round2(categoryTotals.get(id)) }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 3);

  const accountIds = new Set(accounts.map((row) => row.id));
  let totalBalance = accounts.reduce((sum, row) => sum + Number(row.initial_balance ?? 0), 0);
  for (const row of accountMovements) {
    if (!accountIds.has(row.account_id)) continue;
    totalBalance += row.type === 'income' ? Number(row.amount ?? 0) : -Number(row.amount ?? 0);
  }

  let budgetSummary = null;
  if (budget) {
    const items = await db('budget_items').where({ budget_id: budget.id }).whereNull('deleted_at')
      .select('category_id', 'planned_amount');
    const planned = items.reduce((sum, row) => sum + Number(row.planned_amount ?? 0), 0);
    const spent = items.reduce((sum, row) => sum + (categoryTotals.get(row.category_id) ?? 0), 0);
    budgetSummary = {
      planned: round2(planned),
      spent: round2(spent),
      percent_used: planned > 0 ? Math.round((spent / planned) * 100) : null,
      exceeded_categories: items.filter((row) => (categoryTotals.get(row.category_id) ?? 0) > Number(row.planned_amount)).length,
    };
  }

  const totalDebt = debts.reduce((sum, row) => sum + Number(row.outstanding_balance ?? 0), 0);
  const highestDebtRate = debts.reduce((max, row) => Math.max(max, Number(row.interest_rate_monthly ?? 0)), 0);
  const goalsProgress = goals.map((row) => ({
    percent: Number(row.target_amount) > 0
      ? Math.round((Number(row.accumulated_amount ?? 0) / Number(row.target_amount)) * 100)
      : 0,
    has_deadline: !!row.target_date,
  }));

  return {
    reference_month: referenceMonth,
    month: {
      income: round2(income),
      expense: round2(expense),
      result: round2(income - expense),
      savings_rate_percent: income > 0 ? Math.round(((income - expense) / income) * 100) : null,
      overdue_count: overdueCount,
      top_expense_categories: topExpenseCategories,
    },
    total_balance: round2(totalBalance),
    budget: budgetSummary,
    debts: {
      active_count: debts.length,
      outstanding_total: round2(totalDebt),
      highest_monthly_interest_percent: round2(highestDebtRate),
    },
    goals: { active_count: goals.length, progress: goalsProgress.slice(0, 3) },
  };
}

const cleanSingleLine = (value) => value.replace(/\s+/g, ' ').trim();

/** Gera uma dica geral ou personalizada usando o provedor LLM disponível. */
export async function generateTip({ userId } = {}) {
  const snapshot = userId ? await buildFinancialSnapshot(userId) : null;
  const request = snapshot
    ? `Crie uma dica personalizada a partir deste resumo financeiro agregado:\n${JSON.stringify(snapshot)}`
    : 'Crie uma nova dica geral e original sobre finanças pessoais. Escolha um tema de alto impacto prático para o dia a dia.';

  let raw;
  try {
    raw = await llm.chatJson({
      model: llm.models.default,
      modelKey: 'default',
      format: TIP_OUTPUT_SCHEMA,
      temperature: 0.7,
      // O primeiro uso após ociosidade pode precisar recarregar o modelo.
      timeoutMs: 120_000,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: request },
      ],
    });
  } catch (err) {
    if (!(err instanceof LlmError)) throw err;
    logger.warn({ err: err.message }, 'Falha ao gerar dica financeira no LLM');
    throw new HttpError(503, 'AI_UNAVAILABLE', 'A geração de dicas está indisponível agora');
  }

  const parsed = tipOutputSchema.safeParse(raw);
  if (!parsed.success) {
    logger.warn({ raw }, 'Dica gerada fora do formato esperado');
    throw new HttpError(503, 'AI_UNAVAILABLE', 'A IA não conseguiu gerar uma dica válida');
  }
  return {
    title: cleanSingleLine(parsed.data.title),
    body: cleanSingleLine(parsed.data.body),
    personalized: !!userId,
    target_user_id: userId ?? null,
  };
}
