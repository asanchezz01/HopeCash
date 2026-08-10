import crypto from 'node:crypto';
import { db } from '../../../db/knex.js';
import { now } from '../../../utils/time.js';
import { notFound } from '../../../utils/httpError.js';

/**
 * Um tipo de mensagem automática por linha. Valores padrão usados apenas na
 * primeira vez que cada tipo é acessado (idempotente, mesmo padrão de
 * `preferencesService.getPreferences`) — depois disso, o admin é dono do
 * conteúdo/frequência pela retaguarda.
 */
const DEFAULTS = {
  due_reminder: {
    frequency_days: 3,
    title: null,
    body: null,
    config: null,
  },
  financial_insight: {
    frequency_days: 7,
    title: 'Fique de olho no seu orçamento',
    body: 'Uma categoria do seu orçamento está perto do limite. Toque para conferir.',
    config: JSON.stringify({ threshold_percent: 90 }),
  },
  tip: {
    frequency_days: 14,
    title: 'Dica da Hope',
    body: 'Revise assinaturas que você não usa mais — pequenos cortes fazem diferença no fim do mês.',
    config: null,
  },
};

export const MESSAGE_TYPES = Object.keys(DEFAULTS);

const parseConfig = (rule) => {
  if (!rule?.config) return {};
  try {
    return JSON.parse(rule.config);
  } catch {
    return {};
  }
};

const toApiRule = (rule) => ({ ...rule, config: parseConfig(rule) });

/** Garante que as três regras padrão existam — idempotente. */
export async function ensureAutomationRules() {
  for (const [messageType, defaults] of Object.entries(DEFAULTS)) {
    const existing = await db('push_automation_rules').where({ message_type: messageType }).first('id');
    if (existing) continue;
    const ts = now();
    await db('push_automation_rules').insert({
      id: crypto.randomUUID(),
      message_type: messageType,
      enabled: true,
      ...defaults,
      created_at: ts,
      updated_at: ts,
    });
  }
}

export async function listAutomationRules() {
  await ensureAutomationRules();
  const rules = await db('push_automation_rules').orderBy('message_type', 'asc');
  return rules.map(toApiRule);
}

/** Linha crua (sem desserializar `config`) — uso interno dos workers. */
export async function getAutomationRule(messageType) {
  await ensureAutomationRules();
  return db('push_automation_rules').where({ message_type: messageType }).first();
}

export async function updateAutomationRule(messageType, patch, updatedBy) {
  await ensureAutomationRules();
  if (!MESSAGE_TYPES.includes(messageType)) throw notFound('Tipo de mensagem automática desconhecido');

  const update = { ...patch, updated_by: updatedBy, updated_at: now() };
  if ('config' in patch) {
    update.config = patch.config != null ? JSON.stringify(patch.config) : null;
  }
  await db('push_automation_rules').where({ message_type: messageType }).update(update);
  const rule = await db('push_automation_rules').where({ message_type: messageType }).first();
  return toApiRule(rule);
}
