import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { now } from '../../utils/time.js';
import { hashPassword, generateTempPassword } from '../../utils/password.js';
import { notFound } from '../../utils/httpError.js';
import { audit } from '../../core/audit.js';
import { sendMail } from '../../core/mailer.js';
import { config } from '../../config.js';

const router = Router();

const LIST_FIELDS = ['id', 'name', 'email', 'status', 'locale', 'currency', 'created_at', 'updated_at'];

/** Lista/pesquisa usuários do APP (tabela `users`), com paginação. */
router.get('/', validate(z.object({
  search: z.string().max(120).optional(),
  status: z.enum(['active', 'blocked', 'pending_deletion']).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
}), 'query'), async (req, res) => {
  const { search, status, limit, offset } = req.query;

  const base = db('users').whereNull('deleted_at');
  if (status) base.where({ status });
  if (search) {
    // LIKE é case-insensitive para ASCII tanto no MySQL (collation utf8mb4) quanto no SQLite.
    const like = `%${search}%`;
    base.where((qb) => qb.where('name', 'like', like).orWhere('email', 'like', like));
  }

  const total = await base.clone().count({ n: '*' }).first();
  const users = await base.clone()
    .select(LIST_FIELDS)
    .orderBy('created_at', 'desc')
    .limit(limit)
    .offset(offset);

  const userIds = users.map((user) => user.id);
  const pushUserIds = userIds.length
    ? await db('push_devices')
      .whereIn('user_id', userIds)
      .where({ is_active: true })
      .distinct('user_id')
    : [];
  const usersWithPush = new Set(pushUserIds.map((device) => device.user_id));

  res.json({
    data: users.map((user) => ({
      ...user,
      has_push_token: usersWithPush.has(user.id),
    })),
    meta: { total: Number(total.n), limit, offset },
  });
});

/** Detalhe de um usuário do APP, com contagem de sessões ativas. */
router.get('/:id', async (req, res) => {
  const user = await db('users').where({ id: req.params.id }).whereNull('deleted_at').first(LIST_FIELDS);
  if (!user) throw notFound('Usuário não encontrado');
  const sessions = await db('user_sessions')
    .where({ user_id: user.id })
    .whereNull('revoked_at')
    .where('expires_at', '>', now())
    .count({ n: '*' })
    .first();
  res.json({ data: { ...user, active_sessions: Number(sessions.n) } });
});

/** Bloqueia/desbloqueia o acesso de um usuário do APP. */
router.patch('/:id/status', validate(z.object({
  status: z.enum(['active', 'blocked']),
})), async (req, res) => {
  const user = await db('users').where({ id: req.params.id }).whereNull('deleted_at').first();
  if (!user) throw notFound('Usuário não encontrado');

  await db('users').where({ id: user.id }).update({ status: req.body.status, updated_at: now() });
  if (req.body.status === 'blocked') {
    await db('user_sessions').where({ user_id: user.id }).update({ revoked_at: now() });
  }
  await audit({
    auth: { userId: req.rtg.userId },
    entity: 'users', entityId: user.id,
    action: req.body.status === 'blocked' ? 'blocked' : 'unblocked',
    req,
  });
  const updated = await db('users').where({ id: user.id }).first(LIST_FIELDS);
  res.json({ data: updated });
});

/**
 * Redefine a senha de um usuário do APP: gera uma senha provisória, envia por
 * e-mail e derruba as sessões ativas. O usuário entra com a senha provisória e
 * depois a troca no app. Com MAIL_ENABLED=false o código é devolvido na resposta
 * (e sempre registrado no log) para que o operador consiga repassá-lo.
 */
router.post('/:id/reset-password', async (req, res) => {
  const user = await db('users').where({ id: req.params.id }).whereNull('deleted_at').first();
  if (!user) throw notFound('Usuário não encontrado');

  const tempPassword = generateTempPassword();
  await db('users').where({ id: user.id }).update({
    password_hash: await hashPassword(tempPassword),
    password_reset_token: null,
    password_reset_expires_at: null,
    updated_at: now(),
  });
  // A troca de senha derruba todas as sessões do usuário.
  await db('user_sessions').where({ user_id: user.id }).update({ revoked_at: now() });

  const mail = await sendMail({
    to: user.email,
    subject: 'HopeCash — Senha provisória de acesso',
    text:
      `Olá, ${user.name}.\n\n` +
      `Um administrador redefiniu a sua senha do HopeCash.\n` +
      `Sua senha provisória é: ${tempPassword}\n\n` +
      `Entre no aplicativo com essa senha e, em seguida, defina uma nova senha ` +
      `em "Mais > Dados de login".\n\n` +
      `Se você não solicitou esta alteração, entre em contato com o suporte.`,
  });

  await audit({ auth: { userId: req.rtg.userId }, entity: 'users', entityId: user.id, action: 'password_reset', req });

  res.json({
    data: {
      message: mail.sent
        ? 'Senha provisória enviada para o e-mail do usuário.'
        : 'Senha provisória gerada. Envie o código ao usuário.',
      email: user.email,
      email_sent: mail.sent,
      // Exposto apenas quando o envio de e-mail está desabilitado.
      code: config.mail.enabled ? undefined : tempPassword,
    },
  });
});

export default router;
