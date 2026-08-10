import crypto from 'node:crypto';
import { db } from '../../../db/knex.js';
import { now } from '../../../utils/time.js';
import { config } from '../../../config.js';

const defaults = () => ({
  push_enabled: true,
  due_reminders_enabled: true,
  financial_insights_enabled: true,
  tips_enabled: true,
  // Canal de e-mail independente: quando autorizado, recebe as mesmas
  // notificações junto com o push.
  email_notifications_enabled: true,
  reminder_advance_days: config.push.dueReminderDays,
  preferred_hour: null,
  timezone: config.push.defaultTimezone,
});

/** Busca as preferências do usuário, criando a linha padrão no primeiro acesso. */
export async function getPreferences(userId) {
  const existing = await db('push_preferences').where({ user_id: userId }).first();
  if (existing) return existing;

  const ts = now();
  const row = { id: crypto.randomUUID(), user_id: userId, ...defaults(), created_at: ts, updated_at: ts };
  await db('push_preferences').insert(row);
  return row;
}

export async function updatePreferences(userId, patch) {
  await getPreferences(userId); // garante que a linha existe
  await db('push_preferences').where({ user_id: userId }).update({ ...patch, updated_at: now() });
  return db('push_preferences').where({ user_id: userId }).first();
}

export async function deletePreferencesForUser(userId, trx) {
  await (trx ?? db)('push_preferences').where({ user_id: userId }).del();
}
