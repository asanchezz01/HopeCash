import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import * as patService from './pat.service.js';
import { audit } from '../../core/audit.js';

const router = Router();

const createPatSchema = z.object({
  name: z.string().min(1).max(120),
  expires_in_days: z.coerce.number().int().min(1).max(365).optional(),
  kind: z.enum(['mcp_read', 'mcp_write', 'push_transactions']).default('push_transactions'),
});

/** Cria um novo Personal Access Token. */
router.post('/', validate(createPatSchema), async (req, res) => {
  const { name, expires_in_days, kind } = req.body;
  const userId = req.auth.userId;

  let expiresAt = null;
  if (expires_in_days) {
    expiresAt = new Date(Date.now() + expires_in_days * 86400_000).toISOString().slice(0, 23).replace('T', ' ');
  }

  const pat = await patService.createPat(userId, name, expiresAt, kind);

  await audit({
    auth: { userId },
    entity: 'personal_access_tokens',
    entityId: pat.id,
    action: 'create',
    req,
  });

  // Retorna o token em clear text APENAS nesta criação
  res.status(201).json({ data: pat });
});

/** Lista todos os PATs ativos do usuário. */
router.get('/', async (req, res) => {
  const userId = req.auth.userId;
  const pats = await patService.listPats(userId);
  res.json({ data: pats });
});

/** Revoga um PAT. */
router.delete('/:id', validate(z.object({ id: z.string().uuid() }), 'params'), async (req, res) => {
  const userId = req.auth.userId;
  const { id } = req.params;

  await patService.revokePat(userId, id);

  await audit({
    auth: { userId },
    entity: 'personal_access_tokens',
    entityId: id,
    action: 'revoke',
    req,
  });

  res.json({ data: { ok: true } });
});

export default router;
