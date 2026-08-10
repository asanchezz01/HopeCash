import { Router } from 'express';
import { z } from 'zod';
import { ENTITIES } from './registry.js';
import { syncRepo } from './syncRepo.js';
import { validate } from '../middleware/validate.js';
import { notFound } from '../utils/httpError.js';

const listQuery = z.object({
  updated_since: z.string().optional(),
  include_deleted: z.coerce.boolean().default(false),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(500).default(50),
}).passthrough();

/**
 * CRUD REST padrão para uma entidade sincronizável:
 * GET / · GET /:id · POST / · PUT /:id (otimista por version) · DELETE /:id (soft).
 * `filterFields` define filtros de igualdade permitidos na listagem.
 */
export function crudRouter(entity, { filterFields = [] } = {}) {
  const { schema } = ENTITIES[entity];
  const router = Router();

  router.get('/', validate(listQuery, 'query'), async (req, res) => {
    const { updated_since, include_deleted, page, limit, ...rest } = req.query;
    const filters = Object.fromEntries(filterFields.filter((f) => rest[f] !== undefined).map((f) => [f, rest[f]]));
    const data = await syncRepo.list(entity, req.auth, {
      updatedSince: updated_since, includeDeleted: include_deleted, page, limit, filters,
    });
    res.json({ data, page, limit });
  });

  router.get('/:id', async (req, res) => {
    const row = await syncRepo.findById(entity, req.auth, req.params.id);
    if (!row) throw notFound();
    res.json({ data: row });
  });

  router.post('/', validate(schema), async (req, res) => {
    const row = await syncRepo.create(entity, req.auth, req.body, { req });
    res.status(201).json({ data: row });
  });

  router.put('/:id', validate(schema.partial().extend({ version: z.coerce.number().int().optional() })), async (req, res) => {
    const expectedVersion = req.headers['if-match-version']
      ? Number(req.headers['if-match-version'])
      : req.body.version ?? null;
    const { version: _v, ...data } = req.body;
    const row = await syncRepo.update(entity, req.auth, req.params.id, data, { expectedVersion, req });
    res.json({ data: row });
  });

  router.delete('/:id', async (req, res) => {
    const result = await syncRepo.softDelete(entity, req.auth, req.params.id, { req });
    res.json({ data: result });
  });

  return router;
}
