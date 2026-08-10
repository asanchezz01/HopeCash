import crypto from 'node:crypto';
import { db } from '../../../db/knex.js';
import { now } from '../../../utils/time.js';
import { logger } from '../../../logger.js';
import { config } from '../../../config.js';
import { getPushProvider, getEmailNotificationProvider } from '../providers/index.js';
import { markDevicePermanentlyFailed } from './deviceService.js';
import { renderNotificationEmail } from '../emailTemplate.js';

const MAX_ATTEMPTS = 6;
const BASE_BACKOFF_MS = 30_000; // 30s
const MAX_BACKOFF_MS = 30 * 60_000; // 30min

/** Backoff exponencial com jitter (até +20%), limitado a MAX_BACKOFF_MS. */
export function nextBackoffDelayMs(attempts) {
  const exp = Math.min(BASE_BACKOFF_MS * 2 ** Math.max(attempts - 1, 0), MAX_BACKOFF_MS);
  return Math.round(exp + Math.random() * exp * 0.2);
}

const isUniqueViolation = (err) => /unique|duplicate/i.test(err?.message ?? '');

/**
 * Enfileira uma entrega pendente, idempotente pela `idempotencyKey`. Se já
 * existir uma entrega com a mesma chave (reprocessamento, corrida entre
 * instâncias do worker), o insert é ignorado silenciosamente.
 */
export async function enqueueDelivery({
  campaignId = null, sourceType, sourceId = null, reminderKind = null, userId, deviceId = null,
  channel = 'push', idempotencyKey, content = null,
}) {
  const ts = now();
  const row = {
    id: crypto.randomUUID(),
    campaign_id: campaignId,
    source_type: sourceType,
    source_id: sourceId,
    reminder_kind: reminderKind,
    user_id: userId,
    device_id: deviceId,
    channel,
    status: 'pending',
    attempts: 0,
    next_attempt_at: ts,
    idempotency_key: idempotencyKey,
    notification_content: content ? JSON.stringify(content) : null,
    created_at: ts,
    updated_at: ts,
  };
  try {
    await db('push_deliveries').insert(row);
    return row;
  } catch (err) {
    if (isUniqueViolation(err)) return null; // já enfileirada — idempotente
    throw err;
  }
}

/**
 * Enfileira a mensagem para um usuário, escolhendo o canal automaticamente:
 * um `push_deliveries` por dispositivo push ativo; sem nenhum dispositivo
 * ativo, cai para uma única entrega por e-mail — se o usuário não desativou
 * esse canal em `push_preferences.email_notifications_enabled` (padrão:
 * ativado). Com `includeEmail`, cria também a entrega por e-mail mesmo quando
 * há push (usado pelas Dicas da Hope). `idempotencyPrefix` recebe
 * `:<deviceId>` (push) ou `:email`.
 */
export async function enqueueForUser({
  sourceType, campaignId = null, sourceId = null, reminderKind = null, userId, idempotencyPrefix,
  sendPush = true, includeEmail = true, content = null,
}) {
  const devices = sendPush
    ? await db('push_devices').where({ user_id: userId, is_active: true })
    : [];
  let pushCreated = 0;
  if (devices.length) {
    for (const device of devices) {
      const row = await enqueueDelivery({
        campaignId, sourceType, sourceId, reminderKind, userId, deviceId: device.id, channel: 'push',
        idempotencyKey: `${idempotencyPrefix}:${device.id}`, content,
      });
      if (row) pushCreated += 1;
    }
    if (!includeEmail) return { channel: 'push', created: pushCreated };
  }

  const prefs = await db('push_preferences').where({ user_id: userId }).first();
  const emailEnabled = prefs ? !!prefs.email_notifications_enabled : true;
  if (!emailEnabled) {
    return { channel: devices.length ? 'push' : 'none', created: pushCreated };
  }

  const row = await enqueueDelivery({
    campaignId, sourceType, sourceId, reminderKind, userId, deviceId: null, channel: 'email',
    idempotencyKey: `${idempotencyPrefix}:email`, content,
  });
  const emailCreated = row ? 1 : 0;
  return {
    channel: devices.length ? 'push+email' : 'email',
    created: pushCreated + emailCreated,
  };
}

/** Reivindica atomicamente uma entrega pendente (1 UPDATE por linha) — seguro entre múltiplas instâncias do worker. */
async function claimDelivery(id) {
  const affected = await db('push_deliveries')
    .where({ id, status: 'pending' })
    .update({ status: 'sending', updated_at: now() });
  return affected === 1;
}

