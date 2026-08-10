import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';

let api;
beforeAll(async () => { api = await makeApp(); });

describe('Tutorial de boas-vindas (por usuário, no servidor)', () => {
  it('nasce pendente, é marcado uma vez e persiste entre logins', async () => {
    const user = await registerUser(api);
    expect(user.user.onboarding_completed_at ?? null).toBeNull();

    const before = await api.get('/api/v1/users/me').set(auth(user.access_token));
    expect(before.status).toBe(200);
    expect(before.body.data.onboarding_completed_at).toBeNull();

    const mark = await api.put('/api/v1/users/me/onboarding').set(auth(user.access_token));
    expect(mark.status).toBe(200);
    const completedAt = mark.body.data.onboarding_completed_at;
    expect(completedAt).toBeTruthy();

    // Idempotente: nova chamada preserva a data da primeira conclusão.
    const again = await api.put('/api/v1/users/me/onboarding').set(auth(user.access_token));
    expect(again.status).toBe(200);
    expect(again.body.data.onboarding_completed_at).toBe(completedAt);

    // "Novo dispositivo": login devolve a marca para o app não reabrir o tutorial.
    const login = await api.post('/api/v1/auth/login').send({
      email: user.email,
      password: 'Senha123!',
    });
    expect(login.status).toBe(200);
    expect(login.body.data.user.onboarding_completed_at).toBe(completedAt);
  });
});
