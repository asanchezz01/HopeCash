import crypto from 'node:crypto';
import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';

let api;
let token;

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;
});

const pushOps = (operations) =>
  api.post('/api/v1/sync/push').set(auth(token)).send({ device_id: 'test-device', operations });

describe('Sincronização offline-first', () => {
  it('push cria registro offline e pull o devolve', async () => {
    const entityId = crypto.randomUUID();
    const opId = crypto.randomUUID();

    const push = await pushOps([{
      operation_id: opId,
      entity: 'bank_accounts',
      entity_id: entityId,
      op: 'create',
      payload: { name: 'Conta criada offline', type: 'wallet', initial_balance: 50 },
    }]);
    expect(push.status).toBe(200);
    expect(push.body.data.results[0].result).toBe('applied');
    expect(push.body.data.results[0].record.version).toBe(1);

    // Reenvio da mesma operação é idempotente.
    const replay = await pushOps([{
      operation_id: opId,
      entity: 'bank_accounts',
      entity_id: entityId,
      op: 'create',
      payload: { name: 'Conta criada offline', type: 'wallet' },
    }]);
    expect(replay.body.data.results[0].result).toBe('duplicate');

    const pull = await api.get('/api/v1/sync/pull?since=0').set(auth(token));
    expect(pull.status).toBe(200);
    expect(pull.body.data.cursor).toBeTruthy();
    const accounts = pull.body.data.entities.bank_accounts;
    expect(accounts.some((a) => a.id === entityId)).toBe(true);
  });

  it('resolve conflito por last-write-wins preservando a versão perdedora', async () => {
    const entityId = crypto.randomUUID();
    await pushOps([{
      operation_id: crypto.randomUUID(),
      entity: 'goals',
      entity_id: entityId,
      op: 'create',
      payload: { name: 'Meta original', target_amount: 1000 },
    }]);

    // Edição direta no servidor (outro dispositivo) → version 2.
    const serverEdit = await api.put(`/api/v1/goals/${entityId}`).set(auth(token))
      .send({ name: 'Editada no servidor' });
    expect(serverEdit.body.data.version).toBe(2);

    // Cliente offline edita com base na version 1 e um carimbo futuro (vence o LWW).
    const future = new Date(Date.now() + 60_000).toISOString().slice(0, 23).replace('T', ' ');
    const conflictPush = await pushOps([{
      operation_id: crypto.randomUUID(),
      entity: 'goals',
      entity_id: entityId,
      op: 'update',
      payload: { name: 'Editada offline' },
      base_version: 1,
      client_updated_at: future,
    }]);
    const result = conflictPush.body.data.results[0];
    expect(result.result).toBe('conflict_resolved');
    expect(result.record.name).toBe('Editada offline');
    expect(result.record.version).toBe(3);
  });

  it('sincroniza exclusões como tombstones no pull', async () => {
    const entityId = crypto.randomUUID();
    await pushOps([{
      operation_id: crypto.randomUUID(),
      entity: 'categories',
      entity_id: entityId,
      op: 'create',
      payload: { name: 'Temporária', type: 'expense' },
    }]);
    const before = await api.get('/api/v1/sync/pull?since=0&entities=categories').set(auth(token));
    const cursor = before.body.data.cursor;

    await pushOps([{
      operation_id: crypto.randomUUID(),
      entity: 'categories',
      entity_id: entityId,
      op: 'delete',
    }]);

    const after = await api.get(`/api/v1/sync/pull?since=${encodeURIComponent(cursor)}&entities=categories`)
      .set(auth(token));
    const tombstone = after.body.data.entities.categories.find((c) => c.id === entityId);
    expect(tombstone).toBeTruthy();
    expect(tombstone.deleted_at).toBeTruthy();
  });

  it('rejeita operação em registro de outro usuário', async () => {
    const other = await registerUser(api);
    const acc = await api.post('/api/v1/accounts').set(auth(other.access_token))
      .send({ name: 'Conta alheia', type: 'checking' });

    const push = await pushOps([{
      operation_id: crypto.randomUUID(),
      entity: 'bank_accounts',
      entity_id: acc.body.data.id,
      op: 'update',
      payload: { name: 'Invasão' },
      base_version: 1,
    }]);
    expect(push.body.data.results[0].result).toBe('rejected');
  });
});
