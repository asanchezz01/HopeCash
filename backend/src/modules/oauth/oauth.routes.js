/**
 * Endpoints OAuth 2.1 do Authorization Server do MCP da Hope — Dynamic
 * Client Registration (RFC 7591), authorization code + PKCE (RFC 6749 +
 * RFC 7636). Montados em /api/v1/oauth, fora do gate de autenticação do v1
 * (são deliberadamente públicos — é assim que se ganha um token).
 *
 * /register e /token respondem no formato OAuth padrão ({ error,
 * error_description }), não no { error: { code, message } } do resto da API
 * — é o formato que bibliotecas cliente OAuth de verdade esperam.
 */
import crypto from 'node:crypto';
import { Router } from 'express';
import {
  OAuthError,
  registerClient,
  findClient,
  isRegisteredRedirect,
  verifyLogin,
  issueAuthorizationCode,
  exchangeAuthorizationCode,
} from './oauth.service.js';
import { renderAuthorizePage, renderErrorPage } from './pages.js';

const router = Router();

/** Erro de protocolo depois que redirect_uri já foi validada — volta pro client via redirect, como o OAuth prevê. */
function redirectWithError(res, redirectUri, state, error, description) {
  const url = new URL(redirectUri);
  url.searchParams.set('error', error);
  url.searchParams.set('error_description', description);
  if (state) url.searchParams.set('state', state);
  return res.redirect(302, url.toString());
}

/**
 * Envia a tela de login/consentimento com um CSP próprio, sobrescrevendo o do
 * helmet só nesta página. Dois motivos:
 *
 * 1. `form-action 'self'` (padrão do helmet) é ativamente hostil a um
 *    Authorization Server: o /authorize TEM que redirecionar o POST do
 *    formulário para o `redirect_uri` do client, e WebKit e Firefox aplicam
 *    `form-action` também ao redirect que segue o submit — o navegador
 *    engole a navegação sem erro visível. Aqui a diretiva libera exatamente a
 *    origem do `redirect_uri`, que `resolveClientOrError` já validou contra os
 *    `redirect_uris` registrados do client (a proteção real é essa, no
 *    servidor — o CSP nunca foi o que impedia redirect para um destino
 *    arbitrário).
 * 2. `script-src 'self'` bloquearia o script inline de feedback do submit;
 *    o nonce libera aquele script específico e nada mais.
 */
function sendAuthorizePage(res, { client, params, error = null, status = 200 }) {
  const nonce = crypto.randomBytes(16).toString('base64');

  const formAction = ["'self'"];
  try {
    formAction.push(new URL(params.redirectUri).origin);
  } catch {
    // redirect_uri ausente/malformada só chega aqui em erro de validação —
    // nesse caso não há redirect para liberar mesmo.
  }

  res.setHeader('Content-Security-Policy', [
    "default-src 'self'",
    "base-uri 'self'",
    "img-src 'self' data:",
    "style-src 'self' 'unsafe-inline'",
    `script-src 'nonce-${nonce}'`,
    "object-src 'none'",
    "frame-ancestors 'self'",
    `form-action ${formAction.join(' ')}`,
  ].join('; '));

  return res.status(status).type('html').send(renderAuthorizePage({ client, params, error, nonce }));
}

/** client_id/redirect_uri inválidos não podem confiar num redirect — só uma página estática nossa. */
async function resolveClientOrError(req, res, redirectUri) {
  const client = await findClient(req.query.client_id ?? req.body?.client_id);
  if (!client || !redirectUri || !isRegisteredRedirect(client, redirectUri)) {
    res.status(400).type('html').send(renderErrorPage(
      'Este aplicativo não está registrado ou a URL de retorno não confere com o cadastro. '
      + 'Peça para reconectar o app ao MCP da Hope.',
    ));
    return null;
  }
  return client;
}

router.post('/register', async (req, res) => {
  try {
    const body = req.body ?? {};
    const client = await registerClient({ clientName: body.client_name, redirectUris: body.redirect_uris });
    res.status(201).json({
      client_id: client.id,
      client_name: client.clientName,
      redirect_uris: client.redirectUris,
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code'],
      response_types: ['code'],
    });
  } catch (err) {
    if (err instanceof OAuthError) {
      return res.status(err.status).json({ error: err.error, error_description: err.description });
    }
    throw err;
  }
});

router.get('/authorize', async (req, res) => {
  const q = req.query;
  const client = await resolveClientOrError(req, res, q.redirect_uri);
  if (!client) return;

  const params = {
    responseType: q.response_type, clientId: q.client_id, redirectUri: q.redirect_uri,
    codeChallenge: q.code_challenge, codeChallengeMethod: q.code_challenge_method,
    state: q.state, scope: q.scope, resource: q.resource,
  };

  if (q.response_type !== 'code') {
    return redirectWithError(res, q.redirect_uri, q.state, 'unsupported_response_type', 'Somente response_type=code é suportado');
  }
  if (!q.code_challenge || q.code_challenge_method !== 'S256') {
    return redirectWithError(res, q.redirect_uri, q.state, 'invalid_request', 'PKCE (code_challenge com code_challenge_method=S256) é obrigatório');
  }

  sendAuthorizePage(res, { client, params });
});

router.post('/authorize', async (req, res) => {
  const b = req.body ?? {};
  const client = await resolveClientOrError(req, res, b.redirect_uri);
  if (!client) return;

  const params = {
    responseType: b.response_type, clientId: b.client_id, redirectUri: b.redirect_uri,
    codeChallenge: b.code_challenge, codeChallengeMethod: b.code_challenge_method,
    state: b.state, scope: b.scope, resource: b.resource,
  };

  if (b.response_type !== 'code') {
    return redirectWithError(res, b.redirect_uri, b.state, 'unsupported_response_type', 'Somente response_type=code é suportado');
  }
  if (!b.code_challenge || b.code_challenge_method !== 'S256') {
    return redirectWithError(res, b.redirect_uri, b.state, 'invalid_request', 'PKCE (code_challenge com code_challenge_method=S256) é obrigatório');
  }

  const kind = b.kind === 'mcp_write' ? 'mcp_write' : 'mcp_read';

  const user = await verifyLogin(b.email, b.password);
  if (!user) {
    return sendAuthorizePage(res, { client, params, error: 'E-mail ou senha inválidos.', status: 401 });
  }

  const code = await issueAuthorizationCode({
    clientId: client.id,
    redirectUri: b.redirect_uri,
    userId: user.id,
    kind,
    codeChallenge: b.code_challenge,
    codeChallengeMethod: b.code_challenge_method,
    resource: b.resource,
  });

  const url = new URL(b.redirect_uri);
  url.searchParams.set('code', code);
  if (b.state) url.searchParams.set('state', b.state);
  res.redirect(302, url.toString());
});

router.post('/token', async (req, res) => {
  const b = req.body ?? {};
  if (b.grant_type !== 'authorization_code') {
    return res.status(400).json({
      error: 'unsupported_grant_type',
      error_description: 'Somente grant_type=authorization_code é suportado (sem refresh_token nesta versão)',
    });
  }
  try {
    const { pat, kind } = await exchangeAuthorizationCode({
      code: b.code, clientId: b.client_id, redirectUri: b.redirect_uri, codeVerifier: b.code_verifier,
    });
    res.status(200).json({
      access_token: pat.token,
      token_type: 'Bearer',
      scope: kind === 'mcp_write' ? 'read write' : 'read',
    });
  } catch (err) {
    if (err instanceof OAuthError) {
      return res.status(err.status).json({ error: err.error, error_description: err.description });
    }
    throw err;
  }
});

export default router;