/** Finaliza o status agregado da campanha quando não há mais entregas pendentes/em andamento. */
async function maybeFinalizeCampaign(campaignId) {
  if (!campaignId) return;
  const inFlight = await db('push_deliveries')
    .where({ campaign_id: campaignId })
    .whereIn('status', ['pending', 'sending'])
    .count({ n: '*' })
    .first();
  if (Number(inFlight.n) > 0) return;

  const [success, failure] = await Promise.all([
    db('push_deliveries').where({ campaign_id: campaignId, status: 'sent' }).count({ n: '*' }).first(),
    db('push_deliveries').where({ campaign_id: campaignId, status: 'failed' }).count({ n: '*' }).first(),
  ]);
  const successTotal = Number(success.n);
  const failureTotal = Number(failure.n);
  // Uma campanha só é "sent" quando ao menos uma entrega foi confirmada pelo
  // provedor e nenhuma modalidade falhou. Zero confirmações nunca é sucesso.
  const status = successTotal === 0 ? 'failed' : failureTotal > 0 ? 'partially_sent' : 'sent';

  const campaign = await db('push_campaigns').where({ id: campaignId }).first();
  if (!campaign || campaign.status !== 'processing') return; // já finalizada por outra chamada
  await db('push_campaigns').where({ id: campaignId }).update({
    status,
    success_total: successTotal,
    failure_total: failureTotal,
    sent_at: now(),
    updated_at: now(),
  });
}

/** Processa uma única entrega já reivindicada: envia (push ou e-mail) e grava o resultado. */
async function processDelivery(delivery) {
  if (delivery.channel === 'email') {
    await processEmailDelivery(delivery);
    return;
  }

  const device = await db('push_devices').where({ id: delivery.device_id }).first();
  const ts = now();

  if (!device || !device.is_active) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: 'Dispositivo inativo ou removido',
      attempts: delivery.attempts + 1,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  const content = await buildDeliveryContent(delivery);
  const result = await getPushProvider().send({
    token: device.token,
    title: content.title,
    body: content.body,
    data: content.data,
    deepLink: content.deepLink,
  });

  if (result.dryRun) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: 'Push não entregue: provedor desabilitado (dry-run)',
      attempts: delivery.attempts + 1,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  if (result.ok) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'sent',
      provider_message_id: result.messageId ?? null,
      attempts: delivery.attempts + 1,
      sent_at: ts,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  const attempts = delivery.attempts + 1;
  if (result.permanent) {
    await markDevicePermanentlyFailed(device.id, result.errorCode);
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: result.error ?? result.errorCode,
      attempts,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  if (attempts >= MAX_ATTEMPTS) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: `Tentativas esgotadas: ${result.error ?? result.errorCode}`,
      attempts,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  const delayMs = nextBackoffDelayMs(attempts);
  await db('push_deliveries').where({ id: delivery.id }).update({
    status: 'pending',
    error: result.error ?? result.errorCode,
    attempts,
    next_attempt_at: new Date(Date.now() + delayMs).toISOString().slice(0, 23).replace('T', ' '),
    updated_at: ts,
  });
}

/**
 * Entrega pelo canal de e-mail. Sem
 * conceito de "token inválido" — qualquer falha (SMTP fora do ar, etc.) é tratada como
 * temporária e entra no mesmo backoff. `MAIL_ENABLED=false` conta como
 * sucesso (dry-run), igual ao provedor push desabilitado.
 */
async function processEmailDelivery(delivery) {
  const ts = now();
  const user = await db('users').where({ id: delivery.user_id }).first();
  if (!user || !user.email) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: 'Usuário sem e-mail cadastrado',
      attempts: delivery.attempts + 1,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  const content = await buildDeliveryContent(delivery);
  const actionUrl = content.deepLink && config.push.emailAppUrl
    ? `${config.push.emailAppUrl}${content.deepLink}`
    : undefined;
  const { html, text } = renderNotificationEmail({ title: content.title, body: content.body, actionUrl });
  const result = await getEmailNotificationProvider().send({
    to: user.email, subject: content.title, html, text,
  });

  if (result.dryRun) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: 'E-mail não entregue: provedor desabilitado (dry-run)',
      attempts: delivery.attempts + 1,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  if (result.ok) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'sent', attempts: delivery.attempts + 1, sent_at: ts, processed_at: ts, updated_at: ts,
    });
    return;
  }

  const attempts = delivery.attempts + 1;
  if (attempts >= MAX_ATTEMPTS) {
    await db('push_deliveries').where({ id: delivery.id }).update({
      status: 'failed',
      error: `Tentativas esgotadas: ${result.error}`,
      attempts,
      processed_at: ts,
      updated_at: ts,
    });
    return;
  }

  const delayMs = nextBackoffDelayMs(attempts);
  await db('push_deliveries').where({ id: delivery.id }).update({
    status: 'pending',
    error: result.error,
    attempts,
    next_attempt_at: new Date(Date.now() + delayMs).toISOString().slice(0, 23).replace('T', ' '),
    updated_at: ts,
  });
}

/**
 * Conteúdo efetivo de uma entrega, resolvido por `source_type`. Campanhas
 * Quando a entrega tem `notification_content`, usa o conteúdo imutável
 * persistido no enfileiramento. Isso permite que uma dica personalizada por
 * IA seja gerada uma única vez e permaneça idêntica no push, e-mail e retries.
 * Sem conteúdo persistido, resolve pelo `source_type` como antes.
 * Compartilhado entre push e e-mail — o mesmo título/corpo/deep link vira
 * card de notificação ou e-mail, conforme o canal da entrega.
 * Os `import()` dinâmicos evitam ciclo de import (esses módulos importam
 * `enqueueDelivery`/`dispatchPendingDeliveries` deste arquivo).
 */
