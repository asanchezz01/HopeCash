import crypto from 'node:crypto';
import { describe, it, expect, beforeAll } from 'vitest';
import { db } from '../src/db/knex.js';
import { now } from '../src/utils/time.js';
import { makeApp } from './helpers.js';
import { _setPushProviderForTests } from '../src/modules/push/providers/index.js';
import { FakePushProvider } from '../src/modules/push/providers/fakePushProvider.js';
import { DisabledPushProvider } from '../src/modules/push/providers/disabledPushProvider.js';
import { enqueueDelivery, dispatchPendingDeliveries, nextBackoffDelayMs } from '../src/modules/push/services/deliveryService.js';

let fakeProvider;

beforeAll(async () => {
  await makeApp(); // garante que as migrations já rodaram
  fakeProvider = new FakePushProvider();
  _setPushProviderForTests(fakeProvider);
});

async function makeDevice(behavior = 'ok') {
  const id = crypto.randomUUID();
  const token = `retry-tok-${crypto.randomUUID()}`;
  const ts = now();
  await db('push_devices').insert({
    id, user_id: crypto.randomUUID(), token, platform: 'android', is_active: true, created_at: ts, updated_at: ts,
  });
  fakeProvider.setBehavior(token, behavior);
  return { id, token };
}

describe('Entregas — enfileiramento idempotente', () => {
  it('não duplica ao enfileirar duas vezes com a mesma chave de idempotência', async () => {
    const device = await makeDevice();
    const key = `test:${crypto.randomUUID()}`;
    const first = await enqueueDelivery({
      sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key,
    });
    const second = await enqueueDelivery({
      sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key,
    });
    expect(first).toBeTruthy();
    expect(second).toBeNull();
    const count = await db('push_deliveries').where({ idempotency_key: key }).count({ n: '*' }).first();
    expect(Number(count.n)).toBe(1);
  });
});

describe('Entregas — classificação de erros e retry', () => {
  it('dry-run não conta como entrega confirmada', async () => {
    const device = await makeDevice('ok');
    const key = `dry-run:${device.id}`;
    await enqueueDelivery({
      sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key,
    });
    _setPushProviderForTests(new DisabledPushProvider());
    try {
      await dispatchPendingDeliveries();
      const delivery = await db('push_deliveries').where({ idempotency_key: key }).first();
      expect(delivery.status).toBe('failed');
      expect(delivery.error).toMatch(/dry-run/i);
      const deviceRow = await db('push_devices').where({ id: device.id }).first();
      expect(deviceRow.is_active).toBeTruthy();
    } finally {
      _setPushProviderForTests(fakeProvider);
    }
  });

  it('falha permanente: marca a entrega como failed e desativa o dispositivo', async () => {
    const device = await makeDevice('permanent');
    const key = `perm:${device.id}`;
    await enqueueDelivery({ sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key });
    await dispatchPendingDeliveries();

    const delivery = await db('push_deliveries').where({ idempotency_key: key }).first();
    expect(delivery.status).toBe('failed');
    const deviceRow = await db('push_devices').where({ id: device.id }).first();
    expect(deviceRow.is_active).toBeFalsy();
    expect(deviceRow.revoked_at).toBeTruthy();
  });

  it('falha temporária: agenda nova tentativa com backoff, sem desativar o dispositivo', async () => {
    const device = await makeDevice('temporary');
    const key = `temp:${device.id}`;
    await enqueueDelivery({ sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key });
    await dispatchPendingDeliveries();

    const delivery = await db('push_deliveries').where({ idempotency_key: key }).first();
    expect(delivery.status).toBe('pending');
    expect(delivery.attempts).toBe(1);
    expect(new Date(`${delivery.next_attempt_at.replace(' ', 'T')}Z`).getTime()).toBeGreaterThan(Date.now());

    const deviceRow = await db('push_devices').where({ id: device.id }).first();
    expect(deviceRow.is_active).toBeTruthy();
  });

  it('esgota as tentativas após o limite máximo e desiste (failed) sem desativar o dispositivo', async () => {
    const device = await makeDevice('temporary');
    const key = `exhaust:${device.id}`;
    await enqueueDelivery({ sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key });
    // Simula que já era a última tentativa permitida, pronta agora (evita esperar o backoff real).
    await db('push_deliveries').where({ idempotency_key: key }).update({ attempts: 5, next_attempt_at: now() });
    await dispatchPendingDeliveries();

    const delivery = await db('push_deliveries').where({ idempotency_key: key }).first();
    expect(delivery.status).toBe('failed');
    expect(delivery.attempts).toBe(6);
    expect(delivery.error).toMatch(/esgotadas/i);
    const deviceRow = await db('push_devices').where({ id: device.id }).first();
    expect(deviceRow.is_active).toBeTruthy(); // esgotar retry não é o mesmo que token inválido
  });

  it('não reprocessa uma entrega cujo next_attempt_at ainda está no futuro', async () => {
    const device = await makeDevice('temporary');
    const key = `future:${device.id}`;
    await enqueueDelivery({ sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: device.id, idempotencyKey: key });
    await db('push_deliveries').where({ idempotency_key: key })
      .update({ next_attempt_at: new Date(Date.now() + 3_600_000).toISOString().slice(0, 23).replace('T', ' ') });
    await dispatchPendingDeliveries();
    const delivery = await db('push_deliveries').where({ idempotency_key: key }).first();
    expect(delivery.attempts).toBe(0); // ainda não tentou — respeitou o agendamento futuro
  });
});

describe('nextBackoffDelayMs', () => {
  it('cresce exponencialmente e respeita o teto máximo (com jitter de até 20%)', () => {
    expect(nextBackoffDelayMs(1)).toBeGreaterThanOrEqual(30_000);
    expect(nextBackoffDelayMs(1)).toBeLessThan(30_000 * 1.21);
    expect(nextBackoffDelayMs(10)).toBeLessThanOrEqual(30 * 60_000 * 1.21);
  });
});

describe('Entregas — concorrência entre instâncias do worker', () => {
  it('duas chamadas concorrentes de dispatchPendingDeliveries não processam a mesma entrega duas vezes', async () => {
    const devices = await Promise.all(Array.from({ length: 8 }, () => makeDevice('ok')));
    await Promise.all(devices.map((d, i) => enqueueDelivery({
      sourceType: 'due_reminder', userId: crypto.randomUUID(), deviceId: d.id, idempotencyKey: `concurrent:${d.id}:${i}`,
    })));

    await Promise.all([dispatchPendingDeliveries(), dispatchPendingDeliveries()]);

    for (const d of devices) {
      const sentCount = fakeProvider.sent.filter((m) => m.token === d.token).length;
      expect(sentCount).toBe(1); // nunca enviado duas vezes, mesmo com duas chamadas simultâneas
    }
  });
});
