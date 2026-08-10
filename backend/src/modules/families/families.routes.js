import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { now } from '../../utils/time.js';
import { notFound, forbidden, badRequest } from '../../utils/httpError.js';
import { audit } from '../../core/audit.js';

const router = Router();

const ROLES = ['owner', 'admin', 'member', 'viewer'];

async function requireRole(auth, familyId, roles) {
  const member = await db('family_members')
    .where({ family_id: familyId, member_user_id: auth.userId, status: 'active' })
    .whereNull('deleted_at')
    .first();
  if (!member || !roles.includes(member.role)) throw forbidden('Permissão insuficiente na família');
  return member;
}

router.get('/', async (req, res) => {
  const families = await db('families')
    .whereIn('id', req.auth.familyIds.length ? req.auth.familyIds : [''])
    .whereNull('deleted_at');
  res.json({ data: families });
});

router.post('/', validate(z.object({ name: z.string().min(2).max(120) })), async (req, res) => {
  const ts = now();
  const family = {
    id: crypto.randomUUID(),
    name: req.body.name,
    owner_id: req.auth.userId,
    user_id: req.auth.userId,
    created_at: ts,
    updated_at: ts,
    version: 1,
  };
  await db('families').insert(family);
  await db('family_members').insert({
    id: crypto.randomUUID(),
    user_id: req.auth.userId,
    family_id: family.id,
    member_user_id: req.auth.userId,
    role: 'owner',
    status: 'active',
    created_at: ts,
    updated_at: ts,
    version: 1,
  });
  await audit({ auth: req.auth, entity: 'families', entityId: family.id, action: 'create', req });
  res.status(201).json({ data: family });
});

router.get('/:id/members', async (req, res) => {
  await requireRole(req.auth, req.params.id, ROLES);
  const members = await db('family_members as fm')
    .leftJoin('users as u', 'u.id', 'fm.member_user_id')
    .where('fm.family_id', req.params.id)
    .whereNull('fm.deleted_at')
    .whereNot('fm.status', 'removed')
    .select('fm.id', 'fm.role', 'fm.status', 'fm.invited_email', 'u.id as member_user_id', 'u.name', 'u.email');
  res.json({ data: members });
});

router.post('/:id/invites', validate(z.object({
  email: z.string().email().toLowerCase(),
  role: z.enum(['admin', 'member', 'viewer']).default('member'),
})), async (req, res) => {
  await requireRole(req.auth, req.params.id, ['owner', 'admin']);
  const existing = await db('family_members')
    .where({ family_id: req.params.id, invited_email: req.body.email })
    .whereNot('status', 'removed')
    .whereNull('deleted_at')
    .first();
  if (existing) throw badRequest('Convite já existe para esse e-mail');

  const ts = now();
  const invite = {
    id: crypto.randomUUID(),
    user_id: req.auth.userId,
    family_id: req.params.id,
    invited_email: req.body.email,
    invite_token: crypto.randomBytes(16).toString('hex'),
    role: req.body.role,
    status: 'invited',
    created_at: ts,
    updated_at: ts,
    version: 1,
  };
  await db('family_members').insert(invite);
  await audit({ auth: req.auth, entity: 'family_members', entityId: invite.id, action: 'invite', changes: { email: req.body.email }, req });
  // Em produção o token vai por e-mail; retornado aqui para o fluxo do app.
  res.status(201).json({ data: { id: invite.id, invite_token: invite.invite_token } });
});

router.post('/invites/accept', validate(z.object({ token: z.string() })), async (req, res) => {
  const invite = await db('family_members')
    .where({ invite_token: req.body.token, status: 'invited' })
    .whereNull('deleted_at')
    .first();
  if (!invite) throw notFound('Convite não encontrado ou já utilizado');
  await db('family_members').where({ id: invite.id }).update({
    member_user_id: req.auth.userId,
    status: 'active',
    invite_token: null,
    updated_at: now(),
    version: invite.version + 1,
  });
  res.json({ data: { family_id: invite.family_id, role: invite.role } });
});

router.put('/:id/members/:memberId', validate(z.object({ role: z.enum(['admin', 'member', 'viewer']) })), async (req, res) => {
  await requireRole(req.auth, req.params.id, ['owner']);
  const member = await db('family_members').where({ id: req.params.memberId, family_id: req.params.id }).first();
  if (!member) throw notFound();
  if (member.role === 'owner') throw badRequest('O dono da família não pode ter o papel alterado');
  await db('family_members').where({ id: member.id })
    .update({ role: req.body.role, updated_at: now(), version: member.version + 1 });
  res.json({ data: { ok: true } });
});

router.delete('/:id/members/:memberId', async (req, res) => {
  await requireRole(req.auth, req.params.id, ['owner', 'admin']);
  const member = await db('family_members').where({ id: req.params.memberId, family_id: req.params.id }).first();
  if (!member) throw notFound();
  if (member.role === 'owner') throw badRequest('O dono da família não pode ser removido');
  await db('family_members').where({ id: member.id })
    .update({ status: 'removed', deleted_at: now(), updated_at: now(), version: member.version + 1 });
  res.json({ data: { ok: true } });
});

export default router;
