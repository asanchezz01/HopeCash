/**
 * Páginas HTML do fluxo OAuth (login + consentimento). Mesmo estilo "função
 * retorna string HTML" de modules/push/emailTemplate.js.
 *
 * Nasceu sem JS de propósito (formulário puro evitava qualquer questão de CSP
 * script-src). Isso se mostrou um erro em 2026-08-07: o submit levava ~300ms
 * e o botão não dava NENHUM sinal de que algo estava acontecendo, então dentro
 * do navegador embutido do ChatGPT a página parecia travada — uma usuária
 * clicou 32 vezes em 40s, e cada clique emitiu um authorization code novo.
 * Agora existe um script mínimo, servido com nonce (ver oauth.routes.js), só
 * para dar retorno visual e impedir o reenvio duplicado.
 */
import { escapeHtml } from '../../utils/html.js';

const BRAND_COLOR = '#16C784';
const TEXT_COLOR = '#1B263B';
const MUTED_COLOR = '#64748B';

// Stack de fonte do sistema: renderiza SF Pro no iOS, Segoe UI no Windows,
// Roboto no Android. Herdamos `Arial, Helvetica` do emailTemplate.js junto com
// o resto do estilo, mas ali a fonte web-safe existe por causa de cliente de
// e-mail — aqui é uma página web normal, e Arial só fazia esta tela (a
// primeira coisa que alguém vê ao conectar o HopeCash a uma IA) parecer
// genérica. Continua sem custo: nenhuma requisição externa, nada a liberar no
// CSP restrito desta página.
const FONT_STACK = "-apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, Roboto, sans-serif";

const shell = (title, body) => `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #F1F5F9; font-family: ${FONT_STACK}; color: ${TEXT_COLOR};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #F1F5F9; padding: 32px 16px; min-height: 100vh;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width: 420px; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08);">
          <tr>
            <td align="center" bgcolor="${BRAND_COLOR}" style="padding: 28px 24px;">
              <span style="font-size: 22px; font-weight: bold; color: #ffffff; letter-spacing: 0.3px;">HopeCash</span>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px;">
              ${body}
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

const hidden = (name, value) => (value == null ? '' : `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(value)}">`);

// `font-family: inherit` porque input/button NÃO herdam a fonte do body —
// sem isso os campos e o botão cairiam na fonte padrão de formulário do
// navegador e destoariam do resto da página.
const inputStyle = 'width: 100%; box-sizing: border-box; padding: 12px 14px; margin-top: 6px; border: 1px solid #CBD5E1; border-radius: 8px; font-size: 15px; font-family: inherit;';
const labelStyle = `display: block; font-size: 13px; font-weight: bold; color: ${MUTED_COLOR}; margin-top: 16px;`;

/**
 * Tela única de login + escolha de permissão. `params` são os parâmetros
 * OAuth recebidos no /authorize, ecoados como campos hidden para o POST.
 */
