import { config } from '../config.js';
import { db } from '../db/knex.js';
import { verifyToken } from '../utils/jwt.js';
import { unauthorized, forbidden } from '../utils/httpError.js';
import { verifyPatToken } from '../modules/pat/pat.service.js';

/**
 * Autentica via Bearer token (JWT ou PAT) e monta o escopo de acesso:
 * req.auth = { userId, email, familyIds, actorId, readOnly }.
 */
export async function authenticate(req, res, next) {
  // Hosts MCP com OAuth (RFC 9728) descobrem o Authorization Server a partir
  // de um 401 SEM token: leem o `WWW-Authenticate` daqui, não tentam os
  // caminhos /.well-known por conta própria. Sem este header, um host que
  // sonde /ai/mcp antes do OAuth falha na hora — foi o caso do Grok.
  if (req.path.startsWith('/ai/mcp')) {
    const resourceMetadataUrl = `${config.publicUrl}/.well-known/oauth-protected-resource/api/v1/ai/mcp`;
    res.set('WWW-Authenticate', `Bearer resource_metadata="${resourceMetadataUrl}"`);
  }

  const header = req.headers.authorization || '';
  let token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) throw unauthorized('Token de acesso ausente');

  // Tenta autenticar como PAT primeiro
  const pat = await verifyPatToken(token);
  if (pat) {
    req.auth = {
      userId: pat.userId,
      email: null,
      familyIds: [],
      familyRoles: {},
      actorId: null,
      readOnly: pat.kind === 'mcp_read', // mcp_read é sempre só leitura via auth layer
      isPat: true,
      scopes: pat.scopes,
      patKind: pat.kind, // indica o tipo do token para filtros adicionais
      patName: pat.name, // identifica o host nas chamadas MCP (ver mcp_logs)
    };
    return next();
  }

  // Se não for PAT, tenta JWT
  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    throw unauthorized('Token inválido ou expirado');
  }
  if (payload.typ !== 'access') throw unauthorized('Tipo de token inválido');

  let userId = payload.sub;
  let actorId = null;
  let readOnly = false;
  if (payload.act_for) {
    const delegation = await db('account_delegations')
      .where({ owner_user_id: payload.act_for, delegate_user_id: payload.sub })
      .whereNull('revoked_at')
      .first();
    if (!delegation) throw unauthorized('Acesso delegado revogado');
    userId = payload.act_for;
    actorId = payload.sub;
    readOnly = delegation.permission === 'read';
  }

  const memberships = await db('family_members')
    .where({ member_user_id: userId, status: 'active' })
    .whereNull('deleted_at')
    .select('family_id', 'role');

  req.auth = {
    userId,
    email: payload.email,
    familyIds: memberships.map((membership) => membership.family_id),
    familyRoles: Object.fromEntries(memberships.map((membership) => [membership.family_id, membership.role])),
    actorId,
    readOnly,
    isPat: false,
    patKind: null,
    patName: null,
    scopes: null,
  };
  next();
}

/**
 * Middleware que valida o escopo mínimo de um PAT MCP.
 * - mcp_read: acesso às tools de leitura (read-only).
 * - mcp_write: acesso a todas as tools, incluindo escrita em duas fases.
 * push_transactions NUNCA pode acessar endpoints do protocolo MCP.
 */
export function mcpScopeGuard(requiredScope) {
  return (req, _res, next) => {
    // Apenas PATs são tratados aqui — JWT vai pelo fluxo normal de auth/delegation
    if (!req.auth?.isPat) return next();

    const hasReadScope = req.auth.scopes.includes('read');
    if (requiredScope === 'write' && !hasReadScope) {
      throw forbidden('Este token PAT requer o escopo mcp_write para operações de escrita.');
    }
    if (!hasReadScope) {
      throw forbidden(`Este token PAT requer o escopo ${requiredScope} para esta operação.`);
    }
    next();
  };
}

/**
 * Restrições de sessão delegada:
 * - rotas pessoais (/users, /delegations) pertencem ao usuário real, não ao
 *   contexto delegado — bloqueadas para evitar, p.ex., troca de senha do dono;
 * - permissão somente leitura bloqueia qualquer método de escrita.
 */
export function delegationGuard(req, _res, next) {
  if (req.auth?.actorId) {
    if (req.path.startsWith('/users') || req.path.startsWith('/delegations')) {
      throw forbidden('Indisponível enquanto você acessa uma conta compartilhada');
    }
    if (req.auth.readOnly && !['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
      throw forbidden('Seu acesso a esta conta é somente leitura');
    }
  }

  // PAT push_transactions: restrito a POST /transactions
  if (req.auth?.patKind === 'push_transactions') {
    if (!req.path.startsWith('/transactions') || req.method !== 'POST') {
      throw forbidden('Este token só tem permissão para criar lançamentos.');
    }
  }

  next();
}
