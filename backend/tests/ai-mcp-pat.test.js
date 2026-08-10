import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';

let api;

beforeAll(async () => {
  api = await makeApp();
});

async function createPat(token, kind, overrides = {}) {
  const res = await api.post('/api/v1/pat').set(auth(token))
    .send({ name: `pat-${kind}`, kind, ...overrides });
  expect(res.status).toBe(201);
  return res.body.data;
}

function mcpCall(token, method, params) {
  return api.post('/api/v1/ai/mcp/methods').set(auth(token))
    .send({ jsonrpc: '2.0', id: 1, method, params });
}

describe('Personal Access Tokens — CRUD', () => {
  it('cria, lista (sem expor o token em claro) e revoga um PAT', async () => {
    const user = await registerUser(api);

    const created = await createPat(user.access_token, 'mcp_read');
    expect(created.token).toMatch(/^[0-9a-f]{64}$/);
    expect(created.scopes).toEqual(['read']);

    const list = await api.get('/api/v1/pat').set(auth(user.access_token));
    expect(list.status).toBe(200);
    expect(list.body.data).toHaveLength(1);
    expect(list.body.data[0]).not.toHaveProperty('token');
    expect(list.body.data[0].last4).toMatch(/^\.\.\.[0-9a-f]{4}$/);

    const revoke = await api.delete(`/api/v1/pat/${created.id}`).set(auth(user.access_token));
    expect(revoke.status).toBe(200);

    const afterRevoke = await api.get('/api/v1/pat').set(auth(user.access_token));
    expect(afterRevoke.body.data).toHaveLength(0);

    // Token revogado não autentica mais.
    const blocked = await mcpCall(created.token, 'tools/list');
    expect(blocked.status).toBe(401);
  });
});

describe('MCP — autenticação via PAT', () => {
  it('sem token, /ai/mcp devolve 401 com WWW-Authenticate apontando pro resource_metadata (descoberta OAuth do host — ex.: Grok)', async () => {
    const res = await api.post('/api/v1/ai/mcp/methods')
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list' });
    expect(res.status).toBe(401);
    expect(res.headers['www-authenticate']).toContain('resource_metadata=');
    expect(res.headers['www-authenticate']).toContain('/.well-known/oauth-protected-resource/api/v1/ai/mcp');
  });

  it('fora de /ai/mcp, 401 não leva o WWW-Authenticate de descoberta do MCP', async () => {
    const res = await api.get('/api/v1/accounts');
    expect(res.status).toBe(401);
    expect(res.headers['www-authenticate']).toBeUndefined();
  });

  it('initialize responde o handshake para um PAT mcp_read', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_read');
    const res = await api.post('/api/v1/ai/mcp/initialize').set(auth(pat.token))
      .send({ jsonrpc: '2.0', id: 1, method: 'initialize' });
    expect(res.status).toBe(200);
    expect(res.body.result.serverInfo.name).toBe('hopecash-mcp');
  });

  it('/methods também responde initialize — hosts reais (transporte HTTP "Streamable") usam uma única URL para a sessão inteira', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_read');
    const res = await mcpCall(pat.token, 'initialize');
    expect(res.status).toBe(200);
    expect(res.body.result.serverInfo.name).toBe('hopecash-mcp');
  });

  it('notificação JSON-RPC (sem "id") em /methods recebe 202 sem corpo, não um erro', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_read');
    const res = await api.post('/api/v1/ai/mcp/methods').set(auth(pat.token))
      .send({ jsonrpc: '2.0', method: 'notifications/initialized' });
    expect(res.status).toBe(202);
    expect(res.body).toEqual({});
  });

  it('PAT push_transactions recebe 403 em qualquer rota MCP (bloqueado já no gate do app.js)', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'push_transactions');
    const res = await mcpCall(pat.token, 'tools/list');
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });

  it('PAT push_transactions também não acessa /api/v1/pat (só POST /transactions)', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'push_transactions');
    const res = await api.get('/api/v1/pat').set(auth(pat.token));
    expect(res.status).toBe(403);
  });

  it('PAT MCP não acessa rotas REST gerais fora de /pat e /ai/*', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_write');
    const res = await api.get('/api/v1/accounts').set(auth(pat.token));
    expect(res.status).toBe(403);
  });

  it('escopo por usuário: PAT de um usuário não enxerga dados de outro', async () => {
    const owner = await registerUser(api);
    await api.post('/api/v1/accounts').set(auth(owner.access_token))
      .send({ name: 'Conta do dono', type: 'checking', initial_balance: 500 });
    const other = await registerUser(api);
    const patOther = await createPat(other.access_token, 'mcp_read');

    const res = await mcpCall(patOther.token, 'tools/call', { name: 'get_balances', arguments: {} });
    const data = JSON.parse(res.body.result.content[0].text);
    expect(data.accounts).toHaveLength(0);
    expect(data.total_balance).toBe(0);
  });

  it('CORS aberto em /api/v1/ai/mcp — hosts (ChatGPT, Grok) testam a conexão via fetch() cross-origin do próprio domínio antes do OAuth', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_read');
    const res = await api.post('/api/v1/ai/mcp/methods').set(auth(pat.token)).set('Origin', 'https://grok.com')
      .send({ jsonrpc: '2.0', id: 1, method: 'initialize' });
    expect(res.status).toBe(200);
    expect(res.headers['access-control-allow-origin']).toBe('https://grok.com');
  });
});

