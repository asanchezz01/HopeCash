import crypto from 'node:crypto';
import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';
import { db } from '../src/db/knex.js';

let api;

beforeAll(async () => {
  api = await makeApp();
});

const REDIRECT_URI = 'https://chatgpt.com/connector_platform_oauth_redirect';

function pkcePair() {
  const codeVerifier = crypto.randomBytes(32).toString('hex');
  const codeChallenge = crypto.createHash('sha256').update(codeVerifier).digest('base64url');
  return { codeVerifier, codeChallenge };
}

async function registerClient(overrides = {}) {
  const res = await api.post('/api/v1/oauth/register').send({
    client_name: 'ChatGPT',
    redirect_uris: [REDIRECT_URI],
    ...overrides,
  });
  expect(res.status).toBe(201);
  return res.body;
}

function locationParams(res) {
  const url = new URL(res.headers.location);
  return Object.fromEntries(url.searchParams.entries());
}

describe('OAuth — Dynamic Client Registration', () => {
  it('registra um cliente público e devolve client_id', async () => {
    const client = await registerClient();
    expect(client.client_id).toBeTruthy();
    expect(client.token_endpoint_auth_method).toBe('none');
    expect(client.redirect_uris).toEqual([REDIRECT_URI]);
  });

  it('rejeita redirect_uris ausente ou vazio', async () => {
    const res = await api.post('/api/v1/oauth/register').send({ client_name: 'X', redirect_uris: [] });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('invalid_client_metadata');
  });

  it('rejeita redirect_uri não-https (exceto loopback)', async () => {
    const res = await api.post('/api/v1/oauth/register').send({ redirect_uris: ['http://evil.example/cb'] });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('invalid_client_metadata');
  });
});

describe('OAuth — tela de login (CSP e feedback de submit)', () => {
  async function authorizePage() {
    const client = await registerClient();
    const { codeChallenge } = pkcePair();
    const res = await api.get('/api/v1/oauth/authorize').query({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
    });
    expect(res.status).toBe(200);
    return res;
  }

  it('libera a origem do redirect_uri em form-action — com o "self" do helmet o WebKit engole o redirect pós-login', async () => {
    const res = await authorizePage();
    const csp = res.headers['content-security-policy'];
    const formAction = csp.split(';').map((d) => d.trim()).find((d) => d.startsWith('form-action'));
    expect(formAction).toBe("form-action 'self' https://chatgpt.com");
  });

  it('serve o script de feedback com nonce, e o nonce do CSP casa com o da tag', async () => {
    const res = await authorizePage();
    const nonceFromCsp = res.headers['content-security-policy'].match(/'nonce-([^']+)'/)[1];
    expect(res.text).toContain(`<script nonce="${nonceFromCsp}">`);
    // Sem 'unsafe-inline': o nonce é o que libera este script e nada mais.
    expect(res.headers['content-security-policy']).not.toContain("script-src 'unsafe-inline'");
  });

  it('o nonce muda a cada carregamento da página', async () => {
    const [a, b] = await Promise.all([authorizePage(), authorizePage()]);
    const nonceOf = (res) => res.headers['content-security-policy'].match(/'nonce-([^']+)'/)[1];
    expect(nonceOf(a)).not.toBe(nonceOf(b));
  });

  it('a tela de senha inválida também vem com o CSP correto (é dela que o usuário retenta)', async () => {
    const client = await registerClient();
    const { codeChallenge } = pkcePair();
    const res = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: 'ninguem@test.dev', password: 'errada',
    });
    expect(res.status).toBe(401);
    expect(res.headers['content-security-policy']).toContain('form-action');
    expect(res.text).toContain('<script nonce=');
  });
});

