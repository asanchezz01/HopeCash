import { db } from '../../../db/knex.js';
import { today } from '../../../utils/time.js';
import { buildDeepLink } from '../deepLinks.js';
import { enqueueForUser, hasRecentDelivery } from './deliveryService.js';
import { getAutomationRule } from './automationRulesService.js';
import { findBudgetForMonth, getBudgetSummary } from '../../budgets/budgets.service.js';

const DEFAULT_THRESHOLD_PERCENT = 90;
const DEFAULT_TITLE = 'Fique de olho no seu orçamento';
const DEFAULT_BODY = 'Uma categoria do seu orçamento está perto do limite. Toque para conferir.';

const parseConfig = (rule) => {
  if (!rule?.config) return {};
  try {
    return JSON.parse(rule.config);
  } catch {
    return {};
  }
};

/**
 * Alguma categoria de despesa do orçamento pessoal do mês atual já atingiu o
 * limite configurado? Reaproveita o mesmo cálculo previsto×realizado usado em
 * `GET /budgets/:id/summary` — nunca duplica a lógica de orçamento.
 * Escopo deliberadamente simples: só orçamento pessoal (não considera
 * orçamentos de família) — suficiente para o alerta de insight.
 */
async function hasBudgetOverrun(userId, thresholdPercent) {
  const auth = { userId, familyIds: [] };
  const budget = await findBudgetForMonth(auth, today().slice(0, 7));
  if (!budget) return false;
  const summary = await getBudgetSummary(auth, budget);
  return summary.items.some((item) => item.category?.type === 'expense'
    && item.percent_used != null && item.percent_used >= thresholdPercent);
}

/**
 * Verifica orçamento de usuários que optaram por insights financeiros e
 * enfileira um alerta genérico (sem valores/categorias) quando alguma
 * categoria de despesa está perto do limite. Respeita o intervalo mínimo
 * (`frequency_days`) entre insights ao mesmo usuário. Controlado pela regra
 * de automação `financial_insight`.
 */
export async function processFinancialInsights() {
  const rule = await getAutomationRule('financial_insight');
  if (!rule || !rule.enabled) return { evaluated: 0, enqueued: 0, disabled: true };
  const thresholdPercent = parseConfig(rule).threshold_percent ?? DEFAULT_THRESHOLD_PERCENT;

  // LEFT JOIN de propósito: a preferência só é criada no primeiro acesso do
  // usuário a /push/preferences — sem linha, os padrões (tudo habilitado)
  // valem, igual ao worker de avisos de vencimento.
  const users = await db('users')
    .leftJoin('push_preferences', 'push_preferences.user_id', 'users.id')
    .whereNull('users.deleted_at')
    .where('users.status', 'active')
    .select(
      'users.id as user_id',
      'push_preferences.push_enabled',
      'push_preferences.financial_insights_enabled',
      'push_preferences.email_notifications_enabled',
    );

  const dateKey = new Date().toISOString().slice(0, 10);
  let enqueued = 0;
  for (const row of users) {
    const pushEnabled = row.push_enabled == null ? true : !!row.push_enabled;
    const insightsEnabled = row.financial_insights_enabled == null ? true : !!row.financial_insights_enabled;
    const emailEnabled = row.email_notifications_enabled == null
      ? true
      : !!row.email_notifications_enabled;
    if ((!pushEnabled && !emailEnabled) || !insightsEnabled) continue;
    const userId = row.user_id;
    if (await hasRecentDelivery('financial_insight', userId, rule.frequency_days)) continue;
    if (!(await hasBudgetOverrun(userId, thresholdPercent))) continue;

    const result = await enqueueForUser({
      sourceType: 'financial_insight',
      userId,
      idempotencyPrefix: `financial_insight:${userId}:${dateKey}`,
      sendPush: pushEnabled,
      includeEmail: emailEnabled,
    });
    enqueued += result.created;
  }
  return { evaluated: users.length, enqueued };
}

/** Conteúdo do insight — título/corpo configurados pela retaguarda (com fallback). */
export async function financialInsightContent() {
  const rule = await getAutomationRule('financial_insight');
  return {
    title: rule?.title || DEFAULT_TITLE,
    body: rule?.body || DEFAULT_BODY,
    deepLink: buildDeepLink('/more/budget'),
    data: { type: 'financial_insight' },
  };
}
