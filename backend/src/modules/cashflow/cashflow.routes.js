import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { today, addDays } from '../../utils/time.js';
import { getCashflowProjection } from './cashflow.service.js';

const router = Router();

const querySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).default(() => today()),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).default(() => addDays(today(), 90)),
  granularity: z.enum(['day', 'week', 'month', 'year']).default('month'),
});

router.get('/', validate(querySchema, 'query'), async (req, res) => {
  res.json({ data: await getCashflowProjection(req.auth, req.query) });
});

export default router;
