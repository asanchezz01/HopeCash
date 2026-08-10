import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { verifyPassword, sha256 } from '../../utils/password.js';
import {
  signRetaguardaAccessToken,
  signRetaguardaRefreshToken,
  verifyToken,
} from '../../utils/jwt.js';
import { unauthorized } from '../../utils/httpError.js';
import { now } from '../../utils/time.js';
import { config } from '../../config.js';
import { audit } from '../../core/audit.js';

const router = Router();

const loginSchema = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string(),
  device_name: z.string().max(120).optional(),
});

async function issueTokens(user, req, deviceName) {
  const sessionId = crypto.randomUUID();
  const refreshToken = signRetaguardaRefreshToken(user.id, sessionId);
  const expires = new Date(Date.now() + config.jwt.refreshTtlDays * 86400_000);
  await db('retaguarda_sessions').insert({
    id: sessionId,
    retaguarda_user_id: user.id,
    refresh_token_hash: sha256(refreshToken),
    device_name: deviceName ?? null,
    ip: req.ip,
    user_agent: req.headers['user-agent']?.slice(0, 300) ?? null,
    expires_at: expires.toISOString().slice(0, 23).replace('T', ' '),
    created_at: now(),
  });
  return {
    access_token: signRetaguardaAccessToken(user),
    refresh_token: refreshToken,
    user: { id: user.id, name: user.name, email: user.email, role: user.role },
  };
}

router.post('/login', validate(loginSchema), async (req, res) => {
  const { email, password, device_name } = req.body;
  const user = await db('retaguarda_users').where({ email }).whereNull('deleted_at').first();
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    throw unauthorized('E-mail ou senha inválidos');
  }
  if (user.status === 'blocked') throw unauthorized('Acesso bloqueado');
  await db('retaguarda_users').where({ id: user.id }).update({ last_login_at: now() });
  await audit({ auth: { userId: user.id }, entity: 'retaguarda_users', entityId: user.id, action: 'login', req });
  res.json({ data: await issueTokens(user, req, device_name) });
});

router.post('/refresh', validate(z.object({ refresh_token: z.string() })), async (req, res) => {
  const { refresh_token } = req.body;
  let payload;
  try {
    payload = verifyToken(refresh_token);
  } catch {
    throw unauthorized('Refresh token inválido ou expirado');
  }
  if (payload.typ !== 'rtg_refresh') throw unauthorized('Tipo de token inválido');

  const session = await db('retaguarda_sessions').where({ id: payload.jti }).first();
  if (!session || session.revoked_at || session.refresh_token_hash !== sha256(refresh_token)) {
    if (session) {
      await db('retaguarda_sessions')
        .where({ retaguarda_user_id: session.retaguarda_user_id })
        .update({ revoked_at: now() });
    }
    throw unauthorized('Sessão inválida');
  }

  const user = await db('retaguarda_users').where({ id: payload.sub }).whereNull('deleted_at').first();
  if (!user) throw unauthorized('Usuário não encontrado');
  if (user.status === 'blocked') throw unauthorized('Acesso bloqueado');

  await db('retaguarda_sessions').where({ id: session.id }).update({ revoked_at: now() });
  res.json({ data: await issueTokens(user, req, session.device_name) });
});

router.post('/logout', validate(z.object({ refresh_token: z.string() })), async (req, res) => {
  try {
    const payload = verifyToken(req.body.refresh_token);
    await db('retaguarda_sessions').where({ id: payload.jti }).update({ revoked_at: now() });
  } catch {
    // token já inválido — logout é idempotente
  }
  res.json({ data: { ok: true } });
});

export default router;
