import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';
import { now } from '../../utils/time.js';
import { ENTITIES, ENTITY_NAMES } from '../../core/registry.js';
import { applyScope, deserialize } from '../../core/syncRepo.js';
import {
  needsDestination,
  mergeForDestinationCheck,
  defaultDebitAccount,
} from '../../core/transactionDestination.js';
import { categoryInUse } from '../categories/categories.service.js';

const router = Router();

const pushSchema = z.object({
  device_id: z.string().max(64),
  operations: z.array(z.object({
    operation_id: z.string().max(64),
    entity: z.enum(ENTITY_NAMES),
    entity_id: z.string().uuid(),
    op: z.enum(['create', 'update', 'delete']),
    payload: z.record(z.any()).nullish(),
    base_version: z.number().int().nullish(),
    client_updated_at: z.string().nullish(),
  })).max(500),
});

const serializePayload = (entity, payload) => {
  const out = { ...payload };
  for (const f of ENTITIES[entity].jsonFields ?? []) {
    if (f in out && out[f] != null && typeof out[f] !== 'string') out[f] = JSON.stringify(out[f]);
  }
  // Colunas que o cliente não controla:
  delete out.user_id; delete out.version; delete out.created_at; delete out.updated_at;
  delete out.sync_status;
  return out;
};

/**
 * Um lançamento pago sem conta nem cartão não movimenta saldo (ver
 * `core/transactionDestination.js`). No caminho REST isso vira 400, mas aqui
 * NÃO dá para recusar: a operação chega de um aparelho onde o usuário já viu
 * o lançamento salvo, e devolver "rejected" apagaria o dado dele sem aviso.
 * Versões do app em campo permitem salvar sem forma de pagamento, então o
 * servidor completa com a conta de débito principal — o usuário enxerga a
 * conta escolhida no próximo pull e pode trocar. Só recusa quando não existe
 * conta nenhuma para atribuir, aí não há o que completar.
 *
 * Muta `op.payload` de propósito: é ele que vira a linha logo em seguida.
 */
async function resolveMissingDestination(auth, op, merged) {
  if (op.entity !== 'transactions' || !needsDestination(merged)) return { rejected: false };

  const account = await defaultDebitAccount(auth);
  if (!account) {
    return {
      rejected: true,
      message: 'Lançamento pago sem conta nem cartão, e não há conta de débito '
        + 'ativa para atribuir. Cadastre uma conta e sincronize de novo.',
    };
  }
  op.payload = { ...(op.payload ?? {}), account_id: account.id };
  return { rejected: false };
}

/**
 * Aplica uma operação offline de forma idempotente com resolução de conflito
 * last-write-wins pelo carimbo do cliente. A versão perdedora fica preservada
 * em sync_operations.conflict_payload.
 */
async function applyOperation(auth, deviceId, op) {
  const existingOp = await db('sync_operations').where({ operation_id: op.operation_id }).first();
  if (existingOp) {
    const current = await db(ENTITIES[op.entity].table).where({ id: op.entity_id }).first();
    return { operation_id: op.operation_id, result: 'duplicate', record: deserialize(op.entity, current) };
  }

  const { table } = ENTITIES[op.entity];
  const current = await db(table).where({ id: op.entity_id }).first();
  // Segurança: só opera sobre registros do escopo do usuário.
  if (current && current.user_id !== auth.userId && !auth.familyIds.includes(current.family_id)) {
    return record(auth, deviceId, op, 'rejected', null, 'Fora do escopo do usuário');
  }

  const ts = now();
  let result = 'applied';
  let conflictPayload = null;

  if (op.op === 'delete') {
    if (op.entity === 'categories' && current && !current.deleted_at
      && await categoryInUse(op.entity_id)) {
      return record(auth, deviceId, op, 'rejected', null,
        'Categoria possui lançamentos ou orçamentos e não pode ser excluída');
    }
    if (current && !current.deleted_at) {
      await db(table).where({ id: op.entity_id })
        .update({ deleted_at: ts, updated_at: ts, version: current.version + 1 });
    }
  } else if (!current) {
    // create (ou update de registro que o servidor nunca viu → upsert)
    const destinationFix = await resolveMissingDestination(auth, op, op.payload ?? {});
    if (destinationFix.rejected) {
      return record(auth, deviceId, op, 'rejected', null, destinationFix.message);
    }
    const row = {
      ...serializePayload(op.entity, op.payload ?? {}),
      id: op.entity_id,
      user_id: auth.userId,
      created_at: ts,
      updated_at: ts,
      deleted_at: null,
      version: 1,
    };
    await db(table).insert(row);
  } else {
    const hasConflict = op.base_version != null && current.version !== op.base_version;
    const clientWins = !hasConflict
      || (op.client_updated_at && op.client_updated_at > current.updated_at);
    if (hasConflict) {
      result = 'conflict_resolved';
      conflictPayload = clientWins ? current : op.payload;
    }
    if (clientWins) {
      const destinationFix = await resolveMissingDestination(
        auth, op, mergeForDestinationCheck(current, op.payload),
      );
      if (destinationFix.rejected) {
        return record(auth, deviceId, op, 'rejected', null, destinationFix.message);
      }
      const patch = {
        ...serializePayload(op.entity, op.payload ?? {}),
        updated_at: ts,
        version: current.version + 1,
      };
      delete patch.id;
      await db(table).where({ id: op.entity_id }).update(patch);
    }
  }

  return record(auth, deviceId, op, result, conflictPayload);
}

async function record(auth, deviceId, op, result, conflictPayload, message) {
  await db('sync_operations').insert({
    id: crypto.randomUUID(),
    operation_id: op.operation_id,
    user_id: auth.userId,
    device_id: deviceId,
    entity: op.entity,
    entity_id: op.entity_id,
    op: op.op,
    payload: op.payload ? JSON.stringify(op.payload) : null,
    base_version: op.base_version ?? null,
    result,
    conflict_payload: conflictPayload ? JSON.stringify(conflictPayload) : null,
    created_at: now(),
  });
  const current = await db(ENTITIES[op.entity].table).where({ id: op.entity_id }).first();
  return {
    operation_id: op.operation_id,
    result,
    message,
    record: deserialize(op.entity, current),
  };
}

router.post('/push', validate(pushSchema), async (req, res) => {
  const results = [];
  // Sequencial: preserva a ordem causal das operações do dispositivo.
  for (const op of req.body.operations) {
    try {
      results.push(await applyOperation(req.auth, req.body.device_id, op));
    } catch (err) {
      results.push({ operation_id: op.operation_id, result: 'rejected', message: err.message });
    }
  }
  res.json({ data: { results, server_time: now() } });
});

router.get('/pull', async (req, res) => {
  const since = req.query.since && req.query.since !== '0' ? String(req.query.since) : null;
  const requested = req.query.entities ? String(req.query.entities).split(',') : ENTITY_NAMES;
  const cursor = now();
  const entities = {};
  for (const name of requested) {
    if (!ENTITIES[name]) continue;
    const { table } = ENTITIES[name];
    const q = applyScope(db(table), name, req.auth).orderBy(`${table}.updated_at`);
    if (since) q.where(`${table}.updated_at`, '>', since);
    const rows = await q.limit(5000);
    entities[name] = rows.map((r) => deserialize(name, r));
  }
  res.json({ data: { entities, cursor } });
});

export default router;
