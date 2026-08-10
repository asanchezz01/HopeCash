import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';

let api;
let owner; // titular que delega
let reader; // recebe acesso somente leitura
let editor; // recebe acesso total

beforeAll(async () => {
  api = await makeApp();
  owner = await registerUser(api, { name: 'Titular' });
  reader = await registerUser(api, { name: 'Leitor' });
  editor = await registerUser(api, { name: 'Editor' });
  // Dado do titular para os delegados enxergarem.
  await api.post('/api/v1/accounts').set(auth(owner.access_token))
    .send({ name: 'Conta do Titular', type: 'checking' });
});

describe('Delegação de acesso', () => {
  it('rejeita e-mail desconhecido e auto-delegação', async () => {
    const unknown = await api.post('/api/v1/delegations').set(auth(owner.access_token))
      .send({ email: 'nao-existe@test.dev', permission: 'read' });
    expect(unknown.status).toBe(404);

    const self = await api.post('/api/v1/delegations').set(auth(owner.access_token))
      .send({ email: owner.email, permission: 'read' });
    expect(self.status).toBe(400);
  });

  it('concede acesso somente leitura e registra o envio do e-mail', async () => {
    const res = await api.post('/api/v1/delegations').set(auth(owner.access_token))
      .send({ email: reader.email, permission: 'read' });
    expect(res.status).toBe(201);
    expect(res.body.data.permission).toBe('read');
    expect(res.body.data.delegate_email).toBe(reader.email);
    expect(res.body.data).toHaveProperty('email_sent'); // e-mail é best-effort

    const dup = await api.post('/api/v1/delegations').set(auth(owner.access_token))
      .send({ email: reader.email, permission: 'full' });
    expect(dup.status).toBe(400); // já existe delegação ativa
  });

  it('delegado vê a conta em /delegations/received e o titular em /delegations', async () => {
    const received = await api.get('/api/v1/delegations/received').set(auth(reader.access_token));
    expect(received.status).toBe(200);
    expect(received.body.data).toHaveLength(1);
    expect(received.body.data[0].owner_email).toBe(owner.email);
    expect(received.body.data[0].permission).toBe('read');

    const granted = await api.get('/api/v1/delegations').set(auth(owner.access_token));
    expect(granted.body.data).toHaveLength(1);
    expect(granted.body.data[0].delegate_email).toBe(reader.email);
  });

  it('act-as dá visão dos dados do titular; leitura bloqueia escrita', async () => {
    const ownerId = (await api.get('/api/v1/delegations/received')
      .set(auth(reader.access_token))).body.data[0].owner_id;

    const actAs = await api.post('/api/v1/delegations/act-as')
      .set(auth(reader.access_token)).send({ owner_user_id: ownerId });
    expect(actAs.status).toBe(200);
    const actingToken = actAs.body.data.access_token;
    expect(actAs.body.data.permission).toBe('read');
    expect(actAs.body.data.owner.email).toBe(owner.email);

    // Leitura funciona: enxerga as contas do titular.
    const accounts = await api.get('/api/v1/accounts').set(auth(actingToken));
    expect(accounts.status).toBe(200);
    expect(accounts.body.data.some((a) => a.name === 'Conta do Titular')).toBe(true);

    // Escrita bloqueada (somente leitura).
    const write = await api.post('/api/v1/accounts').set(auth(actingToken))
      .send({ name: 'Invasora', type: 'checking' });
    expect(write.status).toBe(403);

    // Rotas pessoais do titular são inacessíveis na sessão delegada.
    const password = await api.put('/api/v1/users/me/password').set(auth(actingToken))
      .send({ current_password: 'x', password: 'NovaSenha123' });
    expect(password.status).toBe(403);
    const delegations = await api.get('/api/v1/delegations').set(auth(actingToken));
    expect(delegations.status).toBe(403);
  });

  it('acesso total permite escrita na conta do titular', async () => {
    await api.post('/api/v1/delegations').set(auth(owner.access_token))
      .send({ email: editor.email, permission: 'full' });
    const ownerId = (await api.get('/api/v1/delegations/received')
      .set(auth(editor.access_token))).body.data[0].owner_id;
    const actAs = await api.post('/api/v1/delegations/act-as')
      .set(auth(editor.access_token)).send({ owner_user_id: ownerId });
    const actingToken = actAs.body.data.access_token;
    expect(actAs.body.data.permission).toBe('full');

    const write = await api.post('/api/v1/accounts').set(auth(actingToken))
      .send({ name: 'Conta criada pelo delegado', type: 'savings' });
    expect(write.status).toBe(201);

    // O titular vê o registro criado na conta dele.
    const accounts = await api.get('/api/v1/accounts').set(auth(owner.access_token));
    expect(accounts.body.data.some((a) => a.name === 'Conta criada pelo delegado')).toBe(true);
  });

  it('revogação vale imediatamente, mesmo para token já emitido', async () => {
    const ownerId = (await api.get('/api/v1/delegations/received')
      .set(auth(reader.access_token))).body.data[0].owner_id;
    const actAs = await api.post('/api/v1/delegations/act-as')
      .set(auth(reader.access_token)).send({ owner_user_id: ownerId });
    const actingToken = actAs.body.data.access_token;

    const granted = await api.get('/api/v1/delegations').set(auth(owner.access_token));
    const delegationId = granted.body.data.find((d) => d.delegate_email === reader.email).id;
    const revoke = await api.delete(`/api/v1/delegations/${delegationId}`)
      .set(auth(owner.access_token));
    expect(revoke.status).toBe(200);

    // Token delegado emitido antes da revogação para de funcionar.
    const after = await api.get('/api/v1/accounts').set(auth(actingToken));
    expect(after.status).toBe(401);

    // E um novo act-as é negado.
    const again = await api.post('/api/v1/delegations/act-as')
      .set(auth(reader.access_token)).send({ owner_user_id: ownerId });
    expect(again.status).toBe(403);

    // A conta some da lista de recebidas.
    const received = await api.get('/api/v1/delegations/received').set(auth(reader.access_token));
    expect(received.body.data).toHaveLength(0);
  });

  it('usuário sem delegação não consegue act-as', async () => {
    const res = await api.post('/api/v1/delegations/act-as')
      .set(auth(reader.access_token)).send({ owner_user_id: editor.user.id });
    expect(res.status).toBe(403);
  });
});
