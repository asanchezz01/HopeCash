import { db } from '../db/knex.js';
import { verifyToken } from '../utils/jwt.js';
import { unauthorized, forbidden } from '../utils/httpError.js';

/**
 * Autentica um usuário da retaguarda via Bearer token (typ rtg_access).
 * Monta req.rtg = { userId, email, role }. É independente do middleware do app.
 */
export async function authenticateRetaguarda(req, _res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw unauthorized('Token de acesso ausente');

  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    throw unauthorized('Token inválido ou expirado');
  }
  if (payload.typ !== 'rtg_access') throw unauthorized('Tipo de token inválido');

  const user = await db('retaguarda_users')
    .where({ id: payload.sub })
    .whereNull('deleted_at')
    .first('id', 'email', 'role', 'status');
  if (!user) throw unauthorized('Usuário da retaguarda não encontrado');
  if (user.status === 'blocked') throw unauthorized('Acesso bloqueado');

  req.rtg = { userId: user.id, email: user.email, role: user.role };
  next();
}

/** Exige papel de superusuário para ações sensíveis. */
export function requireSuperuser(req, _res, next) {
  if (req.rtg?.role !== 'superuser') throw forbidden('Ação exclusiva do superusuário');
  next();
}
