import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { now } from '../../utils/time.js';
import { hashPassword, verifyPassword } from '../../utils/password.js';
import { badRequest, notFound, unauthorized, forbidden } from '../../utils/httpError.js';
import { audit } from '../../core/audit.js';

const router = Router();

const PUBLIC_FIELDS = ['id', 'name', 'email', 'role', 'status', 'last_login_at', 'created_at', 'updated_at'];
const passwordSchema = z.string().min(8, 'Mínimo de 8 caracteres')
  .regex(/[a-zA-Z]/, 'Deve conter letras').regex(/[0-9]/, 'Deve conter números');
const roleSchema = z.enum(['superuser', 'admin']);

/** Perfil do usuário logado. */
router.get('/me', async (req, res) => {
  const user = await db('retaguarda_users').where({ id: req.rtg.userId }).first(PUBLIC_FIELDS);
  if (!user) throw notFound();
  res.json({ data: user });
});

/** Troca da própria senha (exige a senha atual). */
router.put('/me/password', validate(z.object({
  current_password: z.string(),
  password: passwordSchema,
})), async (req, res) => {
  const user = await db('retaguarda_users').where({ id: req.rtg.userId }).first();
  if (!user) throw notFound();
  if (!(await verifyPassword(req.body.current_password, user.password_hash))) {
    throw unauthorized('Senha atual inválida');
  }
  await db('retaguarda_users').where({ id: user.id }).update({
    password_hash: await hashPassword(req.body.password),
    updated_at: now(),
  });
  // Trocar a senha derruba as demais sessões da retaguarda.
  await db('retaguarda_sessions').where({ retaguarda_user_id: user.id }).update({ revoked_at: now() });
  await audit({ auth: { userId: user.id }, entity: 'retaguarda_users', entityId: user.id, action: 'password_updated', req });
  res.json({ data: { message: 'Senha atualizada com sucesso.' } });
});

/** Lista todos os usuários da retaguarda. */
router.get('/', async (_req, res) => {
  const users = await db('retaguarda_users')
    .whereNull('deleted_at')
    .select(PUBLIC_FIELDS)
    .orderBy('created_at', 'asc');
  res.json({ data: users });
});

/** Cria um novo usuário da retaguarda. */
router.post('/', validate(z.object({
  name: z.string().min(2).max(120),
  email: z.string().email().toLowerCase(),
  password: passwordSchema,
  role: roleSchema.default('admin'),
})), async (req, res) => {
  const { name, email, password, role } = req.body;
  if (role === 'superuser' && req.rtg.role !== 'superuser') {
    throw forbidden('Apenas um superusuário pode criar outro superusuário');
  }
  const exists = await db('retaguarda_users').where({ email }).first();
  if (exists) throw badRequest('E-mail já cadastrado');

  const ts = now();
  const id = crypto.randomUUID();
  await db('retaguarda_users').insert({
    id, name, email,
    password_hash: await hashPassword(password),
    role, status: 'active',
    created_at: ts, updated_at: ts,
  });
  await audit({ auth: req.rtg && { userId: req.rtg.userId }, entity: 'retaguarda_users', entityId: id, action: 'create', req });
  const user = await db('retaguarda_users').where({ id }).first(PUBLIC_FIELDS);
  res.status(201).json({ data: user });
});

/** Atualiza nome, papel, status e/ou senha de um usuário da retaguarda. */
router.put('/:id', validate(z.object({
  name: z.string().min(2).max(120).optional(),
  role: roleSchema.optional(),
  status: z.enum(['active', 'blocked']).optional(),
  password: passwordSchema.optional(),
})), async (req, res) => {
  const target = await db('retaguarda_users').where({ id: req.params.id }).whereNull('deleted_at').first();
  if (!target) throw notFound('Usuário não encontrado');

  const grantsSuperuser = req.body.role === 'superuser' && target.role !== 'superuser';
  const revokesSuperuser = target.role === 'superuser' && req.body.role && req.body.role !== 'superuser';
  if ((grantsSuperuser || revokesSuperuser) && req.rtg.role !== 'superuser') {
    throw forbidden('Apenas um superusuário pode alterar o papel de superusuário');
  }
  // Não permitir rebaixar/bloquear o último superusuário ativo.
  await assertNotLastSuperuser(target, req.body);

  const patch = { updated_at: now() };
  if (req.body.name !== undefined) patch.name = req.body.name;
  if (req.body.role !== undefined) patch.role = req.body.role;
  if (req.body.status !== undefined) patch.status = req.body.status;
  if (req.body.password !== undefined) patch.password_hash = await hashPassword(req.body.password);

  await db('retaguarda_users').where({ id: target.id }).update(patch);
  if (req.body.password !== undefined || req.body.status === 'blocked') {
    await db('retaguarda_sessions').where({ retaguarda_user_id: target.id }).update({ revoked_at: now() });
  }
  await audit({ auth: { userId: req.rtg.userId }, entity: 'retaguarda_users', entityId: target.id, action: 'update', req });
  const user = await db('retaguarda_users').where({ id: target.id }).first(PUBLIC_FIELDS);
  res.json({ data: user });
});

/** Exclui (soft delete) um usuário da retaguarda. */
router.delete('/:id', async (req, res) => {
  const target = await db('retaguarda_users').where({ id: req.params.id }).whereNull('deleted_at').first();
  if (!target) throw notFound('Usuário não encontrado');
  if (target.id === req.rtg.userId) throw badRequest('Você não pode excluir a própria conta');
  if (target.role === 'superuser' && req.rtg.role !== 'superuser') {
    throw forbidden('Apenas um superusuário pode excluir um superusuário');
  }
  await assertNotLastSuperuser(target, { status: 'blocked' });

  await db('retaguarda_users').where({ id: target.id }).update({
    deleted_at: now(),
    updated_at: now(),
  });
  await db('retaguarda_sessions').where({ retaguarda_user_id: target.id }).update({ revoked_at: now() });
  await audit({ auth: { userId: req.rtg.userId }, entity: 'retaguarda_users', entityId: target.id, action: 'delete', req });
  res.json({ data: { ok: true } });
});

/**
 * Impede que a última conta de superusuário ativa seja perdida (por rebaixamento,
 * bloqueio ou exclusão) — a retaguarda ficaria sem superusuário.
 */
async function assertNotLastSuperuser(target, changes) {
  if (target.role !== 'superuser') return;
  const losesSuperuser = (changes.role && changes.role !== 'superuser') || changes.status === 'blocked';
  if (!losesSuperuser) return;
  const activeSuperusers = await db('retaguarda_users')
    .where({ role: 'superuser', status: 'active' })
    .whereNull('deleted_at')
    .count({ n: '*' })
    .first();
  if (Number(activeSuperusers.n) <= 1) {
    throw badRequest('É necessário manter ao menos um superusuário ativo');
  }
}

export default router;
