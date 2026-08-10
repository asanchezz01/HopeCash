import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';
import { _setPushProviderForTests, _setEmailNotificationProviderForTests } from '../src/modules/push/providers/index.js';
import { FakePushProvider } from '../src/modules/push/providers/fakePushProvider.js';
import { FakeEmailNotificationProvider } from '../src/modules/push/providers/fakeEmailNotificationProvider.js';
import { processDueReminders, todayInTimezone } from '../src/modules/push/services/dueReminderService.js';
import { processTips } from '../src/modules/push/services/tipService.js';
import { dispatchPendingDeliveries } from '../src/modules/push/services/deliveryService.js';

let api;
let fakePush;
let fakeEmail;

beforeAll(async () => {
  api = await makeApp();
  fakePush = new FakePushProvider();
  fakeEmail = new FakeEmailNotificationProvider();
  _setPushProviderForTests(fakePush);
  _setEmailNotificationProviderForTests(fakeEmail);
});

async function withDevice(platform = 'android') {
  const user = await registerUser(api);
  const token = `email-fb-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform });
  return { user, token };
}

describe('Fallback por e-mail — campanhas', () => {
  it('usuário sem dispositivo push recebe a campanha por e-mail, com layout e assunto corretos', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const user = await registerUser(api); // sem device

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Campanha por e-mail', body: 'Corpo da campanha para quem não tem push',
      audience: 'selected', target_user_ids: [user.user.id],
    });
    expect(created.status).toBe(201);
    const id = created.body.data.id;

    const preview = await api.get(`/api/v1/retaguarda/notifications/${id}/preview`).set(auth(superToken));
    expect(preview.body.data.recipients_total).toBe(1);
    expect(preview.body.data.devices_total).toBe(0);
    expect(preview.body.data.email_fallback_total).toBe(1);

    const sent = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    expect(sent.status).toBe(200);
    expect(sent.body.data.status).toBe('sent');
    expect(sent.body.data.success_total).toBe(1);

    const email = fakeEmail.sent.find((m) => m.to === user.email);
    expect(email).toBeTruthy();
    expect(email.subject).toBe('Campanha por e-mail');
    expect(email.html).toContain('Corpo da campanha para quem não tem push');
    expect(email.html).toContain('HopeCash');
    expect(email.text).toContain('Campanha por e-mail');

    const delivery = await db('push_deliveries').where({ campaign_id: id, user_id: user.user.id }).first();
    expect(delivery.channel).toBe('email');
    expect(delivery.device_id).toBeNull();
    expect(delivery.status).toBe('sent');
  });

  it('usuário com dispositivo push ativo recebe push e e-mail quando ambos estão autorizados', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Push e e-mail', body: 'Corpo', audience: 'selected', target_user_ids: [user.user.id],
    });
    await api.post(`/api/v1/retaguarda/notifications/${created.body.data.id}/send`).set(auth(superToken));

    expect(fakePush.sent.some((m) => m.token === token && m.title === 'Push e e-mail')).toBe(true);
    expect(fakeEmail.sent.some((m) => m.to === user.email && m.subject === 'Push e e-mail')).toBe(true);
  });

  it('usuário sem dispositivo e com e-mail desativado não recebe nada', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const user = await registerUser(api);
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({ email_notifications_enabled: false });

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Sem canal nenhum', body: 'Corpo', audience: 'selected', target_user_ids: [user.user.id],
    });
    const preview = await api.get(`/api/v1/retaguarda/notifications/${created.body.data.id}/preview`).set(auth(superToken));
    expect(preview.body.data.email_fallback_total).toBe(0);

    await api.post(`/api/v1/retaguarda/notifications/${created.body.data.id}/send`).set(auth(superToken));
    expect(fakeEmail.sent.some((m) => m.subject === 'Sem canal nenhum')).toBe(false);

    const delivery = await db('push_deliveries')
      .where({ campaign_id: created.body.data.id, user_id: user.user.id }).first();
    expect(delivery).toBeUndefined();
    const campaign = await db('push_campaigns').where({ id: created.body.data.id }).first();
    expect(campaign.status).toBe('failed');
  });
});

describe('Fallback por e-mail — avisos de vencimento', () => {
  it('envia o aviso de vencimento por e-mail quando não há dispositivo ativo', async () => {
    const user = await registerUser(api);
    const today = todayInTimezone('America/Sao_Paulo');
    await api.post('/api/v1/transactions').set(auth(user.access_token)).send({
      type: 'expense', description: 'Conta a pagar', competence_date: today, due_date: today, status: 'planned',
    });

    await processDueReminders();
    await dispatchPendingDeliveries();

    const email = fakeEmail.sent.find((m) => m.to === user.email);
    expect(email).toBeTruthy();
    expect(email.subject).toBe('Conta vence hoje');
    // Conteúdo automático nunca inclui valores/descrições.
    expect(email.html).not.toMatch(/Conta a pagar/);
  });
});

describe('Fallback por e-mail — dicas da Hope', () => {
  it('envia a dica automática por push e também por e-mail quando ambos estão autorizados', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    const title = `Dica multicanal ${Date.now()}`;
    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({
      title, body: 'Uma dica entregue nos dois canais autorizados.', frequency_days: 30,
    });

    await processTips({
      generatePersonalizedTip: async () => ({
        title, body: 'Uma dica entregue nos dois canais autorizados.',
      }),
    });
    await dispatchPendingDeliveries();

    expect(fakePush.sent.some((message) => message.token === token && message.title === title)).toBe(true);
    expect(fakeEmail.sent.some((message) => message.to === user.email && message.subject === title)).toBe(true);
    const channels = await db('push_deliveries')
      .where({ source_type: 'tip', user_id: user.user.id })
      .pluck('channel');
    expect(channels.sort()).toEqual(['email', 'push']);
  });

  it('não envia a dica por e-mail quando o usuário desativou esse canal', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({
      email_notifications_enabled: false,
    });
    const title = `Dica somente push ${Date.now()}`;
    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({
      title, body: 'Esta dica deve respeitar a preferência de e-mail.', frequency_days: 30,
    });

    await processTips({
      generatePersonalizedTip: async () => ({
        title, body: 'Esta dica deve respeitar a preferência de e-mail.',
      }),
    });
    await dispatchPendingDeliveries();

    expect(fakePush.sent.some((message) => message.token === token && message.title === title)).toBe(true);
    expect(fakeEmail.sent.some((message) => message.to === user.email && message.subject === title)).toBe(false);
  });

  it('envia somente por e-mail quando o push está desligado e o e-mail autorizado', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({
      push_enabled: false,
      email_notifications_enabled: true,
      tips_enabled: true,
    });
    const title = `Dica somente e-mail ${Date.now()}`;
    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({
      title, body: 'Esta dica deve chegar mesmo sem o canal push.', frequency_days: 30,
    });

    await processTips({
      generatePersonalizedTip: async () => ({
        title, body: 'Esta dica deve chegar mesmo sem o canal push.',
      }),
    });
    await dispatchPendingDeliveries();

    expect(fakePush.sent.some((message) => message.token === token && message.title === title)).toBe(false);
    expect(fakeEmail.sent.some((message) => message.to === user.email && message.subject === title)).toBe(true);
  });

  it('envio imediato de dica usa push e e-mail para o usuário selecionado', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    const title = `Dica imediata multicanal ${Date.now()}`;

    const sent = await api.post('/api/v1/retaguarda/automation-rules/tip/send')
      .set(auth(superToken)).send({
        title,
        body: 'Envio imediato nos canais autorizados.',
        user_id: user.user.id,
      });

    expect(sent.status).toBe(200);
    expect(sent.body.data.recipients_total).toBe(1);
    expect(sent.body.data.success_total).toBe(2);
    expect(fakePush.sent.some((message) => message.token === token && message.title === title)).toBe(true);
    expect(fakeEmail.sent.some((message) => message.to === user.email && message.subject === title)).toBe(true);
  });

  it('envia a dica por e-mail e respeita o mesmo intervalo mínimo entre envios', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const user = await registerUser(api);
    await api.put('/api/v1/retaguarda/automation-rules/tip').set(auth(superToken)).send({
      title: 'Dica por e-mail', body: 'Corpo da dica', frequency_days: 30,
    });

    await processTips({
      generatePersonalizedTip: async () => ({
        title: 'Dica por e-mail', body: 'Corpo da dica',
      }),
    });
    await dispatchPendingDeliveries();
    const messages = fakeEmail.sent.filter((m) => m.to === user.email && m.subject === 'Dica por e-mail');
    expect(messages.length).toBe(1);

    await processTips({
      generatePersonalizedTip: async () => ({
        title: 'Dica por e-mail', body: 'Corpo da dica',
      }),
    });
    await dispatchPendingDeliveries();
    const messagesAfter = fakeEmail.sent.filter((m) => m.to === user.email && m.subject === 'Dica por e-mail');
    expect(messagesAfter.length).toBe(1); // não duplicou
  });
});

describe('Fallback por e-mail — retry e reprocessamento', () => {
  it('só marca a campanha como enviada quando todos os canais são confirmados', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice();
    fakeEmail.setBehavior(user.email, 'temporary');
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Confirmação por canal', body: 'Corpo', audience: 'selected',
      target_user_ids: [user.user.id],
    });
    const id = created.body.data.id;
    const firstAttempt = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    expect(firstAttempt.body.data.status).toBe('processing');
    expect(fakePush.sent.some((message) => message.token === token && message.title === 'Confirmação por canal')).toBe(true);

    await db('push_deliveries').where({ campaign_id: id, channel: 'email' })
      .update({ attempts: 5, next_attempt_at: '1970-01-01 00:00:00.000' });
    await dispatchPendingDeliveries();

    const stats = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(stats.body.data.campaign.status).toBe('partially_sent');
    expect(stats.body.data.campaign.delivery_mode).toBe('both');
    expect(stats.body.data.campaign.delivery_summary.push.sent).toBe(1);
    expect(stats.body.data.campaign.delivery_summary.email.failed).toBe(1);
  });

  it('falha temporária de SMTP entra em backoff e pode ser reprocessada', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const user = await registerUser(api);
    fakeEmail.setBehavior(user.email, 'temporary');

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Falha de e-mail', body: 'Corpo', audience: 'selected', target_user_ids: [user.user.id],
    });
    const id = created.body.data.id;
    await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));

    const stats = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(stats.body.data.counters.pending).toBe(1);

    // Simula esgotamento de tentativas para poder reprocessar de imediato.
    await db('push_deliveries').where({ campaign_id: id, user_id: user.user.id })
      .update({ status: 'failed', error: 'Tentativas esgotadas (simulado em teste)' });

    fakeEmail.setBehavior(user.email, 'ok');
    const reprocessed = await api.post(`/api/v1/retaguarda/notifications/${id}/reprocess`).set(auth(superToken));
    expect(reprocessed.status).toBe(200);
    expect(reprocessed.body.data.reset).toBe(1);

    const statsAfter = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(statsAfter.body.data.counters.sent).toBe(1);
  });
});
