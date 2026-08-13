import { Router } from 'express';
import { z } from 'zod';
import { config } from '../../config.js';
import { logger } from '../../logger.js';
import { validate } from '../../middleware/validate.js';
import { syncRepo } from '../../core/syncRepo.js';
import { HttpError } from '../../utils/httpError.js';
import { today } from '../../utils/time.js';
import { llm, LlmError } from './llm.js';
import { tts, TtsError } from './tts.js';
import { TOOLS, callTool } from './tools/index.js';
import chatRoutes from './chat.routes.js';
import actionsRoutes from './actions/actions.routes.js';
import mcpRouter from './mcp.server.js';
import {
  PARSE_OUTPUT_SCHEMA,
  parseOutputSchema,
  parseSystemPrompt,
  parseUserPayload,
} from './prompts/parseTransaction.js';

const router = Router();

// Chat com a Hope (SSE), gestão de ações e servidor MCP (Etapa 6).
router.use('/actions', actionsRoutes);
router.use('/', chatRoutes);

/**
 * Estado da IA: Groq acessível e modelos configurados/disponíveis.
 * O app usa para esconder recursos de IA quando indisponível; nunca falha.
 */
router.get('/health', async (_req, res) => {
  res.json({ data: await llm.health() });
});

/** Sintetiza uma resposta da Hope por Azure Speech. */
router.post('/speech', validate(z.object({
  text: z.string().trim().min(1).max(config.tts.maxChars),
})), async (req, res) => {
  try {
    const audio = await tts.speech(req.body.text);
    res.set({
      'content-type': audio.contentType,
      'content-length': String(audio.bytes.length),
      'cache-control': 'private, no-store',
      'x-hope-voice': config.tts.voice,
      'x-tts-provider': audio.provider,
    });
    res.send(audio.bytes);
  } catch (err) {
    if (!(err instanceof TtsError)) throw err;
    logger.warn({ err: err.message }, 'Síntese de voz da Hope falhou');
    throw new HttpError(503, 'TTS_UNAVAILABLE', 'A voz da Hope está indisponível agora');
  }
});

router.get('/speech/health', async (_req, res) => {
  res.json({ data: await tts.health() });
});

/**
 * Interpreta uma frase falada/digitada e devolve um lançamento estruturado
 * com ids reais do usuário, pronto para pré-preencher o formulário no app.
 * Nunca grava nada — a confirmação é sempre do usuário.
 */
router.post('/parse-transaction', validate(z.object({
  transcript: z.string().trim().min(3).max(500),
})), async (req, res) => {
  const { transcript } = req.body;

  const [categories, accounts, cards] = await Promise.all([
    syncRepo.list('categories', req.auth, { limit: 200 }),
    syncRepo.list('bank_accounts', req.auth, { limit: 50, filters: { is_active: 1 } }),
    syncRepo.list('credit_cards', req.auth, { limit: 50, filters: { is_active: 1 } }),
  ]);

  let raw;
  try {
    raw = await llm.chatJson({
      model: llm.models.fast,
      format: PARSE_OUTPUT_SCHEMA,
      temperature: 0,
      messages: [
        { role: 'system', content: parseSystemPrompt(today()) },
        { role: 'user', content: parseUserPayload({ transcript, categories, accounts, cards }) },
      ],
    });
  } catch (err) {
    if (!(err instanceof LlmError)) throw err;
    logger.warn({ err: err.message }, 'Falha ao consultar o Groq');
    throw new HttpError(503, 'AI_UNAVAILABLE', 'Serviço de interpretação indisponível');
  }

  const parsed = parseOutputSchema.safeParse(raw);
  if (!parsed.success) {
    logger.warn({ raw }, 'Resposta do Groq fora do formato esperado');
    throw new HttpError(503, 'AI_UNAVAILABLE', 'Não foi possível interpretar a frase');
  }

  // O modelo escolhe ids, mas nunca confiamos neles às cegas.
  const out = parsed.data;
  const category = categories.find((c) => c.id === out.category_id && c.type === out.type);
  const account = accounts.find((a) => a.id === out.account_id);
  const card = out.type === 'expense' ? cards.find((c) => c.id === out.card_id) : null;

  res.json({
    data: {
      type: out.type,
      amount: Math.round(out.amount * 100) / 100,
      description: out.description.trim() || transcript,
      date: out.date,
      category_id: category?.id ?? null,
      account_id: card ? null : account?.id ?? null,
      card_id: card?.id ?? null,
      installments: card ? out.installments : 1,
      paid: out.paid,
      confidence: out.confidence,
    },
  });
});

// Registra o servidor MCP (Etapa 6) em /api/v1/ai/mcp.
router.use('/mcp', mcpRouter);

export default router;
