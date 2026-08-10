import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';

let api;
beforeAll(async () => { api = await makeApp(); });

describe('Retaguarda — autenticação e superusuário', () => {
  it('provisiona o superusuário e faz login', async () => {
    const session = await loginSuperuser(api);
    expect(session.access_token).toBeTruthy();
    expect(session.refresh_token).toBeTruthy();
    expect(session.user.role).toBe('superuser');

    const me = await api.get('/api/v1/retaguarda/users/me').set(auth(session.access_token));
    expect(me.status).toBe(200);
    expect(me.body.data.role).toBe('superuser');
  });

  it('rejeita acesso sem token e com token do app', async () => {
    const noToken = await api.get('/api/v1/retaguarda/users');
    expect(noToken.status).toBe(401);

    // Token de usuário do app não deve valer na retaguarda.
    const appUser = await registerUser(api);
    const crossed = await api.get('/api/v1/retaguarda/users').set(auth(appUser.access_token));
    expect(crossed.status).toBe(401);
  });
});

describe('Retaguarda — gestão de usuários da retaguarda', () => {
  it('cria, lista, atualiza e exclui um usuário da retaguarda', async () => {
    const { access_token } = await loginSuperuser(api);
    const email = `rtg-${Date.now()}@test.dev`;

    const created = await api.post('/api/v1/retaguarda/users')
      .set(auth(access_token))
      .send({ name: 'Operador', email, password: 'Senha123!', role: 'admin' });
    expect(created.status).toBe(201);
    const id = created.body.data.id;
    expect(created.body.data.role).toBe('admin');

    const list = await api.get('/api/v1/retaguarda/users').set(auth(access_token));
    expect(list.status).toBe(200);
    expect(list.body.data.some((u) => u.id === id)).toBe(true);

    const updated = await api.put(`/api/v1/retaguarda/users/${id}`)
      .set(auth(access_token))
      .send({ name: 'Operador Sênior', status: 'blocked' });
    expect(updated.status).toBe(200);
    expect(updated.body.data.name).toBe('Operador Sênior');
    expect(updated.body.data.status).toBe('blocked');

    const deleted = await api.delete(`/api/v1/retaguarda/users/${id}`).set(auth(access_token));
    expect(deleted.status).toBe(200);
  });

  it('o novo operador consegue entrar e trocar a própria senha', async () => {
    const { access_token } = await loginSuperuser(api);
    const email = `op-${Date.now()}@test.dev`;
    await api.post('/api/v1/retaguarda/users')
      .set(auth(access_token))
      .send({ name: 'Operador', email, password: 'Senha123!' });

    const login = await api.post('/api/v1/retaguarda/auth/login').send({ email, password: 'Senha123!' });
    expect(login.status).toBe(200);

    const changed = await api.put('/api/v1/retaguarda/users/me/password')
      .set(auth(login.body.data.access_token))
      .send({ current_password: 'Senha123!', password: 'NovaSenha123!' });
    expect(changed.status).toBe(200);

    const relogin = await api.post('/api/v1/retaguarda/auth/login').send({ email, password: 'NovaSenha123!' });
    expect(relogin.status).toBe(200);
  });

  it('impede que um admin crie um superusuário', async () => {
    const { access_token } = await loginSuperuser(api);
    const email = `adm-${Date.now()}@test.dev`;
    await api.post('/api/v1/retaguarda/users')
      .set(auth(access_token))
      .send({ name: 'Admin', email, password: 'Senha123!', role: 'admin' });
    const adminLogin = await api.post('/api/v1/retaguarda/auth/login').send({ email, password: 'Senha123!' });

    const attempt = await api.post('/api/v1/retaguarda/users')
      .set(auth(adminLogin.body.data.access_token))
      .send({ name: 'Root', email: `root-${Date.now()}@test.dev`, password: 'Senha123!', role: 'superuser' });
    expect(attempt.status).toBe(403);
  });
});

