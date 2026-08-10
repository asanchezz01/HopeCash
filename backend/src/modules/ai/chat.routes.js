import crypto from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { db } from '../../db/knex.js';
import { logger } from '../../logger.js';
import { validate } from '../../middleware/validate.js';
import { notFound } from '../../utils/httpError.js';
import { now } from '../../utils/time.js';
import { runAgent } from './agent.js';
import { actionsForMessages } from './actions/service.js';

const router = Router();

const HISTORY_LIMIT = 20;

const chatSchema = z.object({
  conversation_id: z.string().uuid().nullish(),
  message: z.string().trim().min(1).max(2000),
});

const ownConversation = async (auth, id) => {
  const conversation = await db('ai_conversations').where({ id, user_id: auth.userId }).first();
  if (!conversation) throw notFound('Conversa não encontrada');
  return conversation;
};

/**
 * Conversa com a Hope. Resposta em SSE:
 *   event: meta  → { conversation_id }      (primeiro evento, sempre)
 *   event: tool  → { name }                 (uma consulta começou)
 *   event: delta → { text }                 (trecho da resposta)
 *   event: action → { ...ação proposta }    (card de confirmação)
 *   event: references → { items }           (lançamentos citados, para "ver lançamento")
 *   event: done  → { message_id }           (resposta completa e persistida)
 *   event: error → { message }              (falha após o início do stream)
 */
router.post('/chat', validate(chatSchema), async (req, res) => {
  const { conversation_id: conversationId, message } = req.body;
  const ts = now();

  let conversation;
  if (conversationId) {
    conversation = await ownConversation(req.auth, conversationId);
  } else {
    conversation = {
      id: crypto.randomUUID(),
      user_id: req.auth.userId,
      title: message.slice(0, 80),
      created_at: ts,
      updated_at: ts,
    };
    await db('ai_conversations').insert(conversation);
  }

  const previous = await db('ai_messages')
    .where({ conversation_id: conversation.id })
    .orderBy('created_at', 'desc').limit(HISTORY_LIMIT)
    .select('role', 'content');
  const history = previous.reverse().map((m) => ({ role: m.role, content: m.content }));

  await db('ai_messages').insert({
    id: crypto.randomUUID(),
    conversation_id: conversation.id,
    role: 'user',
    content: message,
    created_at: ts,
  });

  // A partir daqui a resposta é um stream: erros viram `event: error`.
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
    connection: 'keep-alive',
    'x-accel-buffering': 'no', // nginx: não bufferizar o stream
  });
  let closed = false;
  req.on('close', () => { closed = true; });
  const send = (event, data) => {
    if (closed || res.writableEnded) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  send('meta', { conversation_id: conversation.id });

  try {
    const result = await runAgent(req.auth, [...history, { role: 'user', content: message }], {
      onDelta: (text) => send('delta', { text }),
      onTool: (name) => send('tool', { name }),
      onAction: (action) => send('action', action),
    }, { conversationId: conversation.id });

    const references = result.references ?? [];
    const assistantMessage = {
      id: crypto.randomUUID(),
      conversation_id: conversation.id,
      role: 'assistant',
      content: result.content,
      tool_calls: result.tool_calls.length ? JSON.stringify(result.tool_calls) : null,
      references: references.length ? JSON.stringify(references) : null,
      created_at: now(),
    };
    await db('ai_messages').insert(assistantMessage);
    if (result.action_ids.length) {
      await db('ai_actions').whereIn('id', result.action_ids)
        .where({ conversation_id: conversation.id }).update({ message_id: assistantMessage.id, updated_at: now() });
    }
    await db('ai_conversations').where({ id: conversation.id }).update({ updated_at: now() });

    if (references.length) send('references', { items: references });
    send('done', { message_id: assistantMessage.id });
  } catch (err) {
    logger.warn({ err: err.message }, 'Chat da Hope falhou');
    send('error', { message: 'A Hope está indisponível agora. Tente novamente em instantes.' });
  }
  res.end();
});

/** Conversas do usuário, da mais recente para a mais antiga. */
router.get('/conversations', async (req, res) => {
  const rows = await db('ai_conversations')
    .where({ user_id: req.auth.userId })
    .orderBy('updated_at', 'desc').limit(30)
    .select('id', 'title', 'created_at', 'updated_at');
  res.json({ data: rows });
});

/** Uma conversa com todas as mensagens, em ordem cronológica. */
router.get('/conversations/:id', async (req, res) => {
  const conversation = await ownConversation(req.auth, req.params.id);
  const messages = await db('ai_messages')
    .where({ conversation_id: conversation.id })
    .orderBy('created_at')
    .select('id', 'role', 'content', 'tool_calls', 'references', 'created_at');
  const actions = await actionsForMessages(req.auth, conversation.id);
  const actionsByMessage = new Map();
  for (const action of actions) {
    if (!actionsByMessage.has(action.message_id)) actionsByMessage.set(action.message_id, []);
    actionsByMessage.get(action.message_id).push(action);
  }
  res.json({
    data: {
      ...conversation,
      messages: messages.map((m) => ({
        ...m,
        tool_calls: m.tool_calls ? JSON.parse(m.tool_calls) : null,
        references: m.references ? JSON.parse(m.references) : [],
        actions: actionsByMessage.get(m.id) ?? [],
      })),
    },
  });
});

/** Exclusão definitiva (LGPD): a conversa e as mensagens somem do banco. */
router.delete('/conversations/:id', async (req, res) => {
  const conversation = await ownConversation(req.auth, req.params.id);
  await db('ai_actions').where({ conversation_id: conversation.id, user_id: req.auth.userId }).del();
  await db('ai_messages').where({ conversation_id: conversation.id }).del();
  await db('ai_conversations').where({ id: conversation.id }).del();
  res.json({ data: { id: conversation.id, deleted: true } });
});

export default router;
