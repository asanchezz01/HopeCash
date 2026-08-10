import { Router } from 'express';
import { syncRepo } from '../../core/syncRepo.js';
import { now } from '../../utils/time.js';
import { crudRouter } from '../../core/crudRouter.js';

const router = Router();

/** Atalho de conveniência sobre o CRUD genérico: marca a notificação como lida. */
router.patch('/:id/read', async (req, res) => {
  const row = await syncRepo.update('notifications', req.auth, req.params.id, { read_at: now() });
  res.json({ data: row });
});

// Listagem, detalhe, criação e exclusão (soft) seguem o CRUD sincronizável padrão.
router.use('/', crudRouter('notifications', { filterFields: ['type'] }));

export default router;
