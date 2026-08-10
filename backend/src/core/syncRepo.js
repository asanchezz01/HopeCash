import crypto from 'node:crypto';
import { db } from '../db/knex.js';
import { now } from '../utils/time.js';
import { notFound, conflict, forbidden, badRequest } from '../utils/httpError.js';
import { ENTITIES } from './registry.js';
import { audit } from './audit.js';
import { needsDestination, mergeForDestinationCheck, DESTINATION_REQUIRED } from './transactionDestination.js';

/** Serializa campos JSON para TEXT antes de gravar. */
const serialize = (entity, data) => {
  const out = { ...data };
  for (const f of ENTITIES[entity].jsonFields ?? []) {
    if (f in out && out[f] != null && typeof out[f] !== 'string') out[f] = JSON.stringify(out[f]);
  }
  return out;
};

/** Converte TEXT de volta para JSON na leitura. */
export const deserialize = (entity, row) => {
  if (!row) return row;
  const out = { ...row };
  for (const f of ENTITIES[entity].jsonFields ?? []) {
    if (typeof out[f] === 'string' && out[f] !== '') {
      try { out[f] = JSON.parse(out[f]); } catch { /* mantém texto */ }
    }
  }
  return out;
};

/** Escopo de segurança: linhas do próprio usuário, das famílias dele e (opcional) do sistema. */
export const applyScope = (query, entity, auth) => {
  const { table, includeSystem } = ENTITIES[entity];
  return query.where(function () {
    this.where(`${table}.user_id`, auth.userId);
    if (auth.familyIds?.length) this.orWhereIn(`${table}.family_id`, auth.familyIds);
    if (includeSystem) this.orWhere(`${table}.is_system`, true);
  });
};

const assertFamilyAccess = (auth, familyId) => {
  if (familyId && !auth.familyIds.includes(familyId)) {
    throw forbidden('Você não pertence a essa família');
  }
};

export const syncRepo = {
  async list(entity, auth, { updatedSince, includeDeleted, page = 1, limit = 50, filters = {} } = {}) {
    const { table } = ENTITIES[entity];
    const q = applyScope(db(table), entity, auth);
    if (!includeDeleted) q.whereNull(`${table}.deleted_at`);
    if (updatedSince) q.where(`${table}.updated_at`, '>', updatedSince);
    for (const [k, v] of Object.entries(filters)) if (v !== undefined) q.where(`${table}.${k}`, v);
    q.orderBy(`${table}.updated_at`, 'desc').limit(Math.min(limit, 500)).offset((page - 1) * limit);
    const rows = await q;
    return rows.map((r) => deserialize(entity, r));
  },

  async findById(entity, auth, id, { includeDeleted = false, trx } = {}) {
    const { table } = ENTITIES[entity];
    const q = applyScope((trx ?? db)(table), entity, auth).where(`${table}.id`, id);
    if (!includeDeleted) q.whereNull(`${table}.deleted_at`);
    return deserialize(entity, await q.first());
  },

  async create(entity, auth, data, { req, trx } = {}) {
    const { table } = ENTITIES[entity];
    assertFamilyAccess(auth, data.family_id);
    // Chamador online (REST/IA) recebe o 400 e pode reagir na hora. O caminho
    // offline (/sync/push) NÃO passa por aqui de propósito — lá recusar
    // significaria descartar um lançamento que o usuário já deu como salvo.
    if (entity === 'transactions' && needsDestination(data)) throw badRequest(DESTINATION_REQUIRED);
    const ts = now();
    const row = {
      ...serialize(entity, data),
      id: data.id ?? crypto.randomUUID(),
      user_id: auth.userId,
      created_at: ts,
      updated_at: ts,
      deleted_at: null,
      version: 1,
    };
    if (entity === 'transactions') { row.created_by = auth.userId; row.updated_by = auth.userId; }
    await (trx ?? db)(table).insert(row);
    await audit({ auth, entity, entityId: row.id, action: 'create', changes: data, req, trx });
    return this.findById(entity, auth, row.id, { trx });
  },

  /**
   * Atualização com controle otimista: se expectedVersion for informada e
   * divergir da versão atual, retorna 409 para o cliente resolver.
   */
  async update(entity, auth, id, data, { expectedVersion, req, trx } = {}) {
    const { table } = ENTITIES[entity];
    const current = await this.findById(entity, auth, id, { trx });
    if (!current) throw notFound();
    if (current.is_system) throw forbidden('Registros do sistema não podem ser alterados');
    if (expectedVersion != null && current.version !== expectedVersion) {
      throw conflict('Registro alterado por outro dispositivo', { currentVersion: current.version });
    }
    assertFamilyAccess(auth, data.family_id);
    if (entity === 'transactions' && needsDestination(mergeForDestinationCheck(current, data))) {
      throw badRequest(DESTINATION_REQUIRED);
    }
    const patch = { ...serialize(entity, data), updated_at: now(), version: current.version + 1 };
    delete patch.id;
    delete patch.user_id;
    if (entity === 'transactions') patch.updated_by = auth.userId;
    await (trx ?? db)(table).where({ id }).update(patch);
    await audit({ auth, entity, entityId: id, action: 'update', changes: data, req, trx });
    return this.findById(entity, auth, id, { trx });
  },

  async softDelete(entity, auth, id, { req, trx, expectedVersion } = {}) {
    const { table } = ENTITIES[entity];
    const current = await this.findById(entity, auth, id, { trx });
    if (!current) throw notFound();
    if (current.is_system) throw forbidden('Registros do sistema não podem ser excluídos');
    if (expectedVersion != null && current.version !== expectedVersion) {
      throw conflict('Registro alterado por outro dispositivo', { currentVersion: current.version });
    }
    const ts = now();
    await (trx ?? db)(table).where({ id }).update({ deleted_at: ts, updated_at: ts, version: current.version + 1 });
    await audit({ auth, entity, entityId: id, action: 'delete', req, trx });
    return { id, deleted_at: ts, version: current.version + 1 };
  },
};