async function buildDeliveryContent(delivery) {
  if (delivery.notification_content) {
    try {
      const content = typeof delivery.notification_content === 'string'
        ? JSON.parse(delivery.notification_content)
        : delivery.notification_content;
      if (content?.title && content?.body) {
        return {
          title: content.title,
          body: content.body,
          deepLink: content.deepLink || undefined,
          data: content.data && typeof content.data === 'object' ? content.data : {},
        };
      }
    } catch (err) {
      logger.warn({ err: err.message, deliveryId: delivery.id }, 'Conteúdo persistido da notificação é inválido');
    }
  }

  switch (delivery.source_type) {
    case 'campaign': {
      const campaign = await db('push_campaigns').where({ id: delivery.campaign_id }).first();
      return {
        title: campaign?.title ?? 'HopeCash',
        body: campaign?.body ?? '',
        deepLink: campaign?.deep_link || undefined,
        data: { type: 'campaign', campaign_id: delivery.campaign_id ?? '' },
      };
    }
    case 'due_reminder': {
      const { dueReminderContent } = await import('./dueReminderService.js');
      return dueReminderContent(delivery);
    }
    case 'financial_insight': {
      const { financialInsightContent } = await import('./financialInsightService.js');
      return financialInsightContent();
    }
    case 'tip': {
      const { tipContent } = await import('./tipService.js');
      return tipContent();
    }
    default:
      return { title: 'HopeCash', body: '', deepLink: undefined, data: {} };
  }
}

/**
 * Já existe alguma entrega deste tipo para o usuário criada nos últimos
 * `minDays` dias? Usado pelos workers de mensagem automática (dica/insight)
 * para não enviar com mais frequência do que a configurada na retaguarda.
 */
export async function hasRecentDelivery(sourceType, userId, minDays) {
  if (!minDays || minDays <= 0) return false;
  const cutoff = new Date(Date.now() - minDays * 86_400_000).toISOString().slice(0, 23).replace('T', ' ');
  const row = await db('push_deliveries')
    .where({ source_type: sourceType, user_id: userId })
    .where('created_at', '>=', cutoff)
    .first('id');
  return !!row;
}

/**
 * Varre entregas pendentes prontas para (re)tentativa e as processa em lote.
 * Chamada tanto pelo scheduler quanto por "enviar agora"/"reprocessar".
 */
export async function dispatchPendingDeliveries({ limit = 200 } = {}) {
  const candidates = await db('push_deliveries')
    .where({ status: 'pending' })
    .andWhere((qb) => qb.whereNull('next_attempt_at').orWhere('next_attempt_at', '<=', now()))
    .orderBy('created_at', 'asc')
    .limit(limit)
    .select('id');

  const campaignIds = new Set();
  let processed = 0;
  for (const { id } of candidates) {
    const claimed = await claimDelivery(id);
    if (!claimed) continue; // outra instância já pegou esta entrega
    const delivery = await db('push_deliveries').where({ id }).first();
    try {
      await processDelivery(delivery);
    } catch (err) {
      logger.error({ err: err.message, deliveryId: id }, 'Falha inesperada ao processar entrega de push');
      await db('push_deliveries').where({ id }).update({
        status: 'pending',
        error: 'Erro interno ao processar — será tentado novamente',
        next_attempt_at: new Date(Date.now() + nextBackoffDelayMs(delivery.attempts + 1)).toISOString().slice(0, 23).replace('T', ' '),
        updated_at: now(),
      });
    }
    processed += 1;
    if (delivery.campaign_id) campaignIds.add(delivery.campaign_id);
  }

  for (const campaignId of campaignIds) await maybeFinalizeCampaign(campaignId);
  return { processed };
}

/** Reseta entregas falhas para nova tentativa imediata: push com dispositivo ainda ativo, ou e-mail (sem essa dependência). */
export async function resetFailedDeliveriesForRetry({ campaignId }) {
  const rows = await db('push_deliveries')
    .leftJoin('push_devices', 'push_devices.id', 'push_deliveries.device_id')
    .where('push_deliveries.campaign_id', campaignId)
    .where('push_deliveries.status', 'failed')
    .andWhere((qb) => qb.where('push_deliveries.channel', 'email').orWhere('push_devices.is_active', true))
    .select('push_deliveries.id');

  const ts = now();
  for (const { id } of rows) {
    await db('push_deliveries').where({ id }).update({
      status: 'pending', attempts: 0, error: null, next_attempt_at: ts, processed_at: null, updated_at: ts,
    });
  }
  if (rows.length) await db('push_campaigns').where({ id: campaignId }).update({ status: 'processing', updated_at: ts });
  return rows.length;
}

/** Usado no fluxo de exclusão de conta (LGPD) — remove o histórico de entregas do usuário. */
export async function deleteAllDeliveriesForUser(userId, trx) {
  await (trx ?? db)('push_deliveries').where({ user_id: userId }).del();
}

export { maybeFinalizeCampaign };
