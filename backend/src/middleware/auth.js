import { db } from '../db/knex.js';
import { verifyToken } from '../utils/jwt.js';
import { unauthorized, forbidden } from '../utils/httpError.js';

/**
 * Autentica via Bearer token e monta o escopo de acesso:
 * req.auth = { userId, email, familyIds, actorId, readOnly }.
 *
 * Sessão delegada (token com act_for): o escopo passa a ser o do titular da
 * conta (userId = act_for) e actorId guarda quem realmente está acessando.
 * A delegação é revalidada a cada requisição — revogação vale imediatamente
 * e mudanças de permissão também.
 */
export async function authenticate(req, _res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw unauthorized('Token de acesso ausente');

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
  };
  next();
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
  next();
}