describe('MCP — escrita executa em uma única chamada tools/call', () => {
  // Duas chamadas MCP separadas no tempo (propor, depois confirmar) causaram
  // "Session terminated" com o ChatGPT — a janela entre elas expunha a
  // fragilidade de sessão/conexão do host. Hosts MCP já pedem aprovação do
  // usuário na própria UI deles antes de chamar uma tool de escrita, então
  // não há necessidade de uma segunda confirmação do lado da Hope: a tool
  // executa direto e devolve o resultado final na mesma resposta.
  // O chat interno da Hope (agent.js → callTool, sem passar por mcp.server.js)
  // continua com a confirmação em duas fases via card no app — inalterado,
  // coberto por tests/ai-actions.test.js.

  it('mcp_read não pode escrever (token só leitura)', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_read');
    const res = await mcpCall(pat.token, 'tools/call', {
      name: 'create_transaction',
      arguments: { type: 'expense', description: 'x', amount: 10, date: '2026-08-01' },
    });
    expect(res.body.error.message).toContain('somente leitura');
  });

  it('mcp_write executa create_transaction de ponta a ponta numa chamada só', async () => {
    const user = await registerUser(api);
    const account = await api.post('/api/v1/accounts').set(auth(user.access_token))
      .send({ name: 'Conta', type: 'checking', initial_balance: 0 });
    const pat = await createPat(user.access_token, 'mcp_write');

    const res = await mcpCall(pat.token, 'tools/call', {
      name: 'create_transaction',
      arguments: {
        type: 'expense', description: 'Compra via MCP', amount: 42,
        date: '2026-08-01', account_id: account.body.data.id,
      },
    });
    expect(res.status).toBe(200);
    const action = JSON.parse(res.body.result.content[0].text);
    // Não é mais {proposed:true, action:{status:'proposed'}} — já vem confirmada.
    expect(action.status).toBe('confirmed');
    expect(action.result.id).toBeTruthy();

    const balances = await mcpCall(pat.token, 'tools/call', { name: 'get_balances', arguments: {} });
    const data = JSON.parse(balances.body.result.content[0].text);
    expect(data.total_balance).toBe(-42);
  });

  it('mcp_write executa pay_transaction (dar baixa) de ponta a ponta numa chamada só', async () => {
    const user = await registerUser(api);
    const account = await api.post('/api/v1/accounts').set(auth(user.access_token))
      .send({ name: 'Conta', type: 'checking', initial_balance: 0 });
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Aluguel sogra', amount_planned: 750,
      competence_date: '2026-08-10', due_date: '2026-08-10',
      status: 'planned', account_id: account.body.data.id,
    });
    const pat = await createPat(user.access_token, 'mcp_write');

    const res = await mcpCall(pat.token, 'tools/call', {
      name: 'pay_transaction',
      arguments: { transaction_id: 'Aluguel sogra', date: '2026-08-07' },
    });
    expect(res.status).toBe(200);
    const action = JSON.parse(res.body.result.content[0].text);
    expect(action.status).toBe('confirmed');
    expect(action.result.transaction.status).toBe('paid');

    const balances = await mcpCall(pat.token, 'tools/call', { name: 'get_balances', arguments: {} });
    expect(JSON.parse(balances.body.result.content[0].text).total_balance).toBe(-750);
  });

  it('erro de validação na execução não deixa a ação "pendente" — devolve erro claro na mesma chamada', async () => {
    const user = await registerUser(api);
    const pat = await createPat(user.access_token, 'mcp_write');
    // account_id inexistente: create_transaction tenta pagar de uma conta que não existe.
    const res = await mcpCall(pat.token, 'tools/call', {
      name: 'add_goal_contribution',
      arguments: { goal_id: 'meta-que-nao-existe', amount: 10, date: '2026-08-01' },
    });
    expect(res.status).toBe(404);
    expect(res.body.error).toBeTruthy();
  });
});
