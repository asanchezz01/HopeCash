import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { registerDevice, deactivateDevice, listDevicesForUser, PUBLIC_DEVICE_FIELDS } from './services/deviceService.js';
import { getPreferences, updatePreferences } from './services/preferencesService.js';

const router = Router();

const registerDeviceSchema = z.object({
  token: z.string().min(20).max(500),
  platform: z.enum(['web', 'pwa', 'android', 'ios']),
  install_id: z.string().max(120).nullish(),
  app_version: z.string().max(30).nullish(),
  locale: z.string().max(10).nullish(),
  timezone: z.string().max(60).nullish(),
});

const deactivateDeviceSchema = z.object({ token: z.string().min(1).max(500) });

const preferencesSchema = z.object({
  push_enabled: z.coerce.boolean().optional(),
  due_reminders_enabled: z.coerce.boolean().optional(),
  financial_insights_enabled: z.coerce.boolean().optional(),
  tips_enabled: z.coerce.boolean().optional(),
  // Canal de e-mail independente — desligável aqui.
  email_notifications_enabled: z.coerce.boolean().optional(),
  reminder_advance_days: z.coerce.number().int().min(0).max(30).optional(),
  preferred_hour: z.coerce.number().int().min(0).max(23).nullish(),
  timezone: z.string().max(60).optional(),
});

/** Registra (ou atualiza, de forma idempotente) o token FCM do dispositivo do usuário autenticado. */
router.post('/devices', validate(registerDeviceSchema), async (req, res) => {
  const device = await registerDevice(req.auth.userId, req.body);
  res.status(201).json({ data: device });
});

/** Desativa o token no logout — idempotente. */
router.post('/devices/deactivate', validate(deactivateDeviceSchema), async (req, res) => {
  const ok = await deactivateDevice(req.auth.userId, req.body.token);
  res.json({ data: { ok } });
});

router.get('/devices', async (req, res) => {
  const devices = await listDevicesForUser(req.auth.userId);
  res.json({ data: devices.map((d) => Object.fromEntries(PUBLIC_DEVICE_FIELDS.map((f) => [f, d[f]]))) });
});

router.get('/preferences', async (req, res) => {
  res.json({ data: await getPreferences(req.auth.userId) });
});

router.put('/preferences', validate(preferencesSchema), async (req, res) => {
  res.json({ data: await updatePreferences(req.auth.userId, req.body) });
});

export default router;
