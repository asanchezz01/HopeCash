/**
 * Gravação da trilha de chamadas MCP (tabela `mcp_logs`).
 *
 * Mesma regra do `core/audit.js`: é best-effort e NUNCA pode derrubar a
 * chamada MCP em si — um erro ao registrar o log não pode virar um erro
 * devolvido ao host.
 */
import crypto from 'node:crypto';
import { db } from '../../db/knex.js';
import { now } from '../../utils/time.js';

/** `arguments` pode vir arbitrariamente grande do host; a coluna é TEXT. */
const MAX_ARGUMENTS_CHARS = 2000;

function serializeArguments(args) {
  if (args == null) return null;
  try {
    const json = JSON.stringify(args);
    if (json == null) return null;
    return json.length > MAX_ARGUMENTS_CHARS
      ? `${json.slice(0, MAX_ARGUMENTS_CHARS)}…[truncado]`
      : json;
  } catch {
    // Argumentos com referência circular / BigInt — não vale derrubar nada.
    return null;
  }
}

export async function recordMcpCall({
  req, method, toolName, ok, statusCode, errorCode, errorMessage, args, durationMs,
}) {
  try {
    await db('mcp_logs').insert({
      id: crypto.randomUUID(),
      user_id: req?.auth?.userId ?? null,
      client_name: req?.auth?.patName?.slice(0, 120) ?? null,
      pat_kind: req?.auth?.patKind ?? null,
      method: method?.slice(0, 40) ?? null,
      tool_name: toolName?.slice(0, 60) ?? null,
      ok,
      status_code: statusCode,
      error_code: errorCode ?? null,
      error_message: errorMessage?.slice(0, 1000) ?? null,
      arguments: serializeArguments(args),
      duration_ms: durationMs ?? null,
      ip: req?.ip?.slice(0, 45) ?? null,
      user_agent: req?.headers?.['user-agent']?.slice(0, 300) ?? null,
      created_at: now(),
    });
  } catch {
    // best-effort
  }
}
