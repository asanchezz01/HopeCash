import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { requireSuperuser } from '../../middleware/retaguardaAuth.js';
import { badRequest } from '../../utils/httpError.js';
import { audit } from '../../core/audit.js';
import { isAllowedDeepLink } from '../push/deepLinks.js';
import { zonedTimeToUtc, toCanonicalUtc } from '../push/timezone.js';
import {
  createDraftCampaign, listCampaigns, getCampaign, updateCampaign,
  scheduleCampaign, cancelCampaign, previewCampaign, sendCampaignNow,
  getCampaignStats, reprocessCampaignFailures, deleteCampaign, resendCampaign,
  listCampaignRecipients,
} from '../push/services/campaignService.js';

const router = Router();

const campaignBody = {
  title: z.string().min(1).max(150),
  body: z.string().min(1).max(500),
  category: z.enum(['general', 'tips', 'insights', 'maintenance', 'promo']).default('general'),
  audience: z.enum(['all', 'selected']).default('all'),
  target_user_ids: z.array(z.string().uuid()).max(5000).optional(),
  deep_link: z.string().max(300).nullish(),
};
const createCampaignSchema = z.object(campaignBody);
const updateCampaignSchema = z.object(campaignBody).partial();

const scheduleSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Data no formato YYYY-MM-DD'),
  time: z.string().regex(/^\d{2}:\d{2}$/, 'Horário no formato HH:MM'),
  timezone: z.string().min(1).max(60),
});

const listQuery = z.object({
  status: z.enum(['draft', 'scheduled', 'processing', 'sent', 'partially_sent', 'canceled', 'failed']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const recipientListQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(100),
});

const resendSchema = z.object({
  channel: z.enum(['push', 'email', 'both']).default('both'),
});

/** Cria um rascunho de campanha de notificação push. */
router.post('/', validate(createCampaignSchema), async (req, res) => {
  const campaign = await createDraftCampaign(req.body, req.rtg.userId);
  await audit({ auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: campaign.id, action: 'create', req });
  res.status(201).json({ data: campaign });
});

router.get('/', validate(listQuery, 'query'), async (req, res) => {
  const { status, page, limit } = req.query;
  res.json(await listCampaigns({ status, page, limit }));
});

router.get('/:id', async (req, res) => {
  res.json({ data: await getCampaign(req.params.id) });
});

router.get('/:id/preview', async (req, res) => {
  res.json({ data: await previewCampaign(req.params.id) });
});

router.get('/:id/recipients', validate(recipientListQuery, 'query'), async (req, res) => {
  const { page, limit } = req.query;
  res.json(await listCampaignRecipients(req.params.id, { page, limit }));
});

router.get('/:id/stats', async (req, res) => {
  res.json({ data: await getCampaignStats(req.params.id) });
});

/** Edita uma campanha ainda não processada (rascunho ou agendada). */
router.put('/:id', validate(updateCampaignSchema), async (req, res) => {
  const campaign = await updateCampaign(req.params.id, req.body);
  await audit({ auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: campaign.id, action: 'update', req });
  res.json({ data: campaign });
});

/** Envio imediato — ação sensível, restrita a superusuário. */
router.post('/:id/send', requireSuperuser, async (req, res) => {
  const campaign = await sendCampaignNow(req.params.id);
  await audit({ auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: campaign.id, action: 'send', req });
  res.json({ data: campaign });
});

/** Agendamento — o operador escolhe data/horário/fuso; a campanha é gravada em UTC. */
router.post('/:id/schedule', requireSuperuser, validate(scheduleSchema), async (req, res) => {
  const { date, time, timezone } = req.body;
  const scheduledAt = zonedTimeToUtc(`${date} ${time}`, timezone);
  if (scheduledAt.getTime() <= Date.now()) throw badRequest('A data/horário agendados precisam estar no futuro');

  const campaign = await scheduleCampaign(req.params.id, { scheduledAt: toCanonicalUtc(scheduledAt), timezone });
  await audit({
    auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: campaign.id, action: 'schedule',
    changes: { scheduled_at: campaign.scheduled_at, timezone }, req,
  });
  res.json({ data: campaign });
});

/** Cancelamento — ação sensível, restrita a superusuário. */
router.post('/:id/cancel', requireSuperuser, async (req, res) => {
  const campaign = await cancelCampaign(req.params.id);
  await audit({ auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: campaign.id, action: 'cancel', req });
  res.json({ data: campaign });
});

/** Reprocessa falhas temporárias (token ainda válido) — restrito a superusuário. */
router.post('/:id/reprocess', requireSuperuser, async (req, res) => {
  const result = await reprocessCampaignFailures(req.params.id);
  await audit({ auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: req.params.id, action: 'reprocess', changes: result, req });
  res.json({ data: result });
});

/** Exclui a campanha e seu histórico de entregas — ação sensível, restrita a superusuário. */
router.delete('/:id', requireSuperuser, async (req, res) => {
  await deleteCampaign(req.params.id);
  await audit({ auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: req.params.id, action: 'delete', req });
  res.json({ data: { ok: true } });
});

/** Reenvia: duplica como rascunho e envia imediatamente — restrito a superusuário. */
router.post('/:id/resend', requireSuperuser, validate(resendSchema), async (req, res) => {
  const campaign = await resendCampaign(req.params.id, req.rtg.userId, { channel: req.body.channel });
  await audit({
    auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: campaign.id, action: 'resend',
    changes: { source_campaign_id: req.params.id, channel: req.body.channel }, req,
  });
  res.status(201).json({ data: campaign });
});

/** Endpoint auxiliar: valida se um deep link está na lista de permissão (usado pelo formulário da retaguarda). */
router.post('/deep-links/validate', validate(z.object({ deep_link: z.string().max(300) })), (req, res) => {
  res.json({ data: { allowed: isAllowedDeepLink(req.body.deep_link) } });
});

export default router;
