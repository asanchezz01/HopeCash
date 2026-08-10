import crypto from 'node:crypto';
import { db } from '../../db/knex.js';
import { sha256 } from '../../utils/crypto.js';
import { now } from '../../utils/time.js';
import { notFound } from '../../utils/httpError.js';

/** Tokens válidos para cada tipo de token. */
const TYPES = {
  mcp_read: ['read'],
  mcp_write: ['read', 'write'],
  push_transactions: ['push_transactions'],
};

/** Gera um token plaintext e retorna seu hash SHA-256. */
export function generatePatToken() {
  const plain = crypto.randomBytes(32).toString('hex');
  return { plain, hash: sha256(plain) };
}

/**
 * Cria um novo PAT para o usuário.
 * @param {string} userId
 * @param {string} name
 * @param {Date|null} expiresAt
 * @param {'mcp_read'|'mcp_write'|'push_transactions'} [kind='push_transactions'] — tipo do token; define os scopes automáticamente.
 */
export async function createPat(userId, name, expiresAt, kind = 'push_transactions') {
  const { plain, hash } = generatePatToken();
  const id = crypto.randomUUID();
  const ts = now();
  const scopes = TYPES[kind] ?? ['push_transactions'];

  await db('personal_access_tokens').insert({
    id,
    user_id: userId,
    name,
    token_hash: hash,
    kind,
    scopes: JSON.stringify(scopes),
    expires_at: expiresAt ?? null,
    last_used_at: null,
    revoked_at: null,
    created_at: ts,
    updated_at: ts,
  });
  return { id, name, token: plain, kind, scopes };
}

/** Lista todos os PATs ativos de um usuário. */
export async function listPats(userId) {
  const rows = await db('personal_access_tokens')
    .where({ user_id: userId })
    .whereNull('revoked_at')
    .orderBy('created_at', 'desc');
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    kind: r.kind ?? 'push_transactions',
    scopes: JSON.parse(r.scopes),
    last4: `...${r.token_hash?.slice(-4)}`,
    expires_at: r.expires_at,
    last_used_at: r.last_used_at,
    created_at: r.created_at,
  }));
}

/** Revoga um PAT. */
export async function revokePat(userId, patId) {
  const row = await db('personal_access_tokens')
    .where({ id: patId, user_id: userId })
    .whereNull('revoked_at')
    .first();
  if (!row) throw notFound('Token não encontrado');
  await db('personal_access_tokens').where({ id: patId }).update({
    revoked_at: now(),
    updated_at: now(),
  });
  return { ok: true };
}

/** Verifica se o token plaintext é válido e retorna os metadados. */
export async function verifyPatToken(tokenPlain) {
  const hash = sha256(tokenPlain);
  const row = await db('personal_access_tokens')
    .where({ token_hash: hash })
    .whereNull('revoked_at')
    .first();
  if (!row) return null;

  // Verifica expiração
  if (row.expires_at && new Date(row.expires_at) < new Date()) {
    await db('personal_access_tokens').where({ id: row.id }).update({
      revoked_at: now(),
      updated_at: now(),
    });
    return null;
  }

  const scopes = row.scopes ? JSON.parse(row.scopes) : ['push_transactions'];
  const kind = row.kind ?? 'push_transactions';

  // Atualiza last_used_at
  await db('personal_access_tokens').where({ id: row.id }).update({
    last_used_at: now(),
    updated_at: now(),
  });

  return {
    userId: row.user_id,
    kind,
    scopes,
    name: row.name,
  };
}
