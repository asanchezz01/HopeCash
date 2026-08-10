import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { requireSuperuser } from '../../middleware/retaguardaAuth.js';
import { audit } from '../../core/audit.js';
import { listAutomationRules, updateAutomationRule } from '../push/services/automationRulesService.js';
import { generateTip } from '../push/services/tipGenerationService.js';
import { createDraftCampaign, sendCampaignNow } from '../push/services/campaignService.js';

/**
 * Gestão das mensagens push automáticas (avisos de vencimento, insights
 * financeiros, dicas da Hope) — liga/desliga cada tipo e ajusta frequência e
 * conteúdo sem precisar de redeploy. Montado em /api/v1/retaguarda/automation-rules.
 */
const router = Router();

const updateSchema = z.object({
  enabled: z.coerce.boolean().optional(),
  frequency_days: z.coerce.number().int().min(0).max(365).optional(),
  title: z.string().max(150).nullish(),
  body: z.string().max(500).nullish(),
  config: z.record(z.any()).nullish(),
});

const generateTipSchema = z.object({
  user_id: z.string().uuid().nullish(),
});

const sendTipSchema = z.object({
  title: z.string().trim().min(1).max(150),
  body: z.string().trim().min(1).max(500),
  user_id: z.string().uuid().nullish(),
});

/** Lista as regras (uma por tipo de mensagem automática) — leitura aberta a admin e superuser. */
router.get('/', async (_req, res) => {
  res.json({ data: await listAutomationRules() });
});

/** Gera uma nova dica geral ou, com user_id, uma dica baseada em dados financeiros agregados. */
router.post('/tip/generate', requireSuperuser, validate(generateTipSchema), async (req, res) => {
  const tip = await generateTip({ userId: req.body.user_id ?? undefined });
  await audit({
    auth: { userId: req.rtg.userId }, entity: 'push_automation_rules', entityId: 'tip',
    action: 'generate_tip', changes: { personalized: tip.personalized, target_user_id: tip.target_user_id }, req,
  });
  res.json({ data: tip });
});

/** Envia o conteúdo informado imediatamente, preservando-o no histórico de campanhas. */
router.post('/tip/send', requireSuperuser, validate(sendTipSchema), async (req, res) => {
  const targetUserId = req.body.user_id ?? null;
  const campaign = await createDraftCampaign({
    title: req.body.title,
    body: req.body.body,
    category: 'tips',
    audience: targetUserId ? 'selected' : 'all',
    target_user_ids: targetUserId ? [targetUserId] : undefined,
  }, req.rtg.userId);
  const sent = await sendCampaignNow(campaign.id);
  await audit({
    auth: { userId: req.rtg.userId }, entity: 'push_campaigns', entityId: sent.id,
    action: 'send_tip_now', changes: { personalized: !!targetUserId, target_user_id: targetUserId }, req,
  });
  res.json({ data: sent });
});

/** Liga/desliga e ajusta frequência/conteúdo — ação sensível, restrita a superusuário. */
router.put('/:messageType', requireSuperuser, validate(updateSchema), async (req, res) => {
  const rule = await updateAutomationRule(req.params.messageType, req.body, req.rtg.userId);
  await audit({
    auth: { userId: req.rtg.userId }, entity: 'push_automation_rules', entityId: rule.id,
    action: 'update', changes: req.body, req,
  });
  res.json({ data: rule });
});

export default router;
