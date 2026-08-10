import crypto from 'node:crypto';
import { db } from '../db/knex.js';
import { now } from '../utils/time.js';

/** Trilha de auditoria append-only. Nunca deve derrubar a operação principal. */
export async function audit({ auth, entity, entityId, action, changes, req, trx }) {
  try {
    await (trx ?? db)('audit_logs').insert({
      id: crypto.randomUUID(),
      user_id: auth?.userId ?? null,
      family_id: changes?.family_id ?? null,
      entity,
      entity_id: entityId ?? null,
      action,
      changes: changes ? JSON.stringify(changes) : null,
      ip: req?.ip ?? null,
      user_agent: req?.headers?.['user-agent']?.slice(0, 300) ?? null,
      created_at: now(),
    });
  } catch {
    // auditoria é best-effort
  }
}
