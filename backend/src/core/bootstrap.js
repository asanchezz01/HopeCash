import crypto from 'node:crypto';
import { db } from '../db/knex.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { hashPassword } from '../utils/password.js';
import { now } from '../utils/time.js';

/**
 * Provisiona o superusuário da retaguarda a partir do .env, de forma idempotente.
 * Criado apenas se ainda não existir — não sobrescreve a senha de um superusuário
 * já existente (permitindo que a senha seja trocada depois pela própria retaguarda).
 */
export async function ensureSuperuser() {
  const email = config.superuser.email;
  const existing = await db('retaguarda_users').where({ email }).first('id');
  if (existing) return existing.id;

  const ts = now();
  const id = crypto.randomUUID();
  await db('retaguarda_users').insert({
    id,
    name: config.superuser.name,
    email,
    password_hash: await hashPassword(config.superuser.password),
    role: 'superuser',
    status: 'active',
    created_at: ts,
    updated_at: ts,
  });
  logger.info({ email }, 'Superusuário da retaguarda provisionado');
  return id;
}
