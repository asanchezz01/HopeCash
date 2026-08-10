import crypto from 'node:crypto';
import { db } from '../../../db/knex.js';
import { now } from '../../../utils/time.js';
import { badRequest, notFound } from '../../../utils/httpError.js';
import { isAllowedDeepLink } from '../deepLinks.js';
import { enqueueForUser, dispatchPendingDeliveries, resetFailedDeliveriesForRetry } from './deliveryService.js';

const INSTANCE_ID = crypto.randomUUID();
const EDITABLE_STATUSES = ['draft', 'scheduled'];
const CANCELABLE_STATUSES = ['draft', 'scheduled'];
const SENDABLE_STATUSES = ['draft', 'scheduled'];
const DELIVERY_CHANNELS = ['push', 'email', 'both'];

const channelFlags = (channel = 'both') => {
  if (!DELIVERY_CHANNELS.includes(channel)) throw badRequest('Modalidade de envio inválida');
  return {
    push: channel === 'push' || channel === 'both',
    email: channel === 'email' || channel === 'both',
  };
};

const parseTargetIds = (campaign) => {
  if (!campaign.target_user_ids) return [];
  try {
    const parsed = JSON.parse(campaign.target_user_ids);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
};

/**
 * `getCampaignOrThrow`/as linhas cruas do banco guardam `target_user_ids` como
 * TEXT (JSON serializado) — igual ao resto do app faz com campos JSON. Esta
 * função prepara uma linha para sair pela API, com o campo já desserializado
 * (a mesma convenção que `syncRepo.deserialize` aplica às demais entidades).
 */
const emptyChannelCounters = () => ({ total: 0, pending: 0, sending: 0, sent: 0, failed: 0 });

const emptyDeliverySummary = () => ({ push: emptyChannelCounters(), email: emptyChannelCounters() });

const deliveryMode = (summary) => {
  const hasPush = summary.push.total > 0;
  const hasEmail = summary.email.total > 0;
  if (hasPush && hasEmail) return 'both';
  if (hasPush) return 'push';
  if (hasEmail) return 'email';
  return 'none';
};

const toApiCampaign = (campaign, deliverySummary = emptyDeliverySummary()) => ({
  ...campaign,
  target_user_ids: parseTargetIds(campaign),
  delivery_mode: deliveryMode(deliverySummary),
  delivery_summary: deliverySummary,
});

async function deliverySummaries(campaignIds) {
  const summaries = new Map(campaignIds.map((id) => [id, emptyDeliverySummary()]));
  if (!campaignIds.length) return summaries;
  const rows = await db('push_deliveries')
    .whereIn('campaign_id', campaignIds)
    .groupBy('campaign_id', 'channel', 'status')
    .select('campaign_id', 'channel', 'status')
    .count({ n: '*' });
  for (const row of rows) {
    const summary = summaries.get(row.campaign_id);
    if (!summary?.[row.channel] || !(row.status in summary[row.channel])) continue;
    const count = Number(row.n);
    summary[row.channel][row.status] = count;
    summary[row.channel].total += count;
  }
  return summaries;
}

async function campaignWithSummary(campaign) {
  const summaries = await deliverySummaries([campaign.id]);
  return toApiCampaign(campaign, summaries.get(campaign.id));
}

/**
 * Usuários elegíveis para uma campanha (conta ativa, preferências por categoria
 * e canal), com seus dispositivos push ativos e autorização de e-mail.
 */
async function resolveEligibleUsers(campaign, channel = 'both') {
  const requested = channelFlags(channel);
  let usersQuery = db('users').whereNull('deleted_at').where('status', 'active');
  if (campaign.audience === 'selected') {
    const ids = parseTargetIds(campaign);
    if (!ids.length) return [];
    usersQuery = usersQuery.whereIn('id', ids);
  }
  const userIds = (await usersQuery.select('id')).map((u) => u.id);
  if (!userIds.length) return [];

  const prefsRows = await db('push_preferences').whereIn('user_id', userIds);
  const prefsByUser = new Map(prefsRows.map((p) => [p.user_id, p]));
  const devices = await db('push_devices').whereIn('user_id', userIds).where('is_active', true);
  const devicesByUser = new Map();
  for (const device of devices) {
    if (!devicesByUser.has(device.user_id)) devicesByUser.set(device.user_id, []);
    devicesByUser.get(device.user_id).push(device);
  }
  const categoryField = campaign.category === 'tips'
    ? 'tips_enabled'
    : campaign.category === 'insights' ? 'financial_insights_enabled' : null;

  const eligibleUserIds = userIds.filter((id) => {
    const prefs = prefsByUser.get(id);
    const pushEnabled = prefs ? !!prefs.push_enabled : true;
    const emailEnabled = prefs ? !!prefs.email_notifications_enabled : true;
    const hasPushChannel = requested.push && pushEnabled && (devicesByUser.get(id)?.length ?? 0) > 0;
    const hasEmailChannel = requested.email && emailEnabled;
    if (categoryField && prefs && !prefs[categoryField]) return false;
    return hasPushChannel || hasEmailChannel;
  });
  if (!eligibleUserIds.length) return [];
  return eligibleUserIds.map((userId) => {
    const prefs = prefsByUser.get(userId);
    return {
      userId,
      devices: requested.push && (!prefs || prefs.push_enabled)
        ? (devicesByUser.get(userId) ?? [])
        : [],
      pushEnabled: requested.push && (prefs ? !!prefs.push_enabled : true),
      emailEnabled: requested.email && (prefs ? !!prefs.email_notifications_enabled : true),
    };
  });
}

export async function createDraftCampaign(payload, createdBy) {
  if (payload.deep_link && !isAllowedDeepLink(payload.deep_link)) {
    throw badRequest('Deep link não permitido', { deep_link: payload.deep_link });
  }
  if (payload.audience === 'selected' && !payload.target_user_ids?.length) {
    throw badRequest('Informe ao menos um usuário para o público selecionado');
  }
  const ts = now();
  const row = {
    id: crypto.randomUUID(),
    title: payload.title,
    body: payload.body,
    category: payload.category ?? 'general',
    audience: payload.audience ?? 'all',
    target_user_ids: payload.audience === 'selected' ? JSON.stringify(payload.target_user_ids) : null,
    deep_link: payload.deep_link ?? null,
    status: 'draft',
    created_by: createdBy,
    created_at: ts,
    updated_at: ts,
  };
  await db('push_campaigns').insert(row);
  return campaignWithSummary(await db('push_campaigns').where({ id: row.id }).first());
}

export async function getCampaignOrThrow(id) {
  const campaign = await db('push_campaigns').where({ id }).first();
  if (!campaign) throw notFound('Campanha não encontrada');
  return campaign;
}

export async function listCampaigns({ status, page = 1, limit = 20 } = {}) {
  const query = db('push_campaigns');
  if (status) query.where({ status });
  const total = await query.clone().count({ n: '*' }).first();
  const rows = await query.clone().orderBy('created_at', 'desc').limit(limit).offset((page - 1) * limit);
  const summaries = await deliverySummaries(rows.map((row) => row.id));
  return {
    data: rows.map((row) => toApiCampaign(row, summaries.get(row.id))),
    meta: { total: Number(total.n), page, limit },
  };
}

export async function getCampaign(id) {
  return campaignWithSummary(await getCampaignOrThrow(id));
}

/**
 * Lista os usuários destinatários de uma campanha sem expor e-mail ou outros
 * dados pessoais. Depois que o processamento termina, o histórico de entregas
 * é a fonte da verdade; antes disso, a lista representa a elegibilidade atual
 * e pode mudar até o momento do envio.
 */
export async function listCampaignRecipients(id, { page = 1, limit = 100 } = {}) {
  const campaign = await getCampaignOrThrow(id);
  const deliveredUserRows = await db('push_deliveries')
    .where({ campaign_id: id })
    .distinct('user_id');

  // Enquanto o worker ainda está enfileirando, o histórico pode estar parcial.
  // Só passa a ser a fonte da verdade após sair do estado de processamento.
  const usesDeliveryHistory = deliveredUserRows.length > 0 && campaign.status !== 'processing';
  const userIds = usesDeliveryHistory
    ? deliveredUserRows.map((row) => row.user_id)
    : (await resolveEligibleUsers(campaign)).map((recipient) => recipient.userId);

  if (!userIds.length) {
    return {
      data: [],
      meta: { total: 0, page, limit, source: usesDeliveryHistory ? 'delivery_history' : 'current_eligibility' },
    };
  }

  const usersQuery = db('users').whereIn('id', userIds);
  const totalRow = await usersQuery.clone().count({ n: '*' }).first();
  const rows = await usersQuery.clone()
    .select('id', 'name')
    .orderBy('name', 'asc')
    .orderBy('id', 'asc')
    .limit(limit)
    .offset((page - 1) * limit);

  return {
    data: rows,
    meta: {
      total: Number(totalRow.n),
      page,
      limit,
      source: usesDeliveryHistory ? 'delivery_history' : 'current_eligibility',
    },
  };
}

export async function updateCampaign(id, patch) {
  const campaign = await getCampaignOrThrow(id);
  if (!EDITABLE_STATUSES.includes(campaign.status)) {
    throw badRequest('Só é possível editar campanhas em rascunho ou agendadas');
  }
  if (patch.deep_link && !isAllowedDeepLink(patch.deep_link)) {
    throw badRequest('Deep link não permitido', { deep_link: patch.deep_link });
  }
  if ((patch.audience ?? campaign.audience) === 'selected' && patch.target_user_ids && !patch.target_user_ids.length) {
    throw badRequest('Informe ao menos um usuário para o público selecionado');
  }
  const update = { ...patch, updated_at: now() };
  if ('target_user_ids' in patch) {
    update.target_user_ids = patch.target_user_ids ? JSON.stringify(patch.target_user_ids) : null;
  }
  await db('push_campaigns').where({ id }).update(update);
  return campaignWithSummary(await getCampaignOrThrow(id));
}

export async function scheduleCampaign(id, { scheduledAt, timezone }) {
  const campaign = await getCampaignOrThrow(id);
  if (campaign.status !== 'draft') throw badRequest('Só é possível agendar uma campanha em rascunho');
  await db('push_campaigns').where({ id }).update({
    status: 'scheduled', scheduled_at: scheduledAt, scheduled_timezone: timezone ?? null, updated_at: now(),
  });
  return campaignWithSummary(await getCampaignOrThrow(id));
}

export async function cancelCampaign(id) {
  const campaign = await getCampaignOrThrow(id);
  if (!CANCELABLE_STATUSES.includes(campaign.status)) {
    throw badRequest('Só é possível cancelar campanhas em rascunho ou agendadas');
  }
  await db('push_campaigns').where({ id }).update({ status: 'canceled', canceled_at: now(), updated_at: now() });
  return campaignWithSummary(await getCampaignOrThrow(id));
}

export async function previewCampaign(id, channel = 'both') {
  const campaign = await getCampaignOrThrow(id);
  const eligible = await resolveEligibleUsers(campaign, channel);
  const byPlatform = { web: 0, pwa: 0, android: 0, ios: 0 };
  let devicesTotal = 0;
  let emailTotal = 0;
  for (const user of eligible) {
    if (user.devices.length) {
      devicesTotal += user.devices.length;
      for (const device of user.devices) byPlatform[device.platform] = (byPlatform[device.platform] ?? 0) + 1;
    }
    if (user.emailEnabled) {
      emailTotal += 1;
    }
  }
  return {
    title: campaign.title,
    body: campaign.body,
    deep_link: campaign.deep_link,
    recipients_total: eligible.length,
    devices_total: devicesTotal,
    by_platform: byPlatform,
    email_total: emailTotal,
    // Compatibilidade com clientes anteriores ao envio multicanal.
    email_fallback_total: emailTotal,
    requested_channel: channel,
  };
}

/** Reivindica atomicamente a campanha (1 UPDATE) — só uma chamada concorrente ganha o processamento. */
async function claimCampaign(id) {
  const affected = await db('push_campaigns')
    .where({ id })
    .whereIn('status', ['draft', 'scheduled'])
    .update({ status: 'processing', claimed_at: now(), claimed_by: INSTANCE_ID, updated_at: now() });
  return affected === 1;
}

async function processCampaign(campaign, channel = 'both') {
  const eligible = await resolveEligibleUsers(campaign, channel);
  const recipientsTotal = eligible.length;

  if (!recipientsTotal) {
    await db('push_campaigns').where({ id: campaign.id }).update({
      status: 'failed', recipients_total: 0, success_total: 0, failure_total: 0, sent_at: null, updated_at: now(),
    });
    return;
  }

  await db('push_campaigns').where({ id: campaign.id }).update({ recipients_total: recipientsTotal, updated_at: now() });
  for (const { userId, pushEnabled, emailEnabled } of eligible) {
    await enqueueForUser({
      campaignId: campaign.id,
      sourceType: 'campaign',
      userId,
      idempotencyPrefix: `campaign:${campaign.id}`,
      sendPush: pushEnabled,
      includeEmail: emailEnabled,
    });
  }
  await dispatchPendingDeliveries();
}

/** "Enviar agora" — reivindica e processa imediatamente (chamada síncrona da rota). */
export async function sendCampaignNow(id, { channel = 'both' } = {}) {
  channelFlags(channel);
  const campaign = await getCampaignOrThrow(id);
  if (!SENDABLE_STATUSES.includes(campaign.status)) {
    throw badRequest('Campanha já foi enviada, está em processamento ou foi cancelada');
  }
  const claimed = await claimCampaign(id);
  if (!claimed) throw badRequest('Campanha já está sendo processada');
  await processCampaign(await getCampaignOrThrow(id), channel);
  return campaignWithSummary(await getCampaignOrThrow(id));
}

/** Chamada pelo scheduler: processa campanhas agendadas cuja data já chegou. */
export async function processDueScheduledCampaigns() {
  const due = await db('push_campaigns')
    .where('status', 'scheduled')
    .where('scheduled_at', '<=', now())
    .select('id');
  let processed = 0;
  for (const { id } of due) {
    if (await claimCampaign(id)) {
      await processCampaign(await getCampaignOrThrow(id), 'both');
      processed += 1;
    }
  }
  return { processed };
}

export async function getCampaignStats(id) {
  const campaign = await getCampaignOrThrow(id);
  const [pending, sending, sent, failed] = await Promise.all([
    db('push_deliveries').where({ campaign_id: id, status: 'pending' }).count({ n: '*' }).first(),
    db('push_deliveries').where({ campaign_id: id, status: 'sending' }).count({ n: '*' }).first(),
    db('push_deliveries').where({ campaign_id: id, status: 'sent' }).count({ n: '*' }).first(),
    db('push_deliveries').where({ campaign_id: id, status: 'failed' }).count({ n: '*' }).first(),
  ]);
  const failures = await db('push_deliveries')
    .where({ campaign_id: id, status: 'failed' })
    .select('id', 'user_id', 'device_id', 'channel', 'error', 'attempts', 'processed_at')
    .orderBy('processed_at', 'desc')
    .limit(100);
  const summaries = await deliverySummaries([id]);
  return {
    campaign: toApiCampaign(campaign, summaries.get(id)),
    counters: {
      pending: Number(pending.n), sending: Number(sending.n), sent: Number(sent.n), failed: Number(failed.n),
    },
    failures,
  };
}

/** Reprocessa falhas temporárias (dispositivo ainda ativo) desta campanha. */
export async function reprocessCampaignFailures(id) {
  await getCampaignOrThrow(id);
  const reset = await resetFailedDeliveriesForRetry({ campaignId: id });
  if (reset > 0) {
    await db('push_campaigns').where({ id }).update({
      status: 'processing', sent_at: null, updated_at: now(),
    });
    await dispatchPendingDeliveries();
  }
  return { reset };
}

/**
 * Exclui definitivamente a campanha e seu histórico de entregas. Bloqueada
 * enquanto `processing` — o scheduler pode estar no meio do envio e ler a
 * linha (título/corpo) para montar o conteúdo das entregas em andamento.
 */
export async function deleteCampaign(id) {
  const campaign = await getCampaignOrThrow(id);
  if (campaign.status === 'processing') {
    throw badRequest('Aguarde a campanha terminar de processar antes de excluir');
  }
  await db.transaction(async (trx) => {
    await trx('push_deliveries').where({ campaign_id: id }).del();
    await trx('push_campaigns').where({ id }).del();
  });
}

/**
 * Reenvia: duplica a campanha (título/corpo/categoria/público/deep link) como
 * um novo rascunho e o envia imediatamente. Recalcula os destinatários na
 * hora — respeita preferências/opt-out atuais, que podem ter mudado desde o
 * envio original. Nunca reaproveita o id da campanha original: o histórico e
 * as estatísticas de cada envio ficam preservados separadamente.
 */
export async function resendCampaign(id, createdBy, { channel = 'both' } = {}) {
  channelFlags(channel);
  const source = await getCampaignOrThrow(id);
  const ts = now();
  const row = {
    id: crypto.randomUUID(),
    title: source.title,
    body: source.body,
    category: source.category,
    audience: source.audience,
    target_user_ids: source.target_user_ids,
    deep_link: source.deep_link,
    status: 'draft',
    created_by: createdBy,
    created_at: ts,
    updated_at: ts,
  };
  await db('push_campaigns').insert(row);
  return sendCampaignNow(row.id, { channel });
}
