/**
 * Servidor MCP (Model Context Protocol) — Etapa 6 do AI_ROADMAP.md.
 *
 * Implementa initialize, tools/list e tools/call sobre o registro de tools da HopeCash.
 * Autenticação via Bearer token (JWT ou PAT com escopo read/write).
 */

import crypto from 'node:crypto';
import { Router } from 'express';
import { db } from '../../db/knex.js';
import { now } from '../../utils/time.js';
import { TOOLS, TOOLS_BY_NAME, callTool } from './tools/index.js';
import { confirmAction } from './actions/service.js';
import { recordMcpCall } from './mcpLog.js';

export const router = Router();

/**
 * Envia a resposta JSON-RPC e registra a chamada em `mcp_logs`.
 *
 * O log é gravado DEPOIS de responder e sem `await` de propósito: o host MCP
 * não deve esperar um INSERT de auditoria, e `recordMcpCall` já engole os
 * próprios erros. `body` nulo = notificação JSON-RPC (202 sem corpo).
 */
function respond(req, res, { status, body, method, toolName = null, args = null, startedAt }) {
  if (body === null) res.status(status).end();
  else res.status(status).json(body);

  recordMcpCall({
    req,
    method,
    toolName,
    args,
    ok: !body?.error,
    statusCode: status,
    errorCode: body?.error?.code ?? null,
    errorMessage: body?.error?.message ?? null,
    durationMs: Date.now() - startedAt,
  });
}

// Tools de escrita exigem uma ai_conversations (dono de toda proposta em
// ai_actions — ver proposeAction). Hosts MCP não têm conversa de chat, então
// reaproveitamos (ou criamos) uma conversa técnica dedicada por usuário.
const MCP_CONVERSATION_TITLE = 'Hope MCP';

async function getOrCreateMcpConversationId(userId) {
  const existing = await db('ai_conversations')
    .where({ user_id: userId, title: MCP_CONVERSATION_TITLE })
    .first();
  if (existing) return existing.id;

  const id = crypto.randomUUID();
  const ts = now();
  await db('ai_conversations').insert({
    id, user_id: userId, title: MCP_CONVERSATION_TITLE, created_at: ts, updated_at: ts,
  });
  return id;
}

// ---------------------------------------------------------------------------
// Middleware: rejeita tokens push_transactions (não têm escopo MCP).
// JWTs passam (pass-through) — o gate do v1 router + scope do handler cuidam.
// ---------------------------------------------------------------------------
function requireMcpContext() {
  return (req, res, next) => {
    // Se não é PAT, passa direto — JWT é autorizado pela rota REST geral.
    if (!req.auth?.isPat) return next();

    const patKind = req.auth.patKind;
    if (patKind === 'push_transactions') {
      const id = req.body?.id ?? null;
      return respond(req, res, {
        status: 403,
        body: {
          jsonrpc: '2.0',
          id,
          error: { code: -32605, message: 'Este token PAT não tem escopo MCP.' },
        },
        method: req.body?.method,
        toolName: req.body?.params?.name ?? null,
        startedAt: Date.now(),
      });
    }

    next();
  };
}

const initializeResult = () => ({
  protocolVersion: '2024-11-05',
  capabilities: { tools: { listChanged: false } },
  serverInfo: { name: 'hopecash-mcp', version: '1.0.0' },
});

/**
 * POST /initialize — alias legado (curl direto, ver docs/MCP.md). Hosts MCP
 * reais (Claude Code, Claude Desktop) usam transporte HTTP "Streamable": uma
 * única URL para toda a sessão, então `initialize` também precisa responder
 * em /methods — é o que os clientes de verdade chamam.
 */
router.post('/initialize', requireMcpContext(), (req, res) => {
  const id = req.body?.id ?? null;
  respond(req, res, {
    status: 200,
    body: { jsonrpc: '2.0', id, result: initializeResult() },
    method: 'initialize',
    startedAt: Date.now(),
  });
});

/**
 * POST / (e o alias /methods) — o endpoint de verdade. Hosts com transporte
 * HTTP "Streamable" (Claude Code, Claude Desktop) mandam initialize,
 * notifications/initialized, tools/list e tools/call todos para a MESMA URL
 * configurada — por isso o roteamento por `method` acontece aqui dentro, e
 * não em rotas HTTP separadas.
 */
/**
 * Resolve a chamada JSON-RPC e devolve `{ status, body }` em vez de escrever
 * na resposta. Separado de `handleRpc` para que TODO caminho de saída — sucesso,
 * tool inexistente, parâmetros inválidos, erro interno — passe por um único
 * ponto de resposta e seja registrado em `mcp_logs` sem repetição.
 */