describe('Retaguarda — gestão de usuários do app', () => {
  it('exibe indicadores financeiros e filtra por usuário', async () => {
    const { access_token: retaguardaToken } = await loginSuperuser(api);
    const first = await registerUser(api);
    const second = await registerUser(api);

    const indicatorAccount = await api.post('/api/v1/accounts').set(auth(first.access_token))
      .send({ name: 'Conta do indicador', type: 'checking' });
    await api.post('/api/v1/cards').set(auth(first.access_token))
      .send({ name: 'Cartão do indicador', closing_day: 5, due_day: 12 });
    await api.post('/api/v1/debts').set(auth(first.access_token))
      .send({ name: 'Dívida do indicador', original_amount: 1000, outstanding_balance: 800 });
    await api.post('/api/v1/budgets').set(auth(first.access_token))
      .send({ reference_month: '2026-07-01' });
    await api.post('/api/v1/transactions').set(auth(first.access_token)).send({
      type: 'income', description: 'Receita do indicador', amount: 100,
      competence_date: '2026-07-01', status: 'paid',
      account_id: indicatorAccount.body.data.id,
    });
    await api.post('/api/v1/transactions').set(auth(first.access_token)).send({
      type: 'expense', description: 'Despesa do indicador', amount: 50,
      competence_date: '2026-07-02', status: 'paid',
      account_id: indicatorAccount.body.data.id,
    });
    await api.post('/api/v1/accounts').set(auth(second.access_token))
      .send({ name: 'Conta de outro usuário', type: 'checking' });

    const filtered = await api.get('/api/v1/retaguarda/stats')
      .query({ user_id: first.user.id })
      .set(auth(retaguardaToken));

    expect(filtered.status).toBe(200);
    expect(filtered.body.data).toMatchObject({
      accounts_total: 1,
      credit_cards_total: 1,
      debts_total: 1,
      budgets_total: 1,
      income_transactions_total: 1,
      expense_transactions_total: 1,
    });

    const allUsers = await api.get('/api/v1/retaguarda/stats')
      .set(auth(retaguardaToken));
    expect(allUsers.status).toBe(200);
    expect(allUsers.body.data.accounts_total)
      .toBeGreaterThanOrEqual(filtered.body.data.accounts_total + 1);
  });

  it('lista, bloqueia e reseta a senha de um usuário do app', async () => {
    const { access_token } = await loginSuperuser(api);
    const appUser = await registerUser(api);

    const device = await api.post('/api/v1/push/devices')
      .set(auth(appUser.access_token))
      .send({ token: `retaguarda-push-${appUser.user.id}`, platform: 'android' });
    expect(device.status).toBe(201);

    // Lista com busca pelo e-mail.
    const list = await api.get('/api/v1/retaguarda/app-users')
      .query({ search: appUser.email })
      .set(auth(access_token));
    expect(list.status).toBe(200);
    const listedUser = list.body.data.find((u) => u.email === appUser.email);
    expect(listedUser).toBeTruthy();
    expect(listedUser.has_push_token).toBe(true);
    expect(list.body.meta.total).toBeGreaterThanOrEqual(1);

    // Reset de senha → devolve o código provisório (e-mail desabilitado no teste).
    const reset = await api.post(`/api/v1/retaguarda/app-users/${appUser.user.id}/reset-password`)
      .set(auth(access_token));
    expect(reset.status).toBe(200);
    expect(reset.body.data.email_sent).toBe(false);
    const code = reset.body.data.code;
    expect(code).toBeTruthy();

    // A senha antiga não funciona mais; a provisória sim.
    const oldLogin = await api.post('/api/v1/auth/login').send({ email: appUser.email, password: 'Senha123!' });
    expect(oldLogin.status).toBe(401);
    const newLogin = await api.post('/api/v1/auth/login').send({ email: appUser.email, password: code });
    expect(newLogin.status).toBe(200);

    // Bloqueio impede novo login.
    const blocked = await api.patch(`/api/v1/retaguarda/app-users/${appUser.user.id}/status`)
      .set(auth(access_token))
      .send({ status: 'blocked' });
    expect(blocked.status).toBe(200);
    expect(blocked.body.data.status).toBe('blocked');

    const blockedLogin = await api.post('/api/v1/auth/login').send({ email: appUser.email, password: code });
    expect(blockedLogin.status).toBe(401);
  });
});
