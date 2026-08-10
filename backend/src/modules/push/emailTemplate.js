/**
 * Layout HTML do e-mail de notificação. Quando autorizado pelo usuário, o
 * canal funciona junto com o push. Tabelas + CSS inline de propósito — é o jeito que
 * funciona de forma consistente nos clientes de e-mail (Gmail, Outlook,
 * Apple Mail), diferente de HTML "normal" de web.
 */

import { escapeHtml } from '../../utils/html.js';

const BRAND_COLOR = '#16C784'; // mesmo verde do theme-color do PWA e da cor de notificação do Android
const TEXT_COLOR = '#1B263B';
const MUTED_COLOR = '#64748B';

/**
 * Monta o HTML e o texto simples do e-mail de notificação.
 * `actionUrl` é opcional — sem `PUSH_EMAIL_APP_URL` configurado, o e-mail sai
 * só com o texto informativo, sem botão.
 */
export function renderNotificationEmail({ title, body, actionUrl, actionLabel = 'Abrir o HopeCash' }) {
  const safeTitle = escapeHtml(title);
  const safeBody = escapeHtml(body).replace(/\n/g, '<br>');
  const safeActionLabel = escapeHtml(actionLabel);

  const button = actionUrl ? `
    <tr>
      <td align="center" style="padding: 8px 32px 32px 32px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="center" bgcolor="${BRAND_COLOR}" style="border-radius: 8px;">
              <a href="${escapeHtml(actionUrl)}" target="_blank"
                 style="display: inline-block; padding: 14px 28px; font-family: Arial, Helvetica, sans-serif;
                        font-size: 15px; font-weight: bold; color: #ffffff; text-decoration: none; border-radius: 8px;">
                ${safeActionLabel}
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>` : '';

  const html = `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${safeTitle}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #F1F5F9; font-family: Arial, Helvetica, sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #F1F5F9; padding: 32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width: 480px; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08);">
          <tr>
            <td align="center" bgcolor="${BRAND_COLOR}" style="padding: 28px 24px;">
              <span style="font-family: Arial, Helvetica, sans-serif; font-size: 22px; font-weight: bold; color: #ffffff; letter-spacing: 0.3px;">
                HopeCash
              </span>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px 32px 8px 32px;">
              <h1 style="margin: 0 0 12px 0; font-family: Arial, Helvetica, sans-serif; font-size: 20px; color: ${TEXT_COLOR};">
                ${safeTitle}
              </h1>
              <p style="margin: 0; font-family: Arial, Helvetica, sans-serif; font-size: 15px; line-height: 1.6; color: ${TEXT_COLOR};">
                ${safeBody}
              </p>
            </td>
          </tr>
          ${button}
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 0 0 20px 0;">
              <p style="margin: 0; font-family: Arial, Helvetica, sans-serif; font-size: 12px; line-height: 1.6; color: ${MUTED_COLOR};">
                Você recebeu este e-mail porque autorizou notificações por e-mail
                na sua conta HopeCash. Os avisos também podem chegar por este canal
                quando o push estiver ativo. Para não receber mais avisos por
                e-mail, abra o app, acesse <strong>Mais → Notificações</strong> e
                desative “Notificações por e-mail”.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const textLines = [title, '', body];
  if (actionUrl) textLines.push('', `${actionLabel}: ${actionUrl}`);
  textLines.push(
    '',
    '— Você recebeu este e-mail porque autorizou notificações por e-mail na sua '
    + 'conta HopeCash. Os avisos também podem chegar por este canal quando '
    + 'o push estiver ativo. Para não receber mais avisos por e-mail, abra o app, '
    + 'acesse Mais > Notificações e desative "Notificações por e-mail".',
  );

  return { html, text: textLines.join('\n') };
}
