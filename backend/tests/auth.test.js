import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';
import { db } from '../src/db/knex.js';
import { sha256 } from '../src/utils/password.js';

let api;
beforeAll(async () => { api = await makeApp(); });

describe('Autenticação', () => {
  it('registra, faz login e acessa o perfil', async () => {
    const { email } = await registerUser(api);

    const login = await api.post('/api/v1/auth/login').send({ email, password: 'Senha123!' });
    expect(login.status).toBe(200);
    expect(login.body.data.access_token).toBeTruthy();
    expect(login.body.data.refresh_token).toBeTruthy();

    const me = await api.get('/api/v1/users/me').set(auth(login.body.data.access_token));
    expect(me.status).toBe(200);
    expect(me.body.data.email).toBe(email);
  });

  it('rejeita senha fraca e e-mail duplicado', async () => {
    const weak = await api.post('/api/v1/auth/register').send({
      name: 'X Y', email: 'weak@test.dev', password: 'abc',
    });
    expect(weak.status).toBe(422);

    const { email } = await registerUser(api);
    const dup = await api.post('/api/v1/auth/register').send({
      name: 'Outro', email, password: 'Senha123!',
    });
    expect(dup.status).toBe(400);
  });

  it('rejeita login com senha errada e acesso sem token', async () => {
    const { email } = await registerUser(api);
    const bad = await api.post('/api/v1/auth/login').send({ email, password: 'Errada123' });
    expect(bad.status).toBe(401);

    const noToken = await api.get('/api/v1/users/me');
    expect(noToken.status).toBe(401);
  });

  it('rotaciona o refresh token e invalida o antigo', async () => {
    const user = await registerUser(api);

    const first = await api.post('/api/v1/auth/refresh').send({ refresh_token: user.refresh_token });
    expect(first.status).toBe(200);
    const newRefresh = first.body.data.refresh_token;
    expect(newRefresh).not.toBe(user.refresh_token);

    // Reuso do token antigo deve falhar (e derrubar as sessões).
    const reuse = await api.post('/api/v1/auth/refresh').send({ refresh_token: user.refresh_token });
    expect(reuse.status).toBe(401);
  });

  it('atualiza dados de login com senha atual', async () => {
    const user = await registerUser(api);

    const updated = await api.put('/api/v1/users/me/login')
      .set(auth(user.access_token))
      .send({
        name: 'Usuário Atualizado',
        email: `updated-${Date.now()}@test.dev`,
        current_password: 'Senha123!',
      });

    expect(updated.status).toBe(200);
    expect(updated.body.data.name).toBe('Usuário Atualizado');
    expect(updated.body.data.email).toContain('updated-');

    const bad = await api.put('/api/v1/users/me/login')
      .set(auth(user.access_token))
      .send({
        name: 'Outro Nome',
        email: 'outro@test.dev',
        current_password: 'SenhaErrada123',
      });
    expect(bad.status).toBe(401);
  });

  it('troca senha e revoga refresh tokens', async () => {
    const user = await registerUser(api);

    const changed = await api.put('/api/v1/users/me/password')
      .set(auth(user.access_token))
      .send({ current_password: 'Senha123!', password: 'NovaSenha123!' });
    expect(changed.status).toBe(200);

    const oldLogin = await api.post('/api/v1/auth/login')
      .send({ email: user.email, password: 'Senha123!' });
    expect(oldLogin.status).toBe(401);

    const newLogin = await api.post('/api/v1/auth/login')
      .send({ email: user.email, password: 'NovaSenha123!' });
    expect(newLogin.status).toBe(200);

    const refresh = await api.post('/api/v1/auth/refresh')
      .send({ refresh_token: user.refresh_token });
    expect(refresh.status).toBe(401);
  });

  it('recupera senha com token de recuperação', async () => {
    const user = await registerUser(api);

    const requested = await api.post('/api/v1/auth/forgot-password')
      .send({ email: user.email });
    expect(requested.status).toBe(200);
    expect(requested.body.data.message).toBe('Se o e-mail existir, enviaremos instruções de recuperação.');

    const row = await db('users')
      .where({ email: user.email })
      .first('password_reset_token', 'password_reset_expires_at');
    expect(row.password_reset_token).toBeTruthy();
    expect(row.password_reset_expires_at).toBeTruthy();

    const token = 'reset-token-test';
    const expiresAt = new Date(Date.now() + 3600_000).toISOString().slice(0, 23).replace('T', ' ');
    await db('users').where({ email: user.email }).update({
      password_reset_token: sha256(token),
      password_reset_expires_at: expiresAt,
    });

    const reset = await api.post('/api/v1/auth/reset-password')
      .send({ token, password: 'NovaSenha123!' });
    expect(reset.status).toBe(200);
    expect(reset.body.data.message).toBe('Senha redefinida com sucesso.');

    const oldLogin = await api.post('/api/v1/auth/login')
      .send({ email: user.email, password: 'Senha123!' });
    expect(oldLogin.status).toBe(401);

    const newLogin = await api.post('/api/v1/auth/login')
      .send({ email: user.email, password: 'NovaSenha123!' });
    expect(newLogin.status).toBe(200);

    const unknown = await api.post('/api/v1/auth/forgot-password')
      .send({ email: `nao-existe-${Date.now()}@test.dev` });
    expect(unknown.status).toBe(200);
    expect(unknown.body.data.message).toBe(requested.body.data.message);
  });
});
