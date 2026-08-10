import supertest from 'supertest';
import { db } from '../src/db/knex.js';
import { createApp } from '../src/app.js';
import { ensureSuperuser } from '../src/core/bootstrap.js';
import { config } from '../src/config.js';

let migrated = false;

export async function makeApp() {
  if (!migrated) {
    await db.migrate.latest();
    await ensureSuperuser();
    migrated = true;
  }
  return supertest(createApp());
}

/** Faz login como superusuário da retaguarda e devolve os tokens. */
export async function loginSuperuser(api) {
  const res = await api.post('/api/v1/retaguarda/auth/login').send({
    email: config.superuser.email,
    password: config.superuser.password,
  });
  if (res.status !== 200) throw new Error(`login superuser falhou: ${JSON.stringify(res.body)}`);
  return res.body.data;
}

export async function registerUser(api, overrides = {}) {
  const email = overrides.email ?? `user-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.dev`;
  const res = await api.post('/api/v1/auth/register').send({
    name: 'Usuário Teste',
    email,
    password: 'Senha123!',
    ...overrides,
  });
  if (res.status !== 201) throw new Error(`registro falhou: ${JSON.stringify(res.body)}`);
  return { ...res.body.data, email };
}

export const auth = (token) => ({ Authorization: `Bearer ${token}` });

export async function closeDb() {
  await db.destroy();
}
