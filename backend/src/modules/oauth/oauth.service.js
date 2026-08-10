/**
 * Núcleo do Authorization Server OAuth 2.1 do MCP da Hope — registro
 * dinâmico de clientes (RFC 7591), emissão e troca de authorization code
 * com PKCE (RFC 7636). O "access_token" emitido é literalmente um PAT
 * (ver modules/pat/pat.service.js) — reaproveita hash/verificação/revogação
 * já testados; o resource server (mcp.server.js/auth_pat.js) não muda nada.
 */
import crypto from 'node:crypto';
import { db } from '../../db/knex.js';
import { now } from '../../utils/time.js';
import { sha256 } from '../../utils/crypto.js';
import { verifyPassword } from '../../utils/password.js';
import { createPat } from '../pat/pat.service.js';

const CODE_TTL_MS = 5 * 60_000;

/** Erro no formato OAuth (`{ error, error_description }`), distinto do HttpError genérico da API. */
export class OAuthError extends Error {
  constructor(status, error, description) {
    super(description);
    this.status = status;
    this.error = error;
    this.description = description;
  }
}

const expiresInMs = (ms) => new Date(Date.now() + ms).toISOString().slice(0, 23).replace('T', ' ');

function assertValidRedirectUris(redirectUris) {
  if (!Array.isArray(redirectUris) || redirectUris.length === 0) {
    throw new OAuthError(400, 'invalid_client_metadata', 'redirect_uris é obrigatório e deve ser uma lista não vazia');
  }
  for (const uri of redirectUris) {
    let parsed;
    try {
      parsed = new URL(uri);
    } catch {
      throw new OAuthError(400, 'invalid_client_metadata', `redirect_uri inválida: ${uri}`);
    }
    const isLoopback = parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
    if (parsed.protocol !== 'https:' && !isLoopback) {
      throw new OAuthError(400, 'invalid_client_metadata', `redirect_uri deve usar https: ${uri}`);
    }
  }
}

/** Dynamic Client Registration (RFC 7591) — sem autenticação, por design do protocolo. */
export async function registerClient({ clientName, redirectUris }) {
  assertValidRedirectUris(redirectUris);
  const id = crypto.randomUUID();
  const ts = now();
  await db('oauth_clients').insert({
    id,
    client_name: clientName ? String(clientName).slice(0, 200) : null,
    redirect_uris: JSON.stringify(redirectUris),
    created_at: ts,
    updated_at: ts,
  });
  return { id, clientName: clientName ?? null, redirectUris };
}

export async function findClient(clientId) {
  if (!clientId) return null;
  const row = await db('oauth_clients').where({ id: clientId }).first();
  if (!row) return null;
  return { id: row.id, clientName: row.client_name, redirectUris: JSON.parse(row.redirect_uris) };
}

export const isRegisteredRedirect = (client, redirectUri) => client.redirectUris.includes(redirectUri);

/** Mesma checagem de credenciais do POST /auth/login (utils/password.js + tabela users). */
export async function verifyLogin(email, password) {
  const user = await db('users').where({ email: String(email ?? '').trim().toLowerCase() }).whereNull('deleted_at').first();
  if (!user || !(await verifyPassword(password ?? '', user.password_hash))) return null;
  if (user.status === 'blocked') return null;
  return user;
}

/** Emitido após login + consentimento; a URL de redirecionamento já foi validada antes de chegar aqui. */
export async function issueAuthorizationCode({ clientId, redirectUri, userId, kind, codeChallenge, codeChallengeMethod, resource }) {
  const code = crypto.randomBytes(32).toString('hex');

  // Um novo code invalida os anteriores ainda pendentes do mesmo par
  // client+usuário. Sem isso, cada reenvio do formulário deixava mais um code
  // válido em aberto: em 2026-08-07 um único login gerou 32 codes, dos quais
  // 31 ficaram vivos até expirar. Só um deles pode ser trocado por token de
  // qualquer forma, então derrubar os antigos não muda o fluxo feliz — apenas
  // encurta a janela em que um code vazado ainda serviria para alguma coisa.
  await db('oauth_authorization_codes')
    .where({ client_id: clientId, user_id: userId })
    .whereNull('consumed_at')
    .update({ consumed_at: now() });

  await db('oauth_authorization_codes').insert({
    id: crypto.randomUUID(),
    code_hash: sha256(code),
    client_id: clientId,
    redirect_uri: redirectUri,
    user_id: userId,
    kind,
    code_challenge: codeChallenge,
    code_challenge_method: codeChallengeMethod,
    resource: resource ?? null,
    expires_at: expiresInMs(CODE_TTL_MS),
    consumed_at: null,
    created_at: now(),
  });
  return code;
}

/**
 * POST /token — troca o code (+ PKCE) por um PAT novo. Toda falha aqui é
 * `invalid_grant`: não dá pista de qual verificação específica falhou (code
 * inexistente vs. expirado vs. reutilizado vs. PKCE errado), como o RFC 6749
 * recomenda para não ajudar um atacante a calibrar tentativas.
 */
export async function exchangeAuthorizationCode({ code, clientId, redirectUri, codeVerifier }) {
  if (!code || !clientId || !redirectUri || !codeVerifier) {
    throw new OAuthError(400, 'invalid_request', 'code, client_id, redirect_uri e code_verifier são obrigatórios');
  }

  const row = await db('oauth_authorization_codes').where({ code_hash: sha256(code) }).first();
  if (
    !row
    || row.consumed_at
    || new Date(row.expires_at) < new Date()
    || row.client_id !== clientId
    || row.redirect_uri !== redirectUri
  ) {
    throw new OAuthError(400, 'invalid_grant', 'Authorization code inválido, expirado ou já utilizado');
  }

  const expectedChallenge = crypto.createHash('sha256').update(codeVerifier).digest('base64url');
  if (expectedChallenge !== row.code_challenge) {
    throw new OAuthError(400, 'invalid_grant', 'Authorization code inválido, expirado ou já utilizado');
  }

  // Reivindica o code atomicamente — corta corrida em duas trocas simultâneas
  // do mesmo code (mesmo padrão de claim de tools/write.js/confirmAction).
  const claimed = await db('oauth_authorization_codes').where({ id: row.id, consumed_at: null }).update({ consumed_at: now() });
  if (claimed !== 1) {
    throw new OAuthError(400, 'invalid_grant', 'Authorization code inválido, expirado ou já utilizado');
  }

  const client = await findClient(row.client_id);
  const pat = await createPat(row.user_id, `OAuth: ${client?.clientName || 'aplicativo externo'}`, null, row.kind);
  return { pat, kind: row.kind };
}
