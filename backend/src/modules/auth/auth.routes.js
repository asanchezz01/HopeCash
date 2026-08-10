import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { hashPassword, verifyPassword, sha256 } from '../../utils/password.js';
import { signAccessToken, signRefreshToken, verifyToken } from '../../utils/jwt.js';
import { unauthorized, badRequest } from '../../utils/httpError.js';
import { now } from '../../utils/time.js';
import { config } from '../../config.js';
import { audit } from '../../core/audit.js';
import { logger } from '../../logger.js';
import { sendMail } from '../../core/mailer.js';
import { insertDefaultCategories } from '../categories/categories.service.js';

const router = Router();

const passwordSchema = z.string().min(8, 'Mínimo de 8 caracteres')
  .regex(/[a-zA-Z]/, 'Deve conter letras').regex(/[0-9]/, 'Deve conter números');

const registerSchema = z.object({
  name: z.string().min(2).max(120),
  email: z.string().email().toLowerCase(),
  password: passwordSchema,
});

const loginSchema = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string(),
  device_name: z.string().max(120).optional(),
});

async function issueTokens(user, req, deviceName) {
  const sessionId = crypto.randomUUID();
  const refreshToken = signRefreshToken(user.id, sessionId);
  const expires = new Date(Date.now() + config.jwt.refreshTtlDays * 86400_000);
  await db('user_sessions').insert({
    id: sessionId,
    user_id: user.id,
    refresh_token_hash: sha256(refreshToken),
    device_name: deviceName ?? null,
    ip: req.ip,
    user_agent: req.headers['user-agent']?.slice(0, 300) ?? null,
    expires_at: expires.toISOString().slice(0, 23).replace('T', ' '),
    created_at: now(),
  });
  return {
    access_token: signAccessToken(user),
    refresh_token: refreshToken,
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      locale: user.locale,
      currency: user.currency,
      onboarding_completed_at: user.onboarding_completed_at ?? null,
    },
  };
}

router.post('/register', validate(registerSchema), async (req, res) => {
  const { name, email, password } = req.body;
  const exists = await db('users').where({ email }).first();
  if (exists) throw badRequest('E-mail já cadastrado');
  const ts = now();
  const user = {
    id: crypto.randomUUID(),
    name,
    email,
    password_hash: await hashPassword(password),
    created_at: ts,
    updated_at: ts,
  };
  await db('users').insert(user);
  await insertDefaultCategories(db, user.id);
  await audit({ auth: { userId: user.id }, entity: 'users', entityId: user.id, action: 'register', req });
  const tokens = await issueTokens({ ...user, locale: 'pt-BR', currency: 'BRL' }, req, req.body.device_name);
  res.status(201).json({ data: tokens });
});

router.post('/login', validate(loginSchema), async (req, res) => {
  const { email, password, device_name } = req.body;
  const user = await db('users').where({ email }).whereNull('deleted_at').first();
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    throw unauthorized('E-mail ou senha inválidos');
  }
  if (user.status === 'blocked') throw unauthorized('Conta bloqueada');
  await audit({ auth: { userId: user.id }, entity: 'users', entityId: user.id, action: 'login', req });
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
  if (payload.typ !== 'refresh') throw unauthorized('Tipo de token inválido');

  const session = await db('user_sessions').where({ id: payload.jti }).first();
  if (!session || session.revoked_at || session.refresh_token_hash !== sha256(refresh_token)) {
    // Possível reuso de token roubado: revoga todas as sessões do usuário.
    if (session) await db('user_sessions').where({ user_id: session.user_id }).update({ revoked_at: now() });
    throw unauthorized('Sessão inválida');
  }

  const user = await db('users').where({ id: payload.sub }).whereNull('deleted_at').first();
  if (!user) throw unauthorized('Usuário não encontrado');

  // Rotação: a sessão antiga é revogada e uma nova é emitida.
  await db('user_sessions').where({ id: session.id }).update({ revoked_at: now() });
  res.json({ data: await issueTokens(user, req, session.device_name) });
});

router.post('/logout', validate(z.object({ refresh_token: z.string() })), async (req, res) => {
  try {
    const payload = verifyToken(req.body.refresh_token);
    await db('user_sessions').where({ id: payload.jti }).update({ revoked_at: now() });
  } catch {
    // token já inválido — logout é idempotente
  }
  res.json({ data: { ok: true } });
});

router.post('/forgot-password', validate(z.object({ email: z.string().email().toLowerCase() })), async (req, res) => {
  const user = await db('users').where({ email: req.body.email }).whereNull('deleted_at').first();
  if (user) {
    const token = crypto.randomBytes(24).toString('hex');
    const expiresAt = new Date(Date.now() + 3600_000).toISOString().slice(0, 23).replace('T', ' ');
    await db('users').where({ id: user.id }).update({
      password_reset_token: sha256(token),
      password_reset_expires_at: expiresAt,
      updated_at: now(),
    });
    const mail = await sendMail({
      to: user.email,
      subject: 'HopeCash — Recuperação de senha',
      text:
        `Olá, ${user.name}.\n\n` +
        `Recebemos uma solicitação de recuperação de senha para sua conta HopeCash.\n` +
        `Seu token de recuperação é: ${token}\n\n` +
        `Este token expira em 1 hora. Se você não solicitou esta alteração, ignore este e-mail.`,
    });
    logger.info({ email: user.email, token, email_sent: mail.sent }, 'Token de recuperação de senha gerado');
    await audit({
      auth: { userId: user.id },
      entity: 'users',
      entityId: user.id,
      action: 'reset_request',
      changes: { email_sent: mail.sent },
      req,
    });
  }
  // Resposta idêntica exista ou não o e-mail (evita enumeração de contas).
  res.json({ data: { message: 'Se o e-mail existir, enviaremos instruções de recuperação.' } });
});

router.post('/reset-password', validate(z.object({ token: z.string(), password: passwordSchema })), async (req, res) => {
  const user = await db('users')
    .where({ password_reset_token: sha256(req.body.token) })
    .where('password_reset_expires_at', '>', now())
    .first();
  if (!user) throw badRequest('Token inválido ou expirado');
  await db('users').where({ id: user.id }).update({
    password_hash: await hashPassword(req.body.password),
    password_reset_token: null,
    password_reset_expires_at: null,
    updated_at: now(),
  });
  // Troca de senha derruba todas as sessões.
  await db('user_sessions').where({ user_id: user.id }).update({ revoked_at: now() });
  await audit({ auth: { userId: user.id }, entity: 'users', entityId: user.id, action: 'password_reset', req });
  res.json({ data: { message: 'Senha redefinida com sucesso.' } });
});

export default router;
