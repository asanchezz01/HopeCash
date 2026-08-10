import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth, loginSuperuser } from './helpers.js';
import { db } from '../src/db/knex.js';

let api;

beforeAll(async () => {
  api = await makeApp();
});

async function createPat(token, kind) {
  const res = await api.post('/api/v1/pat').set(auth(token)).send({ name: `host-${kind}`, kind });
  expect(res.status).toBe(201);
  return res.body.data;
}

/** POST /auth/register devolve só os tokens, não o id do usuário. */
async function makeUser() {
  const user = await registerUser(api);
  const row = await db('users').where({ email: user.email }).first();
  return { ...user, id: row.id };
}

function mcpCall(token, body) {
  return api.post('/api/v1/ai/mcp').set(auth(token)).send(body);
}

/**
 * `recordMcpCall` é gravado depois de responder e sem await de propósito (o
 * host não espera o INSERT de auditoria), então o teste precisa esperar a
 * linha aparecer em vez de assumir que já está lá.
 */
async function waitForLogs(userId, expectedCount, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const rows = await db('mcp_logs').where({ user_id: userId }).orderBy('created_at', 'asc');
    if (rows.length >= expectedCount) return rows;
    if (Date.now() > deadline) return rows;
    await new Promise((resolve) => { setTimeout(resolve, 25); });
  }
}

describe('mcp_logs — trilha persistente das chamadas MCP', () => {
  it('registra tools/list com usuário, host e duração', async () => {
    const user = await makeUser();
    const pat = await createPat(user.access_token, 'mcp_read');

    const res = await mcpCall(pat.token, { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    expect(res.status).toBe(200);

    const [log] = await waitForLogs(user.id, 1);
    expect(log.method).toBe('tools/list');
    expect(log.tool_name).toBeNull();
    expect(Boolean(log.ok)).toBe(true);
    expect(log.status_code).toBe(200);
    expect(log.client_name).toBe('host-mcp_read');
    expect(log.pat_kind).toBe('mcp_read');
    expect(log.duration_ms).toBeGreaterThanOrEqual(0);
  });

  it('registra o NOME de uma tool inexistente — o dado que faltava no log do container', async () => {
    const user = await makeUser();
    const pat = await createPat(user.access_token, 'mcp_read');

    const res = await mcpCall(pat.token, {
      jsonrpc: '2.0',
      id: 7,
      method: 'tools/call',
      params: { name: 'search', arguments: { query: 'quanto gastei' } },
    });
    expect(res.status).toBe(404);

    const [log] = await waitForLogs(user.id, 1);
    expect(log.method).toBe('tools/call');
    expect(log.tool_name).toBe('search');
    expect(Boolean(log.ok)).toBe(false);
    expect(log.status_code).toBe(404);
    expect(log.error_code).toBe(-32601);
    expect(log.error_message).toContain('search');
    expect(JSON.parse(log.arguments)).toEqual({ query: 'quanto gastei' });
  });

  it('registra notificações JSON-RPC (202) — é o sinal de sessão reiniciada pelo host', async () => {
    const user = await makeUser();
    const pat = await createPat(user.access_token, 'mcp_read');

    const res = await mcpCall(pat.token, { jsonrpc: '2.0', method: 'notifications/initialized' });
    expect(res.status).toBe(202);

    const [log] = await waitForLogs(user.id, 1);
    expect(log.method).toBe('notifications/initialized');
    expect(log.status_code).toBe(202);
    expect(Boolean(log.ok)).toBe(true);
  });

  it('não registra PAT push_transactions — o gate do app.js barra antes do router MCP', async () => {
    const user = await makeUser();
    const pat = await createPat(user.access_token, 'push_transactions');

    const res = await mcpCall(pat.token, { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');

    // A tabela é a trilha do SERVIDOR MCP: só entra o que chegou nele. Um
    // token sem escopo nenhum de MCP é barrado uma camada antes e não conta
    // como interação MCP (continua no log HTTP normal do container).
    const rows = await waitForLogs(user.id, 1, 300);
    expect(rows).toHaveLength(0);
  });

  it('nunca guarda o RESULTADO da tool, só os argumentos enviados', async () => {
    const user = await makeUser();
    const pat = await createPat(user.access_token, 'mcp_read');

    await mcpCall(pat.token, {
      jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'get_balances', arguments: {} },
    });

    const [log] = await waitForLogs(user.id, 1);
    expect(log.tool_name).toBe('get_balances');
    expect(Object.keys(log)).not.toContain('result');
    expect(log.arguments).toBe('{}');
  });
});

describe('mcp_logs — leitura pela retaguarda', () => {
  it('lista, filtra por erro e agrega por tool', async () => {
    const user = await makeUser();
    const pat = await createPat(user.access_token, 'mcp_read');

    await mcpCall(pat.token, { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    await mcpCall(pat.token, {
      jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'fetch', arguments: {} },
    });
    await waitForLogs(user.id, 2);

    const rtg = await loginSuperuser(api);

    const list = await api.get(`/api/v1/retaguarda/mcp-logs?user_id=${user.id}`).set(auth(rtg.access_token));
    expect(list.status).toBe(200);
    expect(list.body.data).toHaveLength(2);
    expect(list.body.meta.total).toBe(2);
    // O join traz o usuário — atribuir uma chamada a uma conta não exige mais
    // casar hash de token na mão.
    expect(list.body.data[0].user_email).toBe(user.email);

    const onlyErrors = await api
      .get(`/api/v1/retaguarda/mcp-logs?user_id=${user.id}&only_errors=true`)
      .set(auth(rtg.access_token));
    expect(onlyErrors.body.data).toHaveLength(1);
    expect(onlyErrors.body.data[0].tool_name).toBe('fetch');

    const summary = await api.get('/api/v1/retaguarda/mcp-logs/summary').set(auth(rtg.access_token));
    expect(summary.status).toBe(200);
    const fetchRow = summary.body.data.find((r) => r.tool_name === 'fetch');
    expect(fetchRow.errors).toBeGreaterThanOrEqual(1);
  });

  it('exige autenticação de retaguarda', async () => {
    const res = await api.get('/api/v1/retaguarda/mcp-logs');
    expect(res.status).toBe(401);
  });
});
