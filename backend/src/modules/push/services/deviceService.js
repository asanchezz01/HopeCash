import crypto from 'node:crypto';
import { db } from '../../../db/knex.js';
import { now } from '../../../utils/time.js';

const PLATFORMS = ['web', 'pwa', 'android', 'ios'];

export const PUBLIC_DEVICE_FIELDS = [
  'id', 'platform', 'app_version', 'locale', 'timezone', 'last_used_at', 'is_active', 'created_at', 'updated_at',
];

/** Mascara o token para exibição (retaguarda) — nunca expõe o valor completo. */
export const maskToken = (token) => (token ? `${token.slice(0, 6)}…${token.slice(-4)}` : null);

/**
 * Registra ou atualiza (idempotente, por token) o dispositivo push de um
 * usuário. Se o mesmo token já existir vinculado a outro usuário (aparelho
 * reutilizado após troca de conta), o vínculo é transferido para o usuário
 * atual — nunca ficam dois donos para o mesmo token.
 */
export async function registerDevice(userId, payload) {
  const { token, platform, install_id: installId, app_version: appVersion, locale, timezone } = payload;
  if (!PLATFORMS.includes(platform)) throw new Error(`Plataforma inválida: ${platform}`);

  const ts = now();
  const existing = await db('push_devices').where({ token }).first();
  if (existing) {
    await db('push_devices').where({ id: existing.id }).update({
      user_id: userId,
      platform,
      install_id: installId ?? null,
      app_version: appVersion ?? null,
      locale: locale ?? null,
      timezone: timezone ?? null,
      is_active: true,
      revoked_at: null,
      last_error: null,
      failed_at: null,
      last_used_at: ts,
      updated_at: ts,
    });
    return db('push_devices').where({ id: existing.id }).first();
  }

  const id = crypto.randomUUID();
  await db('push_devices').insert({
    id,
    user_id: userId,
    token,
    platform,
    install_id: installId ?? null,
    app_version: appVersion ?? null,
    locale: locale ?? null,
    timezone: timezone ?? null,
    is_active: true,
    last_used_at: ts,
    created_at: ts,
    updated_at: ts,
  });
  return db('push_devices').where({ id }).first();
}

/** Desativa (logout) o token do próprio usuário — idempotente. */
export async function deactivateDevice(userId, token) {
  const ts = now();
  const updated = await db('push_devices')
    .where({ user_id: userId, token })
    .update({ is_active: false, revoked_at: ts, updated_at: ts });
  return updated > 0;
}

export async function listDevicesForUser(userId) {
  return db('push_devices').where({ user_id: userId }).orderBy('created_at', 'desc');
}

/** Marca falha permanente (token inválido/revogado) — desativa o dispositivo. */
export async function markDevicePermanentlyFailed(deviceId, errorCode) {
  const ts = now();
  await db('push_devices').where({ id: deviceId }).update({
    is_active: false,
    revoked_at: ts,
    last_error: errorCode?.slice(0, 255) ?? null,
    failed_at: ts,
    updated_at: ts,
  });
}

export async function touchDeviceLastUsed(deviceId) {
  await db('push_devices').where({ id: deviceId }).update({ last_used_at: now(), updated_at: now() });
}

/** Usado no fluxo de exclusão de conta (LGPD) — remove fisicamente os dispositivos do usuário. */
export async function deleteAllDevicesForUser(userId, trx) {
  await (trx ?? db)('push_devices').where({ user_id: userId }).del();
}
