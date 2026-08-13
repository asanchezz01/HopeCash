import { describe, it, expect, beforeAll, vi } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';
import { _setPushProviderForTests } from '../src/modules/push/providers/index.js';
import { FakePushProvider } from '../src/modules/push/providers/fakePushProvider.js';
import { runPushSchedulerTick, startPushScheduler, stopPushScheduler } from '../src/modules/push/scheduler.js';
import { sendCampaignNow } from '../src/modules/push/services/campaignService.js';
import { llm } from '../src/modules/ai/llm.js';

let api;
let fakeProvider;

beforeAll(async () => {
  api = await makeApp();
  fakeProvider = new FakePushProvider();
  _setPushProviderForTests(fakeProvider);
});

async function withDevice(platform = 'android') {
  const user = await registerUser(api);
  const token = `sched-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform });
  return { user, token };
}

describe('Scheduler — ciclo de vida do processo', () => {
  it('inicia e para sem lançar erro (o start real só roda se PUSH_SCHEDULER_ENABLED=true)', () => {
    expect(() => startPushScheduler()).not.toThrow();
    expect(() => stopPushScheduler()).not.toThrow();
  });
});

describe('Scheduler — campanhas agendadas sobrevivem a um "reinício"', () => {
  it('processa uma campanha cuja hora chegou e não a reprocessa em um segundo ciclo', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { token } = await withDevice();

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'Campanha do scheduler', body: 'Corpo', audience: 'all' });
    const id = created.body.data.id;
    // Agenda diretamente no passado (sem passar pela validação de data futura da rota) — simula que a hora já chegou.
    await db('push_campaigns').where({ id }).update({ status: 'scheduled', scheduled_at: '2020-01-01 00:00:00.000' });

    // "Reinício": dois ciclos do worker, como se o processo tivesse caído e voltado no meio do caminho.
    const chat = vi.spyOn(llm, 'chatJson').mockResolvedValue({
      title: 'Dica personalizada do scheduler',
      body: 'Revise uma categoria relevante do seu mês e escolha uma ação simples para esta semana.',
    });
    await runPushSchedulerTick();
    await runPushSchedulerTick();
    chat.mockRestore();

    const campaign = await db('push_campaigns').where({ id }).first();
    expect(['sent', 'partially_sent']).toContain(campaign.status);

    const messagesForThisCampaign = fakeProvider.sent.filter((m) => m.token === token && m.title === 'Campanha do scheduler');
    expect(messagesForThisCampaign.length).toBe(1); // não duplicou entre os dois ciclos
  });
});

describe('Scheduler — claim otimista evita processamento duplicado de campanhas', () => {
  it('duas chamadas concorrentes de "enviar agora" só processam a campanha uma vez', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { token } = await withDevice();

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'Campanha concorrente', body: 'Corpo', audience: 'all' });
    const id = created.body.data.id;

    const results = await Promise.allSettled([sendCampaignNow(id), sendCampaignNow(id)]);
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');
    expect(fulfilled.length).toBe(1);
    expect(rejected.length).toBe(1);

    const messages = fakeProvider.sent.filter((m) => m.token === token && m.title === 'Campanha concorrente');
    expect(messages.length).toBe(1);
  });
});