export function renderAuthorizePage({ client, params, error, nonce }) {
  const appName = escapeHtml(client.clientName || 'Um aplicativo externo');
  const hiddenFields = [
    hidden('response_type', params.responseType),
    hidden('client_id', params.clientId),
    hidden('redirect_uri', params.redirectUri),
    hidden('code_challenge', params.codeChallenge),
    hidden('code_challenge_method', params.codeChallengeMethod),
    hidden('state', params.state),
    hidden('scope', params.scope),
    hidden('resource', params.resource),
  ].join('\n');

  const errorBlock = error
    ? `<div style="background-color: #FEE2E2; color: #991B1B; padding: 12px 14px; border-radius: 8px; font-size: 14px; margin-bottom: 16px;">${escapeHtml(error)}</div>`
    : '';

  const body = `
    <h1 style="margin: 0 0 4px 0; font-size: 19px;">${appName} quer acessar sua conta</h1>
    <p style="margin: 0 0 20px 0; font-size: 14px; line-height: 1.5; color: ${MUTED_COLOR};">
      Entre com sua conta HopeCash para autorizar. Você escolhe abaixo o que ${appName} pode fazer,
      e pode revogar o acesso a qualquer momento em Mais → Tokens de API.
    </p>
    ${errorBlock}
    <form method="post" action="/api/v1/oauth/authorize" id="authorize-form">
      ${hiddenFields}
      <label style="${labelStyle}" for="email">E-mail</label>
      <input style="${inputStyle}" type="email" id="email" name="email" required autofocus>
      <label style="${labelStyle}" for="password">Senha</label>
      <input style="${inputStyle}" type="password" id="password" name="password" required>

      <div style="margin-top: 20px; border: 1px solid #E2E8F0; border-radius: 8px; padding: 14px;">
        <label style="display: flex; align-items: flex-start; gap: 10px; font-size: 14px; cursor: pointer;">
          <input type="radio" name="kind" value="mcp_read" checked style="margin-top: 3px;">
          <span><strong>Somente leitura</strong><br><span style="color: ${MUTED_COLOR};">Consulta saldos, lançamentos, orçamento etc. Não altera nada.</span></span>
        </label>
        <label style="display: flex; align-items: flex-start; gap: 10px; font-size: 14px; cursor: pointer; margin-top: 12px;">
          <input type="radio" name="kind" value="mcp_write" style="margin-top: 3px;">
          <span><strong>Leitura e escrita</strong><br><span style="color: ${MUTED_COLOR};">Também pode propor lançamentos — cada um exige sua confirmação.</span></span>
        </label>
      </div>

      <button type="submit" id="authorize-submit" style="width: 100%; margin-top: 20px; padding: 13px; background-color: ${BRAND_COLOR}; color: #ffffff; border: none; border-radius: 8px; font-size: 15px; font-weight: bold; font-family: inherit; cursor: pointer;">
        Entrar e autorizar
      </button>
      <p id="authorize-hint" style="display: none; margin: 12px 0 0 0; font-size: 13px; line-height: 1.5; color: ${MUTED_COLOR}; text-align: center;"></p>
    </form>
    ${submitFeedbackScript(nonce)}`;

  return shell(`${client.clientName || 'Aplicativo'} quer acessar sua conta HopeCash`, body);
}

/**
 * Retorno visual do submit. Resolve três coisas observadas em produção:
 * o botão vira "Entrando…" (a página não parece mais travada), o reenvio fica
 * bloqueado (um clique = um authorization code, não 32), e se depois de 15s
 * nada aconteceu o botão volta a funcionar com uma explicação — antes disso o
 * usuário não tinha como saber se devia esperar ou tentar de novo.
 *
 * `pageshow` cobre o bfcache: voltar para esta página não pode deixar o botão
 * permanentemente desabilitado.
 */
function submitFeedbackScript(nonce) {
  if (!nonce) return '';
  return `<script nonce="${escapeHtml(nonce)}">
(function () {
  var form = document.getElementById('authorize-form');
  var button = document.getElementById('authorize-submit');
  var hint = document.getElementById('authorize-hint');
  if (!form || !button || !hint) return;
  var pending = false;
  var timer = null;

  function reset() {
    pending = false;
    if (timer) { clearTimeout(timer); timer = null; }
    button.disabled = false;
    button.textContent = 'Entrar e autorizar';
    button.style.opacity = '1';
    button.style.cursor = 'pointer';
  }

  form.addEventListener('submit', function (event) {
    if (pending) { event.preventDefault(); return; }
    pending = true;
    button.disabled = true;
    button.textContent = 'Entrando\\u2026';
    button.style.opacity = '0.65';
    button.style.cursor = 'progress';
    hint.textContent = 'Autorizando e voltando para o aplicativo\\u2026';
    hint.style.display = 'block';
    timer = setTimeout(function () {
      reset();
      hint.textContent = 'Est\\u00e1 demorando mais que o normal. Toque novamente para tentar de novo.';
    }, 15000);
  });

  window.addEventListener('pageshow', reset);
})();
</script>`;
}

/** Erro de protocolo antes de validar client_id/redirect_uri — nunca redireciona, sempre uma página estática. */
export function renderErrorPage(message) {
  const body = `
    <h1 style="margin: 0 0 8px 0; font-size: 19px;">Não foi possível continuar</h1>
    <p style="margin: 0; font-size: 14px; line-height: 1.5; color: ${MUTED_COLOR};">${escapeHtml(message)}</p>`;
  return shell('HopeCash — erro', body);
}
