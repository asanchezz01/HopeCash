import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { makeApp, registerUser, loginSuperuser, auth } from './helpers.js';
import { _setPushProviderForTests } from '../src/modules/push/providers/index.js';
import { FakePushProvider } from '../src/modules/push/providers/fakePushProvider.js';

let api;
let fakeProvider;

beforeAll(async () => {
  api = await makeApp();
});

async function makeAdmin() {
  const { access_token: superToken } = await loginSuperuser(api);
  const email = `adm-camp-${Date.now()}-${Math.random().toString(36).slice(2)}@test.dev`;
  await api.post('/api/v1/retaguarda/users').set(auth(superToken))
    .send({ name: 'Operador Campanhas', email, password: 'Senha123!', role: 'admin' });
  const login = await api.post('/api/v1/retaguarda/auth/login').send({ email, password: 'Senha123!' });
  return login.body.data.access_token;
}

async function withDevice(platform = 'android') {
  const user = await registerUser(api);
  const token = `campaign-tok-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  await api.post('/api/v1/push/devices').set(auth(user.access_token)).send({ token, platform });
  return { user, token };
}

beforeAll(() => {
  fakeProvider = new FakePushProvider();
  _setPushProviderForTests(fakeProvider);
});

describe('Retaguarda — campanhas de notificação: autorização', () => {
  it('admin pode criar, listar e ver prévia; não pode enviar/agendar/cancelar/reprocessar', async () => {
    const adminToken = await makeAdmin();
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(adminToken))
      .send({ title: 'Oi', body: 'Corpo da mensagem', audience: 'all' });
    expect(created.status).toBe(201);
    const id = created.body.data.id;

    const list = await api.get('/api/v1/retaguarda/notifications').set(auth(adminToken));
    expect(list.status).toBe(200);

    const preview = await api.get(`/api/v1/retaguarda/notifications/${id}/preview`).set(auth(adminToken));
    expect(preview.status).toBe(200);

    const send = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(adminToken));
    expect(send.status).toBe(403);

    const schedule = await api.post(`/api/v1/retaguarda/notifications/${id}/schedule`).set(auth(adminToken))
      .send({ date: '2099-01-01', time: '10:00', timezone: 'America/Sao_Paulo' });
    expect(schedule.status).toBe(403);

    const cancel = await api.post(`/api/v1/retaguarda/notifications/${id}/cancel`).set(auth(adminToken));
    expect(cancel.status).toBe(403);
  });

  it('exige autenticação de retaguarda', async () => {
    const res = await api.get('/api/v1/retaguarda/notifications');
    expect(res.status).toBe(401);
  });
});

describe('Retaguarda — campanhas de notificação: ciclo de vida', () => {
  it('cria rascunho, edita, envia imediatamente e reflete nas estatísticas', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice('android');

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Dica financeira', body: 'Economize revisando assinaturas', category: 'tips', audience: 'all',
    });
    expect(created.status).toBe(201);
    expect(created.body.data.status).toBe('draft');
    const id = created.body.data.id;

    const edited = await api.put(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken))
      .send({ title: 'Dica financeira revisada' });
    expect(edited.status).toBe(200);
    expect(edited.body.data.title).toBe('Dica financeira revisada');

    const preview = await api.get(`/api/v1/retaguarda/notifications/${id}/preview`).set(auth(superToken));
    expect(preview.body.data.recipients_total).toBeGreaterThanOrEqual(1);

    const sent = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    expect(sent.status).toBe(200);
    expect(['sent', 'partially_sent']).toContain(sent.body.data.status);
    expect(sent.body.data.success_total).toBeGreaterThanOrEqual(1);

    expect(fakeProvider.sent.some((m) => m.token === token && m.title === 'Dica financeira revisada')).toBe(true);

    const stats = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(stats.status).toBe(200);
    expect(stats.body.data.counters.sent).toBeGreaterThanOrEqual(1);

    // Já enviada — não pode mais editar/enviar de novo.
    const editAfterSend = await api.put(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken)).send({ title: 'X' });
    expect(editAfterSend.status).toBe(400);
    const sendAgain = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    expect(sendAgain.status).toBe(400);

    await db('users').where({ id: user.user.id }).update({ status: 'active' }); // sanity: não afeta outros testes
  });

  it('agenda e cancela uma campanha', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'Campanha agendada', body: 'Corpo', audience: 'all' });
    const id = created.body.data.id;

    const badSchedule = await api.post(`/api/v1/retaguarda/notifications/${id}/schedule`).set(auth(superToken))
      .send({ date: '2020-01-01', time: '10:00', timezone: 'America/Sao_Paulo' });
    expect(badSchedule.status).toBe(400); // data no passado

    const scheduled = await api.post(`/api/v1/retaguarda/notifications/${id}/schedule`).set(auth(superToken))
      .send({ date: '2099-01-01', time: '10:00', timezone: 'America/Sao_Paulo' });
    expect(scheduled.status).toBe(200);
    expect(scheduled.body.data.status).toBe('scheduled');
    expect(scheduled.body.data.scheduled_at).toBeTruthy();

    const canceled = await api.post(`/api/v1/retaguarda/notifications/${id}/cancel`).set(auth(superToken));
    expect(canceled.status).toBe(200);
    expect(canceled.body.data.status).toBe('canceled');

    // Cancelada — não pode mais reagendar.
    const rescheduled = await api.post(`/api/v1/retaguarda/notifications/${id}/schedule`).set(auth(superToken))
      .send({ date: '2099-01-01', time: '10:00', timezone: 'America/Sao_Paulo' });
    expect(rescheduled.status).toBe(400);
  });

  it('envia somente para os usuários selecionados quando audience=selected', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const targetA = await withDevice('web');
    const targetB = await withDevice('web');
    await withDevice('web'); // não incluído — não deve receber

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Só para você', body: 'Mensagem direcionada', audience: 'selected',
      target_user_ids: [targetA.user.user.id, targetB.user.user.id],
    });
    expect(created.status).toBe(201);
    const id = created.body.data.id;

    const preview = await api.get(`/api/v1/retaguarda/notifications/${id}/preview`).set(auth(superToken));
    expect(preview.body.data.recipients_total).toBe(2);

    const recipientsBeforeSend = await api
      .get(`/api/v1/retaguarda/notifications/${id}/recipients`)
      .set(auth(superToken));
    expect(recipientsBeforeSend.status).toBe(200);
    expect(recipientsBeforeSend.body.meta).toMatchObject({
      total: 2, source: 'current_eligibility',
    });
    expect(recipientsBeforeSend.body.data.map((recipient) => recipient.id))
      .toEqual(expect.arrayContaining([targetA.user.user.id, targetB.user.user.id]));
    expect(recipientsBeforeSend.body.data.every((recipient) => typeof recipient.name === 'string')).toBe(true);

    await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    const tokensSent = fakeProvider.sent.filter((m) => m.title === 'Só para você').map((m) => m.token);
    expect(tokensSent).toContain(targetA.token);
    expect(tokensSent).toContain(targetB.token);

    const recipientsAfterSend = await api
      .get(`/api/v1/retaguarda/notifications/${id}/recipients?page=1&limit=1`)
      .set(auth(superToken));
    expect(recipientsAfterSend.body.meta).toMatchObject({
      total: 2, page: 1, limit: 1, source: 'delivery_history',
    });
    expect(recipientsAfterSend.body.data).toHaveLength(1);
  });

  it('rejeita audience=selected sem usuários informados', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const res = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'X', body: 'Y', audience: 'selected' });
    expect(res.status).toBe(400);
  });

  it('rejeita deep link fora da lista de permissão', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const res = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'X', body: 'Y', deep_link: 'https://evil.example.com' });
    expect(res.status).toBe(400);
  });

  it('respeita o opt-out de push nas campanhas', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const { user, token } = await withDevice('ios');
    await api.put('/api/v1/push/preferences').set(auth(user.access_token)).send({ push_enabled: false });

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Respeita opt-out', body: 'Corpo', audience: 'selected', target_user_ids: [user.user.id],
    });
    const preview = await api.get(`/api/v1/retaguarda/notifications/${created.body.data.id}/preview`).set(auth(superToken));
    expect(preview.body.data.recipients_total).toBe(1); // continua elegível pelo e-mail
    expect(preview.body.data.devices_total).toBe(0);
    expect(preview.body.data.email_fallback_total).toBe(1);

    await api.post(`/api/v1/retaguarda/notifications/${created.body.data.id}/send`).set(auth(superToken));
    expect(fakeProvider.sent.some((m) => m.token === token && m.title === 'Respeita opt-out')).toBe(false);
    const channels = await db('push_deliveries')
      .where({ campaign_id: created.body.data.id, user_id: user.user.id })
      .pluck('channel');
    expect(channels).toEqual(['email']);
  });
});

describe('Retaguarda — campanhas: falhas e reprocessamento', () => {
  it('desativa dispositivo em falha permanente e reprocessa falhas temporárias', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const permanentTarget = await withDevice('android');
    const temporaryTarget = await withDevice('android');

    fakeProvider.setBehavior(permanentTarget.token, 'permanent');
    fakeProvider.setBehavior(temporaryTarget.token, 'temporary');

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Teste de falhas', body: 'Corpo', audience: 'selected',
      target_user_ids: [permanentTarget.user.user.id, temporaryTarget.user.user.id],
    });
    const id = created.body.data.id;
    const sent = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    expect(sent.status).toBe(200);

    const permanentDevice = await db('push_devices').where({ token: permanentTarget.token }).first();
    expect(permanentDevice.is_active).toBeFalsy();

    // Falha permanente já é definitiva (failed); a temporária fica pendente aguardando novo retry (backoff).
    const stats = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(stats.body.data.counters.failed).toBeGreaterThanOrEqual(1);
    expect(stats.body.data.counters.pending).toBeGreaterThanOrEqual(1);

    // Simula o esgotamento das tentativas da falha temporária (o teste não espera o backoff real).
    await db('push_deliveries')
      .where({ campaign_id: id, user_id: temporaryTarget.user.user.id })
      .where({ channel: 'push' })
      .update({ status: 'failed', error: 'Tentativas esgotadas (simulado em teste)' });
    const statsExhausted = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(statsExhausted.body.data.counters.failed).toBeGreaterThanOrEqual(2);

    // Corrige o comportamento simulado e reprocessa — só a falha temporária deve ser reenviada.
    fakeProvider.setBehavior(temporaryTarget.token, 'ok');
    const reprocessed = await api.post(`/api/v1/retaguarda/notifications/${id}/reprocess`).set(auth(superToken));
    expect(reprocessed.status).toBe(200);
    expect(reprocessed.body.data.reset).toBe(1); // só o dispositivo ainda ativo é reprocessado

    const statsAfter = await api.get(`/api/v1/retaguarda/notifications/${id}/stats`).set(auth(superToken));
    expect(statsAfter.body.data.counters.sent).toBeGreaterThanOrEqual(1);
  });
});

describe('Retaguarda — campanhas: excluir e reenviar', () => {
  it('admin não pode excluir/reenviar; superuser pode excluir um rascunho', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const adminToken = await makeAdmin();
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'Para excluir', body: 'Corpo', audience: 'all' });
    const id = created.body.data.id;

    const deleteAsAdmin = await api.delete(`/api/v1/retaguarda/notifications/${id}`).set(auth(adminToken));
    expect(deleteAsAdmin.status).toBe(403);
    const resendAsAdmin = await api.post(`/api/v1/retaguarda/notifications/${id}/resend`).set(auth(adminToken));
    expect(resendAsAdmin.status).toBe(403);

    const deleted = await api.delete(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken));
    expect(deleted.status).toBe(200);
    expect(deleted.body.data.ok).toBe(true);

    const getAfterDelete = await api.get(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken));
    expect(getAfterDelete.status).toBe(404);
  });

  it('exclui uma campanha já enviada e remove o histórico de entregas', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    await withDevice('android');
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Enviada para excluir', body: 'Corpo', audience: 'all',
    });
    const id = created.body.data.id;
    await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    const deliveriesBefore = await db('push_deliveries').where({ campaign_id: id }).count({ n: '*' }).first();
    expect(Number(deliveriesBefore.n)).toBeGreaterThanOrEqual(1);

    const deleted = await api.delete(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken));
    expect(deleted.status).toBe(200);

    const remainingDeliveries = await db('push_deliveries').where({ campaign_id: id }).count({ n: '*' }).first();
    expect(Number(remainingDeliveries.n)).toBe(0);
  });

  it('bloqueia a exclusão enquanto a campanha está processando', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken))
      .send({ title: 'Em processamento', body: 'Corpo', audience: 'all' });
    const id = created.body.data.id;
    await db('push_campaigns').where({ id }).update({ status: 'processing' });

    const deleted = await api.delete(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken));
    expect(deleted.status).toBe(400);
  });

  it('reenvia como uma nova campanha, reavaliando destinatários atuais', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const staying = await withDevice('android');
    const optingOut = await withDevice('android');

    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Campanha original', body: 'Corpo', audience: 'selected',
      target_user_ids: [staying.user.user.id, optingOut.user.user.id],
    });
    const id = created.body.data.id;
    const sent = await api.post(`/api/v1/retaguarda/notifications/${id}/send`).set(auth(superToken));
    expect(sent.status).toBe(200);
    expect(fakeProvider.sent.filter((m) => m.title === 'Campanha original').map((m) => m.token))
      .toEqual(expect.arrayContaining([staying.token, optingOut.token]));

    // Usuário desativa push depois do envio original — o reenvio não deve alcançá-lo mais.
    await api.put('/api/v1/push/preferences').set(auth(optingOut.user.access_token)).send({ push_enabled: false });

    const resent = await api.post(`/api/v1/retaguarda/notifications/${id}/resend`).set(auth(superToken));
    expect(resent.status).toBe(201);
    expect(resent.body.data.id).not.toBe(id); // campanha nova, não reaproveita o id original
    expect(['sent', 'partially_sent']).toContain(resent.body.data.status);

    const tokensSentSoFar = fakeProvider.sent
      .filter((m) => m.title === 'Campanha original').map((m) => m.token);
    // staying recebeu duas vezes (original + reenvio); optingOut só a primeira (optou por sair depois).
    expect(tokensSentSoFar.filter((t) => t === staying.token).length).toBe(2);
    expect(tokensSentSoFar.filter((t) => t === optingOut.token).length).toBe(1);

    // A campanha original continua intacta e consultável.
    const original = await api.get(`/api/v1/retaguarda/notifications/${id}`).set(auth(superToken));
    expect(original.status).toBe(200);
  });

  it('reenvia por push, e-mail ou ambos e identifica os canais realizados', async () => {
    const { access_token: superToken } = await loginSuperuser(api);
    const target = await withDevice('android');
    const created = await api.post('/api/v1/retaguarda/notifications').set(auth(superToken)).send({
      title: 'Campanha por modalidade', body: 'Corpo', audience: 'selected',
      target_user_ids: [target.user.user.id],
    });
    await api.post(`/api/v1/retaguarda/notifications/${created.body.data.id}/send`).set(auth(superToken));

    const expectedChannels = {
      push: ['push'],
      email: ['email'],
      both: ['email', 'push'],
    };
    const resentIds = [];
    for (const channel of ['push', 'email', 'both']) {
      const resent = await api.post(`/api/v1/retaguarda/notifications/${created.body.data.id}/resend`)
        .set(auth(superToken)).send({ channel });
      expect(resent.status).toBe(201);
      expect(resent.body.data.delivery_mode).toBe(channel);
      expect(resent.body.data.delivery_summary.push.sent).toBe(channel === 'email' ? 0 : 1);
      expect(resent.body.data.delivery_summary.email.sent).toBe(channel === 'push' ? 0 : 1);
      const channels = await db('push_deliveries').where({ campaign_id: resent.body.data.id }).pluck('channel');
      expect(channels.sort()).toEqual(expectedChannels[channel]);
      resentIds.push(resent.body.data.id);
    }

    const listed = await api.get('/api/v1/retaguarda/notifications?limit=100').set(auth(superToken));
    for (const id of resentIds) {
      const campaign = listed.body.data.find((item) => item.id === id);
      expect(campaign.delivery_mode).not.toBe('none');
      expect(campaign.delivery_summary).toHaveProperty('push');
      expect(campaign.delivery_summary).toHaveProperty('email');
    }
  });
});
