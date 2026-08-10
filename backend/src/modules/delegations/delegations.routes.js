import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { badRequest, notFound, forbidden } from '../../utils/httpError.js';
import { now } from '../../utils/time.js';
import { signDelegatedAccessToken } from '../../utils/jwt.js';
import { sendMail } from '../../core/mailer.js';
import { audit } from '../../core/audit.js';
import { logger } from '../../logger.js';

const router = Router();

const PERMISSION_LABEL = { read: 'somente leitura', full: 'acesso total' };

/** Delegações ativas que EU concedi (visão do titular). */
router.get('/', async (req, res) => {
  const rows = await db('account_delegations as d')
    .join('users as u', 'u.id', 'd.delegate_user_id')
    .where('d.owner_user_id', req.auth.userId)
    .whereNull('d.revoked_at')
    .orderBy('d.created_at', 'desc')
    .select(
      'd.id', 'd.permission', 'd.created_at',
      'u.name as delegate_name', 'u.email as delegate_email',
    );
  res.json({ data: rows });
});

/** Contas que outros usuários compartilharam comigo. */
router.get('/received', async (req, res) => {
  const rows = await db('account_delegations as d')
    .join('users as u', 'u.id', 'd.owner_user_id')
    .where('d.delegate_user_id', req.auth.userId)
    .whereNull('d.revoked_at')
    .orderBy('d.created_at', 'desc')
    .select(
      'd.id', 'd.permission',
      'u.id as owner_id', 'u.name as owner_name', 'u.email as owner_email',
    );
  res.json({ data: rows });
});

/** Concede acesso da minha conta a outro usuário e o avisa por e-mail. */
router.post('/', validate(z.object({
  email: z.string().email().toLowerCase(),
  permission: z.enum(['read', 'full']).default('read'),
})), async (req, res) => {
  const { email, permission } = req.body;
  const owner = await db('users').where({ id: req.auth.userId }).first();
  if (owner.email === email) throw badRequest('Você não pode delegar acesso a si mesmo');

  const delegate = await db('users').where({ email }).whereNull('deleted_at').first();
  if (!delegate) throw notFound('Nenhum usuário HopeCash encontrado com esse e-mail');

  const existing = await db('account_delegations')
    .where({ owner_user_id: owner.id, delegate_user_id: delegate.id })
    .whereNull('revoked_at')
    .first();
  if (existing) throw badRequest('Esse usuário já tem acesso à sua conta');

  const ts = now();
  const delegation = {
    id: crypto.randomUUID(),
    owner_user_id: owner.id,
    delegate_user_id: delegate.id,
    permission,
    created_at: ts,
    updated_at: ts,
  };
  await db('account_delegations').insert(delegation);

  const mail = await sendMail({
    to: delegate.email,
    subject: 'HopeCash — Você recebeu acesso a uma conta',
    text:
      `Olá, ${delegate.name}.\n\n` +
      `${owner.name} (${owner.email}) concedeu a você ${PERMISSION_LABEL[permission]} ` +
      `à conta HopeCash dele(a).\n\n` +
      `Ao entrar no HopeCash, você poderá escolher qual conta deseja visualizar.\n\n` +
      `Se você não esperava este acesso, fale com ${owner.name} — ele(a) pode revogá-lo a qualquer momento.`,
  });
  logger.info(
    { owner: owner.email, delegate: delegate.email, permission, email_sent: mail.sent },
    'Delegação de acesso concedida',
  );
  await audit({
    auth: req.auth,
    entity: 'account_delegations',
    entityId: delegation.id,
    action: 'create',
    changes: { delegate: delegate.email, permission, email_sent: mail.sent },
    req,
  });

  res.status(201).json({
    data: {
      id: delegation.id,
      permission,
      created_at: ts,
      delegate_name: delegate.name,
      delegate_email: delegate.email,
      email_sent: mail.sent,
    },
  });
});

/** Revoga um acesso concedido. Vale imediatamente para tokens já emitidos. */
router.delete('/:id', async (req, res) => {
  const delegation = await db('account_delegations')
    .where({ id: req.params.id, owner_user_id: req.auth.userId })
    .whereNull('revoked_at')
    .first();
  if (!delegation) throw notFound('Delegação não encontrada');

  const ts = now();
  await db('account_delegations')
    .where({ id: delegation.id })
    .update({ revoked_at: ts, updated_at: ts });
  await audit({
    auth: req.auth,
    entity: 'account_delegations',
    entityId: delegation.id,
    action: 'delete',
    req,
  });
  res.json({ data: { ok: true } });
});

/** Emite um token de acesso atuando como o titular de uma conta delegada. */
router.post('/act-as', validate(z.object({
  owner_user_id: z.string().uuid(),
})), async (req, res) => {
  const delegation = await db('account_delegations')
    .where({
      owner_user_id: req.body.owner_user_id,
      delegate_user_id: req.auth.userId,
    })
    .whereNull('revoked_at')
    .first();
  if (!delegation) throw forbidden('Você não tem acesso a essa conta');

  const me = await db('users').where({ id: req.auth.userId }).first();
  const owner = await db('users').where({ id: req.body.owner_user_id }).first();
  if (!owner || owner.deleted_at) throw notFound('Conta não encontrada');

  await audit({
    auth: req.auth,
    entity: 'account_delegations',
    entityId: delegation.id,
    action: 'act_as',
    req,
  });
  res.json({
    data: {
      access_token: signDelegatedAccessToken(me, owner.id, delegation.permission),
      permission: delegation.permission,
      owner: { id: owner.id, name: owner.name, email: owner.email },
    },
  });
});

export default router;