describe('OAuth — /authorize', () => {
  it('página de login exige client_id/redirect_uri registrados — sem isso, nunca redireciona', async () => {
    const client = await registerClient();
    const res = await api.get('/api/v1/oauth/authorize').query({
      response_type: 'code', client_id: client.client_id, redirect_uri: 'https://outro-dominio.example/cb',
      code_challenge: 'x', code_challenge_method: 'S256',
    });
    expect(res.status).toBe(400);
    expect(res.type).toBe('text/html');
  });

  it('client_id inexistente também recebe página de erro, não redirect', async () => {
    const res = await api.get('/api/v1/oauth/authorize').query({
      response_type: 'code', client_id: 'nao-existe', redirect_uri: REDIRECT_URI,
      code_challenge: 'x', code_challenge_method: 'S256',
    });
    expect(res.status).toBe(400);
    expect(res.type).toBe('text/html');
  });

  it('client/redirect_uri válidos, mas sem PKCE S256 → erro redireciona pro client (redirect_uri já é confiável)', async () => {
    const client = await registerClient();
    const res = await api.get('/api/v1/oauth/authorize').query({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge_method: 'plain', state: 'abc123',
    });
    expect(res.status).toBe(302);
    const params = locationParams(res);
    expect(params.error).toBe('invalid_request');
    expect(params.state).toBe('abc123');
  });

  it('parâmetros válidos renderizam a tela de login com o nome do client', async () => {
    const client = await registerClient({ client_name: 'App <script>alert(1)</script>' });
    const { codeChallenge } = pkcePair();
    const res = await api.get('/api/v1/oauth/authorize').query({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
    });
    expect(res.status).toBe(200);
    expect(res.type).toBe('text/html');
    expect(res.text).not.toContain('<script>alert(1)</script>');
    expect(res.text).toContain('App &lt;script&gt;');
  });

  it('senha errada re-renderiza a página com erro, sem redirecionar', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeChallenge } = pkcePair();
    const res = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'senha-errada', kind: 'mcp_read',
    });
    expect(res.status).toBe(401);
    expect(res.type).toBe('text/html');
    expect(res.text).toContain('inválidos');
  });
});

describe('OAuth — reenvio do formulário de login', () => {
  it('um code novo invalida o anterior do mesmo client+usuário', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeVerifier, codeChallenge } = pkcePair();

    const submit = () => api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256', state: 'xyz',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });

    // Exatamente o cenário de 2026-08-07: o mesmo login enviado duas vezes.
    const first = await submit();
    const second = await submit();
    const codeA = locationParams(first).code;
    const codeB = locationParams(second).code;
    expect(codeA).not.toBe(codeB);

    const exchange = (code) => api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: codeVerifier,
    });

    const stale = await exchange(codeA);
    expect(stale.status).toBe(400);
    expect(stale.body.error).toBe('invalid_grant');

    // O último clique — o que o navegador de fato seguiu — continua valendo.
    const fresh = await exchange(codeB);
    expect(fresh.status).toBe(200);
    expect(fresh.body.access_token).toMatch(/^[0-9a-f]{64}$/);
  });

  it('não invalida code de OUTRO usuário no mesmo client', async () => {
    const client = await registerClient();
    const alice = await registerUser(api);
    const bob = await registerUser(api);
    const { codeVerifier, codeChallenge } = pkcePair();

    const submit = (user) => api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });

    const aliceCode = locationParams(await submit(alice)).code;
    await submit(bob);

    const res = await api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code: aliceCode, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: codeVerifier,
    });
    expect(res.status).toBe(200);
  });
});

