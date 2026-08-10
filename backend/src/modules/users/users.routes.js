import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { now } from '../../utils/time.js';
import { hashPassword, verifyPassword } from '../../utils/password.js';
import { badRequest, notFound, unauthorized } from '../../utils/httpError.js';
import { ENTITIES } from '../../core/registry.js';
import { applyScope, deserialize } from '../../core/syncRepo.js';
import { audit } from '../../core/audit.js';
import { listDevicesForUser, deleteAllDevicesForUser } from '../push/services/deviceService.js';
import { getPreferences, deletePreferencesForUser } from '../push/services/preferencesService.js';
import { deleteAllDeliveriesForUser } from '../push/services/deliveryService.js';

const router = Router();

const PUBLIC_FIELDS = ['id', 'name', 'email', 'avatar_url', 'locale', 'currency', 'status', 'onboarding_completed_at', 'created_at'];
const passwordSchema = z.string().min(8, 'Mínimo de 8 caracteres')
  .regex(/[a-zA-Z]/, 'Deve conter letras').regex(/[0-9]/, 'Deve conter números');

router.get('/me', async (req, res) => {
  const user = await db('users').where({ id: req.auth.userId }).first(PUBLIC_FIELDS);
  if (!user) throw notFound();
  res.json({ data: user });
});

router.put('/me', validate(z.object({
  name: z.string().min(2).max(120).optional(),
  avatar_url: z.string().url().nullish(),
  locale: z.string().max(10).optional(),
  currency: z.string().length(3).optional(),
})), async (req, res) => {
  await db('users').where({ id: req.auth.userId }).update({ ...req.body, updated_at: now() });
  const user = await db('users').where({ id: req.auth.userId }).first(PUBLIC_FIELDS);
  res.json({ data: user });
});

router.put('/me/login', validate(z.object({
  name: z.string().min(2).max(120),
  email: z.string().email().toLowerCase(),
  current_password: z.string(),
})), async (req, res) => {
  const user = await db('users').where({ id: req.auth.userId }).first();
  if (!user) throw notFound();
  if (!(await verifyPassword(req.body.current_password, user.password_hash))) {
    throw unauthorized('Senha atual inválida');
  }

  if (req.body.email !== user.email) {
    const exists = await db('users')
      .where({ email: req.body.email })
      .whereNot({ id: user.id })
      .whereNull('deleted_at')
      .first();
    if (exists) throw badRequest('E-mail já cadastrado');
  }

  await db('users').where({ id: user.id }).update({
    name: req.body.name,
    email: req.body.email,
    updated_at: now(),
  });
  await audit({ auth: req.auth, entity: 'users', entityId: user.id, action: 'login_data_updated', req });
  const updated = await db('users').where({ id: user.id }).first(PUBLIC_FIELDS);
  res.json({ data: updated });
});

/**
 * Marca o tutorial de boas-vindas como visto (concluído ou pulado).
 * Idempotente: chamadas repetidas preservam a data da primeira conclusão.
 */
router.put('/me/onboarding', async (req, res) => {
  await db('users')
    .where({ id: req.auth.userId })
    .whereNull('onboarding_completed_at')
    .update({ onboarding_completed_at: now(), updated_at: now() });
  const user = await db('users').where({ id: req.auth.userId }).first(PUBLIC_FIELDS);
  if (!user) throw notFound();
  res.json({ data: { onboarding_completed_at: user.onboarding_completed_at } });
});

router.put('/me/password', validate(z.object({
  current_password: z.string(),
  password: passwordSchema,
})), async (req, res) => {
  const user = await db('users').where({ id: req.auth.userId }).first();
  if (!user) throw notFound();
  if (!(await verifyPassword(req.body.current_password, user.password_hash))) {
    throw unauthorized('Senha atual inválida');
  }

  await db('users').where({ id: user.id }).update({
    password_hash: await hashPassword(req.body.password),
    updated_at: now(),
  });
  await db('user_sessions').where({ user_id: user.id }).update({ revoked_at: now() });
  await audit({ auth: req.auth, entity: 'users', entityId: user.id, action: 'password_updated', req });
  res.json({ data: { message: 'Senha atualizada com sucesso.' } });
});

/** Exportação LGPD: todos os dados do usuário em JSON. */
router.get('/me/export', async (req, res) => {
  const user = await db('users').where({ id: req.auth.userId }).first(PUBLIC_FIELDS);
  const data = { user, exported_at: now(), entities: {} };
  for (const [name, def] of Object.entries(ENTITIES)) {
    const rows = await applyScope(db(def.table), name, req.auth);
    data.entities[name] = rows.map((r) => deserialize(name, r));
  }
  // Dispositivos e preferências de push não fazem parte do registro de sincronização
  // genérico (ENTITIES) — incluídos aqui explicitamente para a exportação ficar completa.
  data.push_devices = await listDevicesForUser(req.auth.userId);
  data.push_preferences = await getPreferences(req.auth.userId);
  await audit({ auth: req.auth, entity: 'users', entityId: req.auth.userId, action: 'export', req });
  res.setHeader('Content-Disposition', 'attachment; filename="hopecash-export.json"');
  res.json(data);
});

/** Exclusão definitiva da conta (LGPD): remove fisicamente todos os dados. */
router.delete('/me', async (req, res) => {
  const userId = req.auth.userId;
  await db.transaction(async (trx) => {
    for (const def of Object.values(ENTITIES)) {
      await trx(def.table).where({ user_id: userId }).del();
    }
    await trx('sync_operations').where({ user_id: userId }).del();
    await trx('user_sessions').where({ user_id: userId }).del();
    await trx('families').where({ owner_id: userId }).del();
    // Notificações push não fazem parte do ENTITIES — removidas explicitamente.
    await deleteAllDeliveriesForUser(userId, trx);
    await deleteAllDevicesForUser(userId, trx);
    await deletePreferencesForUser(userId, trx);
    await trx('users').where({ id: userId }).del();
  });
  await audit({ auth: req.auth, entity: 'users', entityId: userId, action: 'account_deleted', req });
  res.json({ data: { message: 'Conta e dados excluídos definitivamente.' } });
});

router.get('/me/sessions', async (req, res) => {
  const sessions = await db('user_sessions')
    .where({ user_id: req.auth.userId })
    .whereNull('revoked_at')
    .where('expires_at', '>', now())
    .select('id', 'device_name', 'ip', 'created_at', 'expires_at')
    .orderBy('created_at', 'desc');
  res.json({ data: sessions });
});

/** Logout remoto de um dispositivo específico. */
router.delete('/me/sessions/:id', async (req, res) => {
  const updated = await db('user_sessions')
    .where({ id: req.params.id, user_id: req.auth.userId })
    .update({ revoked_at: now() });
  if (!updated) throw notFound('Sessão não encontrada');
  res.json({ data: { ok: true } });
});

export default router;