async function dispatch(req) {
  const { body, auth } = req;
  const id = body?.id ?? null;
  const method = body?.method;
  const params = body?.params ?? {};

  // Notificação JSON-RPC (sem "id"): o host não espera resposta — ex.:
  // notifications/initialized, enviada logo após o initialize. Responder com
  // um erro aqui confundiria o cliente; o protocolo pede 202 sem corpo.
  if (!('id' in (body ?? {}))) {
    return { status: 202, body: null };
  }

  switch (method) {
    case 'initialize':
      return { status: 200, body: { jsonrpc: '2.0', id, result: initializeResult() } };

    case 'tools/list':
      return {
        status: 200,
        body: {
          jsonrpc: '2.0',
          id,
          result: {
            tools: TOOLS.map((t) => ({
              name: t.name,
              inputSchema: t.inputSchema,
              description: t.description ?? '',
              write: t.scope === 'write',
            })),
          },
        },
      };

    case 'tools/call': {
      const toolName = params?.name;
      if (!toolName) {
        return {
          status: 400,
          body: { jsonrpc: '2.0', id, error: { code: -32602, message: 'Param "name" é obrigatório' } },
        };
      }

      const tool = TOOLS_BY_NAME[toolName];
      if (!tool) {
        return {
          status: 404,
          body: { jsonrpc: '2.0', id, error: { code: -32601, message: `Tool não encontrada: ${toolName}` } },
        };
      }

      const raw = params?.arguments ?? {};
      const parsed = tool.paramsSchema.safeParse(raw);
      if (!parsed.success) {
        return {
          status: 400,
          body: {
            jsonrpc: '2.0',
            id,
            error: { code: -32602, message: `Parâmetros inválidos para ${toolName}`, data: parsed.error },
          },
        };
      }

      try {
        const context = tool.scope === 'write'
          ? { conversationId: await getOrCreateMcpConversationId(auth.userId) }
          : {};
        const proposal = await callTool(toolName, auth, parsed.data, context);
        let result = proposal;
        if (tool.scope === 'write') {
          // Hosts MCP (ChatGPT, Claude) já pedem aprovação do usuário antes de
          // chamar uma tool de escrita — essa é a barreira de segurança real
          // nesse caminho. Por isso a escrita via MCP propõe e confirma na
          // mesma chamada (uma única ida-e-volta), ao contrário do chat
          // interno da Hope, onde a confirmação é sempre um clique humano no
          // card, em uma chamada REST separada e mais tarde (ver
          // actions/service.js). Duas chamadas MCP separadas no tempo para a
          // mesma escrita já causou "Session terminated" com o ChatGPT.
          result = await confirmAction(auth, proposal.action.id, req);
          // O host executa sem card de confirmação, então um destino escolhido
          // pelo sistema precisa voltar no resultado — senão o usuário só
          // descobre a conta usada abrindo o app.
          if (proposal.assumed_account) {
            result = {
              ...result,
              assumed_account: proposal.assumed_account,
              notice: `Lançado em "${proposal.assumed_account.name}" porque `
                + `${proposal.assumed_account.reason}. Confirme com o usuário se a conta está correta.`,
            };
          }
        }
        return {
          status: 200,
          body: {
            jsonrpc: '2.0',
            id,
            result: {
              content: [{ type: 'text', text: JSON.stringify(result) }],
              isError: false,
            },
          },
        };
      } catch (err) {
        return {
          status: err.status ?? 500,
          body: {
            jsonrpc: '2.0',
            id,
            error: {
              code: -32603,
              message: err.message ?? 'Erro interno ao executar a tool',
              data: err.details ?? undefined,
            },
          },
        };
      }
    }

    default:
      return {
        status: 400,
        body: { jsonrpc: '2.0', id, error: { code: -32601, message: `Método "${method}" não implementado` } },
      };
  }
}

async function handleRpc(req, res) {
  const startedAt = Date.now();
  const method = req.body?.method;
  // Lidos do request (não do dispatch) para que uma tool INEXISTENTE também
  // fique registrada pelo nome — era exatamente o dado que faltava quando só
  // existia o log do container.
  const toolName = method === 'tools/call' ? (req.body?.params?.name ?? null) : null;
  const args = method === 'tools/call' ? (req.body?.params?.arguments ?? null) : null;

  const { status, body } = await dispatch(req);
  respond(req, res, { status, body, method, toolName, args, startedAt });
}

router.post('/', requireMcpContext(), handleRpc);
router.post('/methods', requireMcpContext(), handleRpc);

export default router;
