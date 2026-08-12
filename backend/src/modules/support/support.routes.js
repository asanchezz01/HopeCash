import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';

import { config } from '../../config.js';
import { sendMail } from '../../core/mailer.js';
import { validate } from '../../middleware/validate.js';
import { escapeHtml } from '../../utils/html.js';
import { HttpError } from '../../utils/httpError.js';

const router = Router();

const categoryLabels = {
  access: 'Acesso e senha',
  sync: 'Sincronização',
  transactions: 'Lançamentos',
  imports: 'Importação de extrato',
  hope: 'Hope e comandos por voz',
  planning: 'Contas, cartões e planejamento',
  other: 'Outro assunto',
};

const supportSchema = z.object({
  name: z.string().trim().min(2, 'Informe seu nome').max(120),
  email: z.string().trim().email('Informe um e-mail válido').max(254).toLowerCase(),
  category: z.enum(Object.keys(categoryLabels)),
  app_version: z.string().trim().max(40).optional().default(''),
  platform: z.enum(['ios', 'android', 'web', '']).optional().default(''),
  message: z.string().trim().min(20, 'Descreva o problema com pelo menos 20 caracteres').max(4000),
  website: z.string().max(200).optional().default(''),
});

const supportLimiter = rateLimit({
  windowMs: config.support.rateLimitWindowMs,
  limit: config.support.rateLimitMax,
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => config.isTest,
  message: {
    error: {
      code: 'SUPPORT_RATE_LIMIT',
      message: 'Muitas solicitações em pouco tempo. Aguarde alguns minutos e tente novamente.',
    },
  },
});

let supportMailer = sendMail;

export function _setSupportMailerForTests(mailer) {
  supportMailer = mailer ?? sendMail;
}

router.post('/', supportLimiter, validate(supportSchema), async (req, res) => {
  const { name, email, category, app_version: appVersion, platform, message, website } = req.body;

  // Campo invisível preenchido por bots: responde como sucesso sem disparar e-mail.
  if (website) {
    return res.status(201).json({
      data: { message: 'Solicitação recebida. Acompanhe a resposta pelo seu e-mail.' },
    });
  }

  const categoryLabel = categoryLabels[category];
  const platformLabel = {
    ios: 'iPhone ou iPad',
    android: 'Android',
    web: 'Navegador Web',
    '': 'Não informado',
  }[platform];
  const subject = `${config.support.subjectPrefix} ${categoryLabel}`;
  const text = [
    'Nova solicitação pública de suporte do HopeCash',
    '',
    `Nome: ${name}`,
    `E-mail: ${email}`,
    `Assunto: ${categoryLabel}`,
    `Plataforma: ${platformLabel}`,
    `Versão do app: ${appVersion || 'Não informada'}`,
    '',
    'Mensagem:',
    message,
  ].join('\n');
  const html = `
    <h1>Nova solicitação de suporte</h1>
    <p><strong>Nome:</strong> ${escapeHtml(name)}</p>
    <p><strong>E-mail:</strong> ${escapeHtml(email)}</p>
    <p><strong>Assunto:</strong> ${escapeHtml(categoryLabel)}</p>
    <p><strong>Plataforma:</strong> ${escapeHtml(platformLabel)}</p>
    <p><strong>Versão do app:</strong> ${escapeHtml(appVersion || 'Não informada')}</p>
    <hr>
    <p>${escapeHtml(message).replace(/\n/g, '<br>')}</p>
  `;

  const result = await supportMailer({
    to: config.support.emailTo,
    replyTo: email,
    subject,
    text,
    html,
  });
  if (!result.sent) {
    throw new HttpError(
      503,
      'SUPPORT_UNAVAILABLE',
      'O canal de suporte está indisponível agora. Tente novamente em alguns minutos.',
    );
  }

  return res.status(201).json({
    data: { message: 'Solicitação enviada. Acompanhe a resposta pelo seu e-mail.' },
  });
});

export default router;
