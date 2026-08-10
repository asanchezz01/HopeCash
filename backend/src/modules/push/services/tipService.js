import { db } from '../../../db/knex.js';
import { logger } from '../../../logger.js';
import { enqueueForUser, hasRecentDelivery } from './deliveryService.js';
import { getAutomationRule } from './automationRulesService.js';
import { generateTip } from './tipGenerationService.js';

const DEFAULT_TITLE = 'Dica da Hope';
const DEFAULT_BODY = 'Revise assinaturas que você não usa mais — pequenos cortes fazem diferença no fim do mês.';

/**
 * Gera uma nova dica personalizada por IA para cada usuário elegível e a
 * enfileira com conteúdo imutável. Se a IA privada estiver indisponível para
 * um usuário, mantém a entrega usando o texto configurado na retaguarda como
 * fallback. Respeita o intervalo mínimo (`frequency_days`) entre envios.
 */
export async function processTips({ generatePersonalizedTip = generateTip } = {}) {
  const rule = await getAutomationRule('tip');
  if (!rule || !rule.enabled) return { evaluated: 0, enqueued: 0, disabled: true };

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
      'push_preferences.tips_enabled',
      'push_preferences.email_notifications_enabled',
    );

  const dateKey = new Date().toISOString().slice(0, 10);
  let enqueued = 0;
  let generated = 0;
  let fallback = 0;
  for (const row of users) {
    const pushEnabled = row.push_enabled == null ? true : !!row.push_enabled;
    const tipsEnabled = row.tips_enabled == null ? true : !!row.tips_enabled;
    const emailEnabled = row.email_notifications_enabled == null
      ? true
      : !!row.email_notifications_enabled;
    if (!tipsEnabled || (!pushEnabled && !emailEnabled)) continue;
    const userId = row.user_id;
    if (await hasRecentDelivery('tip', userId, rule.frequency_days)) continue;

    let content;
    try {
      const tip = await generatePersonalizedTip({ userId });
      content = {
        title: tip.title,
        body: tip.body,
        data: { type: 'tip' },
      };
      generated += 1;
    } catch (err) {
      logger.warn(
        { err: err.message, userId },
        'Falha ao gerar dica personalizada; usando conteúdo configurado',
      );
      content = await tipContent(rule);
      fallback += 1;
    }

    const result = await enqueueForUser({
      sourceType: 'tip',
      userId,
      idempotencyPrefix: `tip:${userId}:${dateKey}`,
      sendPush: pushEnabled,
      includeEmail: emailEnabled,
      content,
    });
    enqueued += result.created;
  }
  return { evaluated: users.length, enqueued, generated, fallback };
}

/** Conteúdo da dica — título/corpo configurados pela retaguarda (com fallback). */
export async function tipContent(existingRule) {
  const rule = existingRule ?? await getAutomationRule('tip');
  return {
    title: rule?.title || DEFAULT_TITLE,
    body: rule?.body || DEFAULT_BODY,
    deepLink: undefined,
    data: { type: 'tip' },
  };
}
