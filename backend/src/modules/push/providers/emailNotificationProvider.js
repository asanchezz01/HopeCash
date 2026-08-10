import { sendMail } from '../../../core/mailer.js';

/**
 * Provedor de e-mail de notificações (produção) — usa o mesmo transporte SMTP já
 * configurado para e-mails transacionais (`core/mailer.js`). Respeita
 * `MAIL_ENABLED`: com `false`, `sendMail` só registra no log e não envia de
 * fato (dry-run), sem precisar de um provedor "desabilitado" separado.
 */
export class RealEmailNotificationProvider {
  async send({ to, subject, html, text }) {
    const result = await sendMail({ to, subject, html, text });
    if (result.sent) return { ok: true };
    // MAIL_ENABLED=false é dry-run deliberado (sem `error`) — não é falha a re-tentar,
    // igual ao DisabledPushProvider. Só uma falha real de SMTP entra em retry.
    if (!result.error) return { ok: true, dryRun: true };
    return { ok: false, error: result.error, permanent: false };
  }
}
