import nodemailer from 'nodemailer';
import { config } from '../config.js';
import { logger } from '../logger.js';

/**
 * Envio de e-mail transacional (reset de senha, avisos da retaguarda).
 *
 * Com MAIL_ENABLED=false o conteúdo é apenas registrado no log e nada é
 * enviado de fato — assim a retaguarda funciona em dev/ambientes sem SMTP.
 * O transporter é criado sob demanda e reutilizado.
 */
let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  transporter = nodemailer.createTransport({
    host: config.mail.host,
    port: config.mail.port,
    secure: config.mail.port === 465, // 465 = TLS implícito; 587 = STARTTLS
    requireTLS: config.mail.useTls && config.mail.port !== 465,
    auth: config.mail.user ? { user: config.mail.user, pass: config.mail.pass } : undefined,
  });
  return transporter;
}

/**
 * Envia um e-mail. Retorna { sent } indicando se saiu de fato pela rede.
 * Nunca lança: uma falha de e-mail não deve derrubar a operação de negócio.
 */
export async function sendMail({ to, subject, text, html }) {
  if (!config.mail.enabled) {
    logger.info({ to, subject, text }, 'E-mail desabilitado (MAIL_ENABLED=false) — conteúdo apenas registrado');
    return { sent: false };
  }
  try {
    await getTransporter().sendMail({ from: config.mail.from, to, subject, text, html });
    logger.info({ to, subject }, 'E-mail enviado');
    return { sent: true };
  } catch (err) {
    logger.error({ err, to, subject }, 'Falha ao enviar e-mail');
    return { sent: false, error: err.message };
  }
}
