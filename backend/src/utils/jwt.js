import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export const signAccessToken = (user) =>
  jwt.sign({ sub: user.id, email: user.email, typ: 'access' }, config.jwt.secret, {
    expiresIn: config.jwt.accessTtl,
  });

/** O refresh token carrega o id da sessão (jti) para permitir rotação e revogação. */
export const signRefreshToken = (userId, sessionId) =>
  jwt.sign({ sub: userId, typ: 'refresh' }, config.jwt.secret, {
    expiresIn: `${config.jwt.refreshTtlDays}d`,
    jwtid: sessionId,
  });

/**
 * Token de acesso delegado: o sub continua sendo o usuário real (delegate),
 * mas act_for aponta o titular da conta visualizada. A permissão efetiva é
 * revalidada a cada requisição no middleware — revogar vale na hora.
 */
export const signDelegatedAccessToken = (user, ownerId, permission) =>
  jwt.sign(
    { sub: user.id, email: user.email, typ: 'access', act_for: ownerId, perm: permission },
    config.jwt.secret,
    { expiresIn: config.jwt.accessTtl },
  );

export const verifyToken = (token) => jwt.verify(token, config.jwt.secret);

/** Tokens da retaguarda usam typ próprio (rtg_*) para não cruzarem com o app. */
export const signRetaguardaAccessToken = (user) =>
  jwt.sign({ sub: user.id, email: user.email, role: user.role, typ: 'rtg_access' }, config.jwt.secret, {
    expiresIn: config.jwt.accessTtl,
  });

export const signRetaguardaRefreshToken = (userId, sessionId) =>
  jwt.sign({ sub: userId, typ: 'rtg_refresh' }, config.jwt.secret, {
    expiresIn: `${config.jwt.refreshTtlDays}d`,
    jwtid: sessionId,
  });
