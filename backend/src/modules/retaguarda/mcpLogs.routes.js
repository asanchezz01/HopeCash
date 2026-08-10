import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { validate } from '../../middleware/validate.js';

/**
 * Leitura da trilha de chamadas MCP (`mcp_logs`), montada em
 * /api/v1/retaguarda/mcp-logs. Só leitura — a tabela é append-only, escrita
 * exclusivamente por `modules/ai/mcpLog.js`.
 */
const router = Router();

const listQuery = z.object({
  user_id: z.string().uuid().optional(),
  tool_name: z.string().max(60).optional(),
  method: z.string().max(40).optional(),
  // "only_errors=true" responde a pergunta operacional mais comum: o que
  // está falhando agora.
  only_errors: z.enum(['true', 'false']).optional(),
  since: z.string().datetime().optional(),
  until: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

function applyFilters(query, q) {
  if (q.user_id) query.where('mcp_logs.user_id', q.user_id);
  if (q.tool_name) query.where('mcp_logs.tool_name', q.tool_name);
  if (q.method) query.where('mcp_logs.method', q.method);
  if (q.only_errors === 'true') query.where('mcp_logs.ok', false);
  if (q.since) query.where('mcp_logs.created_at', '>=', new Date(q.since));
  if (q.until) query.where('mcp_logs.created_at', '<=', new Date(q.until));
  return query;
}

router.get('/', validate(listQuery, 'query'), async (req, res) => {
  const q = req.query;

  const rows = await applyFilters(
    db('mcp_logs')
      .leftJoin('users', 'users.id', 'mcp_logs.user_id')
      .select(
        'mcp_logs.id',
        'mcp_logs.user_id',
        'users.name as user_name',
        'users.email as user_email',
        'mcp_logs.client_name',
        'mcp_logs.pat_kind',
        'mcp_logs.method',
        'mcp_logs.tool_name',
        'mcp_logs.ok',
        'mcp_logs.status_code',
        'mcp_logs.error_code',
        'mcp_logs.error_message',
        'mcp_logs.arguments',
        'mcp_logs.duration_ms',
        'mcp_logs.ip',
        'mcp_logs.user_agent',
        'mcp_logs.created_at',
      ),
    q,
  )
    .orderBy('mcp_logs.created_at', 'desc')
    .limit(q.limit)
    .offset(q.offset);

  const total = await applyFilters(db('mcp_logs'), q).count({ n: '*' }).first();

  res.json({ data: rows, meta: { total: Number(total.n), limit: q.limit, offset: q.offset } });
});

/**
 * Agregado por tool — mostra de imediato qual tool concentra os erros,
 * inclusive tools que o host pede e não existem (ver `docs/MCP.md`).
 */
router.get('/summary', validate(z.object({
  since: z.string().datetime().optional(),
  until: z.string().datetime().optional(),
}), 'query'), async (req, res) => {
  const rows = await applyFilters(db('mcp_logs'), req.query)
    .select('tool_name', 'method', 'client_name')
    .count({ calls: '*' })
    .sum({ errors: db.raw('CASE WHEN ok THEN 0 ELSE 1 END') })
    .groupBy('tool_name', 'method', 'client_name')
    .orderBy('calls', 'desc');

  res.json({
    data: rows.map((r) => ({
      tool_name: r.tool_name,
      method: r.method,
      client_name: r.client_name,
      calls: Number(r.calls),
      errors: Number(r.errors ?? 0),
    })),
  });
});

export default router;
