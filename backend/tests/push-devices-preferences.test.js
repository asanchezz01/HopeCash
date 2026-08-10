import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, auth } from './helpers.js';

let api;
beforeAll(async () => { api = await makeApp(); });

describe('Push — registro de dispositivos', () => {
  it('registra um dispositivo e é idempotente pelo mesmo token', async () => {
    const user = await registerUser(api);
    const token = `tok-${Date.now()}-a-${Math.random().toString(36).slice(2)}`;

    const first = await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({
      token, platform: 'android', app_version: '1.0.0', locale: 'pt-BR', timezone: 'America/Sao_Paulo',
    });
    expect(first.status).toBe(201);
    expect(first.body.data.platform).toBe('android');
    const deviceId = first.body.data.id;

    const second = await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({
      token, platform: 'android', app_version: '1.1.0', locale: 'pt-BR', timezone: 'America/Sao_Paulo',
    });
    expect(second.status).toBe(201);
    expect(second.body.data.id).toBe(deviceId); // mesmo token → mesma linha
    expect(second.body.data.app_version).toBe('1.1.0');

    const count = await db('push_devices').where({ token }).count({ n: '*' }).first();
    expect(Number(count.n)).toBe(1);
  });

  it('suporta vários dispositivos por usuário', async () => {
    const user = await registerUser(api);
    await api.post('/api/v1/push/devices').set(auth(user.access_token))
      .send({ token: `tok-${Date.now()}-web`, platform: 'web' });
    await api.post('/api/v1/push/devices').set(auth(user.access_token))
      .send({ token: `tok-${Date.now()}-ios`, platform: 'ios' });

    const list = await api.get('/api/v1/push/devices').set(auth(user.access_token));
    expect(list.status).toBe(200);
    expect(list.body.data.length).toBeGreaterThanOrEqual(2);
  });

  it('isola dispositivos entre usuários — e transfere o vínculo se o mesmo token reaparecer sob outro usuário', async () => {
    const userA = await registerUser(api);
    const userB = await registerUser(api);
    const sharedToken = `tok-${Date.now()}-shared`;

    await api.post('/api/v1/push/devices').set(auth(userA.access_token))
      .send({ token: sharedToken, platform: 'android' });
    let listA = await api.get('/api/v1/push/devices').set(auth(userA.access_token));
    expect(listA.body.data.some((d) => d.platform === 'android')).toBe(true);

    // Mesmo aparelho, agora logado como outro usuário (ex.: troca de conta no mesmo celular).
    await api.post('/api/v1/push/devices').set(auth(userB.access_token))
      .send({ token: sharedToken, platform: 'android' });

    const row = await db('push_devices').where({ token: sharedToken }).first();
    expect(row.user_id).toBe(userB.user.id);

    const totalWithToken = await db('push_devices').where({ token: sharedToken }).count({ n: '*' }).first();
    expect(Number(totalWithToken.n)).toBe(1); // não duplica linha, transfere o vínculo
  });

  it('desativa o token no logout', async () => {
    const user = await registerUser(api);
    const token = `tok-${Date.now()}-logout`;
    await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform: 'web' });

    const deactivate = await api.post('/api/v1/push/devices/deactivate').set(auth(user.access_token)).send({ token });
    expect(deactivate.status).toBe(200);
    expect(deactivate.body.data.ok).toBe(true);

    const row = await db('push_devices').where({ token }).first();
    expect(row.is_active).toBeFalsy();
    expect(row.revoked_at).toBeTruthy();
  });

  it('rejeita plataforma inválida', async () => {
    const user = await registerUser(api);
    const res = await api.post('/api/v1/push/devices').set(auth(user.access_token))
      .send({ token: `tok-${Date.now()}-bad`, platform: 'windows-phone' });
    expect(res.status).toBe(422);
  });

  it('exige autenticação', async () => {
    const res = await api.post('/api/v1/push/devices').send({ token: 'x'.repeat(30), platform: 'web' });
    expect(res.status).toBe(401);
  });
});

describe('Push — preferências', () => {
  it('cria preferências padrão no primeiro acesso e permite atualizar', async () => {
    const user = await registerUser(api);

    const initial = await api.get('/api/v1/push/preferences').set(auth(user.access_token));
    expect(initial.status).toBe(200);
    expect(initial.body.data.push_enabled).toBe(true);
    expect(initial.body.data.due_reminders_enabled).toBe(true);

    const updated = await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({
      due_reminders_enabled: false,
      tips_enabled: false,
      reminder_advance_days: 5,
      preferred_hour: 9,
      timezone: 'America/Manaus',
    });
    expect(updated.status).toBe(200);
    // SQLite (ambiente de teste) devolve boolean como 0/1; MySQL (produção) devolve boolean real.
    expect(!!updated.body.data.due_reminders_enabled).toBe(false);
    expect(updated.body.data.reminder_advance_days).toBe(5);
    expect(updated.body.data.timezone).toBe('America/Manaus');
  });

  it('isola preferências entre usuários', async () => {
    const userA = await registerUser(api);
    const userB = await registerUser(api);
    await api.put('/api/v1/push/preferences').set(auth(userA.access_token)).send({ push_enabled: false });

    const prefsB = await api.get('/api/v1/push/preferences').set(auth(userB.access_token));
    expect(prefsB.body.data.push_enabled).toBe(true); // não afetado pela alteração de A
  });
});

describe('Push — exclusão de conta (LGPD)', () => {
  it('remove dispositivos e preferências ao excluir a conta', async () => {
    const user = await registerUser(api);
    const token = `tok-${Date.now()}-delete`;
    await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform: 'web' });
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({ push_enabled: false });

    const del = await api.delete('/api/v1/users/me').set(auth(user.access_token));
    expect(del.status).toBe(200);

    const device = await db('push_devices').where({ token }).first();
    expect(device).toBeUndefined();
    const prefs = await db('push_preferences').where({ user_id: user.user.id }).first();
    expect(prefs).toBeUndefined();
  });

  it('inclui dispositivos e preferências na exportação LGPD', async () => {
    const user = await registerUser(api);
    const token = `tok-${Date.now()}-export`;
    await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform: 'pwa' });

    const exported = await api.get('/api/v1/users/me/export').set(auth(user.access_token));
    expect(exported.status).toBe(200);
    expect(exported.body.push_devices.some((d) => d.token === token)).toBe(true);
    expect(exported.body.push_preferences).toBeTruthy();
  });
});
