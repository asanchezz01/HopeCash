import { Router } from 'express';
import { confirmAction, rejectAction } from './service.js';

const router = Router();

router.post('/:id/confirm', async (req, res) => {
  res.json({ data: await confirmAction(req.auth, req.params.id, req) });
});

router.post('/:id/reject', async (req, res) => {
  res.json({ data: await rejectAction(req.auth, req.params.id) });
});

export default router;
