import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { authenticateRetaguarda } from '../../middleware/retaguardaAuth.js';
import { validate } from '../../middleware/validate.js';
import { llm } from '../ai/llm.js';
import authRoutes from './auth.routes.js';
import usersRoutes from './users.routes.js';
import appUsersRoutes from './appUsers.routes.js';
import notificationsRoutes from './notifications.routes.js';
import automationRulesRoutes from './automationRules.routes.js';
import mcpLogsRoutes from './mcpLogs.routes.js';

/**
 * Retaguarda (backoffice) do HopeCash. Autenticação e escopo próprios,
 * independentes do app. Montada em /api/v1/retaguarda.
 */
const router = Router();

// Rotas públicas da retaguarda (login/refresh/logout).
router.use('/auth', authRoutes);

// A partir daqui, tudo exige um usuário de retaguarda autenticado.
router.use(authenticateRetaguarda);

/** Indicadores para o painel inicial da retaguarda. */
router.get('/stats', validate(z.object({
  user_id: z.string().uuid().optional(),
}), 'query'), async (req, res) => {
  const userId = req.query.user_id;
  const countBusinessRows = (table, filters = {}) => {
    const query = db(table).whereNull('deleted_at').where(filters);
    if (userId) query.where({ user_id: userId });
    return query.count({ n: '*' }).first();
  };

  const [
    appTotal,
    appActive,
    appBlocked,
    rtgTotal,
    accounts,
    creditCards,
    debts,
    budgets,
    incomeTransactions,
    expenseTransactions,
  ] = await Promise.all([
    db('users').whereNull('deleted_at').count({ n: '*' }).first(),
    db('users').whereNull('deleted_at').where({ status: 'active' }).count({ n: '*' }).first(),
    db('users').whereNull('deleted_at').where({ status: 'blocked' }).count({ n: '*' }).first(),
    db('retaguarda_users').whereNull('deleted_at').count({ n: '*' }).first(),
    countBusinessRows('bank_accounts'),
    countBusinessRows('credit_cards'),
    countBusinessRows('debts'),
    countBusinessRows('budgets'),
    countBusinessRows('transactions', { type: 'income' }),
    countBusinessRows('transactions', { type: 'expense' }),
  ]);
  res.json({
    data: {
      app_users_total: Number(appTotal.n),
      app_users_active: Number(appActive.n),
      app_users_blocked: Number(appBlocked.n),
      retaguarda_users_total: Number(rtgTotal.n),
      accounts_total: Number(accounts.n),
      credit_cards_total: Number(creditCards.n),
      debts_total: Number(debts.n),
      budgets_total: Number(budgets.n),
      income_transactions_total: Number(incomeTransactions.n),
      expense_transactions_total: Number(expenseTransactions.n),
    },
  });
});

/** Estado do serviço Groq para o painel de monitoramento. */
router.get('/ai/health', async (_req, res) => {
  res.json({ data: await llm.health() });
});

router.use('/users', usersRoutes);
router.use('/app-users', appUsersRoutes);
router.use('/notifications', notificationsRoutes);
router.use('/automation-rules', automationRulesRoutes);
router.use('/mcp-logs', mcpLogsRoutes);

export default router;