describe('OAuth — fluxo completo (authorize → code → token → MCP de verdade)', () => {
  it('emite um PAT funcional via authorization_code + PKCE', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeVerifier, codeChallenge } = pkcePair();

    const authRes = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256', state: 'xyz',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });
    expect(authRes.status).toBe(302);
    const { code, state } = locationParams(authRes);
    expect(code).toBeTruthy();
    expect(state).toBe('xyz');

    const tokenRes = await api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: codeVerifier,
    });
    expect(tokenRes.status).toBe(200);
    expect(tokenRes.body.token_type).toBe('Bearer');
    expect(tokenRes.body.scope).toBe('read');
    const accessToken = tokenRes.body.access_token;
    expect(accessToken).toMatch(/^[0-9a-f]{64}$/);

    // O token OAuth funciona de verdade no MCP — mesmo endpoint que Claude Code usa.
    const mcpRes = await api.post('/api/v1/ai/mcp/methods').set(auth(accessToken))
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list' });
    expect(mcpRes.status).toBe(200);
    expect(mcpRes.body.result.tools.length).toBeGreaterThan(0);

    // E aparece na tela "Tokens de API" do usuário (mesma listagem de PAT).
    const list = await api.get('/api/v1/pat').set(auth(user.access_token));
    expect(list.body.data.some((p) => p.name.includes('ChatGPT'))).toBe(true);
  });

  it('kind mcp_write emite token com escopo de escrita', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeVerifier, codeChallenge } = pkcePair();

    const authRes = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'Senha123!', kind: 'mcp_write',
    });
    const { code } = locationParams(authRes);

    const tokenRes = await api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: codeVerifier,
    });
    expect(tokenRes.body.scope).toBe('read write');
  });

  it('code_verifier errado (PKCE) é rejeitado', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeChallenge } = pkcePair();

    const authRes = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });
    const { code } = locationParams(authRes);

    const tokenRes = await api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: 'verificador-errado',
    });
    expect(tokenRes.status).toBe(400);
    expect(tokenRes.body.error).toBe('invalid_grant');
  });

  it('o mesmo code não pode ser trocado duas vezes (replay)', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeVerifier, codeChallenge } = pkcePair();

    const authRes = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });
    const { code } = locationParams(authRes);
    const body = {
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: codeVerifier,
    };

    const first = await api.post('/api/v1/oauth/token').type('form').send(body);
    expect(first.status).toBe(200);

    const second = await api.post('/api/v1/oauth/token').type('form').send(body);
    expect(second.status).toBe(400);
    expect(second.body.error).toBe('invalid_grant');
  });

  it('code expirado é rejeitado', async () => {
    const user = await registerUser(api);
    const client = await registerClient();
    const { codeVerifier, codeChallenge } = pkcePair();

    const authRes = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });
    const { code } = locationParams(authRes);

    await db('oauth_authorization_codes')
      .where({ client_id: client.client_id })
      .update({ expires_at: '2000-01-01 00:00:00.000' });

    const tokenRes = await api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: codeVerifier,
    });
    expect(tokenRes.status).toBe(400);
    expect(tokenRes.body.error).toBe('invalid_grant');
  });

  it('redirect_uri divergente entre /authorize e /token é rejeitada', async () => {
    const user = await registerUser(api);
    const client = await registerClient({ redirect_uris: [REDIRECT_URI, 'https://chatgpt.com/outra'] });
    const { codeVerifier, codeChallenge } = pkcePair();

    const authRes = await api.post('/api/v1/oauth/authorize').type('form').send({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: codeChallenge, code_challenge_method: 'S256',
      email: user.email, password: 'Senha123!', kind: 'mcp_read',
    });
    const { code } = locationParams(authRes);

    const tokenRes = await api.post('/api/v1/oauth/token').type('form').send({
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: 'https://chatgpt.com/outra', code_verifier: codeVerifier,
    });
    expect(tokenRes.status).toBe(400);
    expect(tokenRes.body.error).toBe('invalid_grant');
  });

  it('grant_type diferente de authorization_code (ex.: refresh_token) devolve unsupported_grant_type', async () => {
    const res = await api.post('/api/v1/oauth/token').type('form').send({ grant_type: 'refresh_token', refresh_token: 'x' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('unsupported_grant_type');
  });
});

describe('OAuth — CORS aberto na superfície pública (bug real: ChatGPT levava 500 ao chamar via fetch() cross-origin)', () => {
  it('/.well-known aceita Origin de terceiros e nunca 500', async () => {
    const res = await api.get('/.well-known/oauth-authorization-server').set('Origin', 'https://chatgpt.com');
    expect(res.status).toBe(200);
    expect(res.headers['access-control-allow-origin']).toBe('https://chatgpt.com');
  });

  it('/api/v1/oauth/register aceita Origin de terceiros e nunca 500', async () => {
    const res = await api.post('/api/v1/oauth/register').set('Origin', 'https://chatgpt.com')
      .send({ client_name: 'CORS check', redirect_uris: [REDIRECT_URI] });
    expect(res.status).toBe(201);
    expect(res.headers['access-control-allow-origin']).toBe('https://chatgpt.com');
  });
});

describe('OAuth — metadados de descoberta', () => {
  it('/.well-known/oauth-authorization-server aponta pros endpoints certos', async () => {
    const res = await api.get('/.well-known/oauth-authorization-server');
    expect(res.status).toBe(200);
    expect(res.body.authorization_endpoint).toContain('/api/v1/oauth/authorize');
    expect(res.body.token_endpoint).toContain('/api/v1/oauth/token');
    expect(res.body.registration_endpoint).toContain('/api/v1/oauth/register');
    expect(res.body.code_challenge_methods_supported).toEqual(['S256']);
  });

  it('/.well-known/oauth-protected-resource/api/v1/ai/mcp aponta pro authorization server', async () => {
    const res = await api.get('/.well-known/oauth-protected-resource/api/v1/ai/mcp');
    expect(res.status).toBe(200);
    expect(res.body.resource).toContain('/api/v1/ai/mcp');
    expect(res.body.authorization_servers).toHaveLength(1);
  });
});
