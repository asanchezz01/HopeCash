import { logger } from '../../logger.js';
import { syncRepo } from '../../core/syncRepo.js';
import { today } from '../../utils/time.js';
import { llm } from './llm.js';
import { callTool } from './tools/index.js';
import {
  PARSE_OUTPUT_SCHEMA,
  parseOutputSchema,
  parseSystemPrompt,
  parseUserPayload,
} from './prompts/parseTransaction.js';

/**
 * Rota determinística de lançamento: frases inequívocas de "lançar um gasto"
 * passam pela MESMA extração estruturada da rota /ai/parse-transaction
 * (structured outputs + ids reais do usuário) e viram direto uma proposta de
 * create_transaction. No tool-calling livre um modelo pode inventar nomes de conta
 * e categoria que o usuário nunca citou; a extração restrita aos ids reais
 * não tem esse caminho de falha. Qualquer dúvida (parse indisponível,
 * confiança baixa, parcelamento) cai para o loop normal do agente.
 */

const PARSE_TIMEOUT_MS = 120_000;
const MAX_RESULT_CHARS = 6_000;

const WRITE_VERB = /\b(?:lanc(?:a|e|ar|ei|ou|ando)|registr(?:a|e|ar|ei|ou|ando)|anot(?:a|e|ar|ei|ou|ando)|adicion(?:a|e|ar|ei|ou|ando))\b/;
// Intenções que create_transaction não cobre — ficam com as tools do agente.
const OTHER_INTENT = /\b(?:transfer\w*|metas?|orcament\w*|categorias?|assinaturas?|baix\w*|pag(?:a|ar|uei|ou|amento|amentos)|quit\w*|fatura\w*)\b/;
const HAS_AMOUNT = /\d|\b(?:um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|onze|doze|quinze|vinte|trinta|quarenta|cinquenta|sessenta|setenta|oitenta|noventa|cem|cento|duzentos|trezentos|quatrocentos|quinhentos|seiscentos|setecentos|oitocentos|novecentos|mil)\b/;

const normalize = (value) => String(value ?? '')
  .normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().trim();

const latestUserContent = (history) => {
  for (let i = history.length - 1; i >= 0; i--) {
    if (history[i].role === 'user') return String(history[i].content ?? '').trim();
  }
  return '';
};

const formatMoney = (value) => new Intl.NumberFormat('pt-BR', {
  style: 'currency', currency: 'BRL',
}).format(Number(value ?? 0));

const formatDateBR = (iso) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

const truncate = (text) => (text.length > MAX_RESULT_CHARS
  ? `${text.slice(0, MAX_RESULT_CHARS)}…(resultado truncado)`
  : text);

const proposalAnswer = (params, { account, card, category, subcategory }) => {
  const kind = params.type === 'income' ? 'receita' : 'despesa';
  const dateLabel = params.date === today() ? 'hoje' : `em ${formatDateBR(params.date)}`;
  let detail = `**${kind === 'receita' ? 'Receita' : 'Despesa'} de ${formatMoney(params.amount)}** — ${params.description}, ${dateLabel}`;
  if (card) detail += `, no cartão ${card.name}`;
  else if (account) detail += `, na conta ${account.name}`;
  if (category) detail += `, categoria ${category.name}`;
  if (subcategory) detail += ` · ${subcategory.name}`;
  return `Criei a proposta: ${detail}. Revise o card e toque em Confirmar ou Recusar.`;
};

export function matchesDirectTransaction(message) {
  const normalized = normalize(message);
  return WRITE_VERB.test(normalized) && HAS_AMOUNT.test(normalized) && !OTHER_INTENT.test(normalized);
}

export async function deterministicWriteRoute(auth, history, events = {}, context = {}) {
  const transcript = latestUserContent(history);
  if (!context.conversationId || !matchesDirectTransaction(transcript)) return null;

  try {
    const [categories, subcategories, accounts, cards] = await Promise.all([
      syncRepo.list('categories', auth, { limit: 200 }),
      syncRepo.list('subcategories', auth, { limit: 500 }),
      syncRepo.list('bank_accounts', auth, { limit: 50, filters: { is_active: 1 } }),
      syncRepo.list('credit_cards', auth, { limit: 50, filters: { is_active: 1 } }),
    ]);

    const raw = await llm.chatJson({
      model: llm.models.fast,
      modelKey: 'fast',
      format: PARSE_OUTPUT_SCHEMA,
      temperature: 0,
      timeoutMs: PARSE_TIMEOUT_MS,
      messages: [
        { role: 'system', content: parseSystemPrompt(today()) },
        { role: 'user', content: parseUserPayload({ transcript, categories, subcategories, accounts, cards }) },
      ],
    });
    const parsed = parseOutputSchema.safeParse(raw);
    if (!parsed.success) return null;
    const out = parsed.data;
    // Parcelamento não existe em create_transaction; confiança baixa merece
    // o loop com tools (que pode consultar e perguntar).
    if (out.confidence === 'low' || out.installments > 1) return null;

    // Os ids vêm do modelo, mas só valem se existirem mesmo para o usuário.
    const category = categories.find((c) => c.id === out.category_id && c.type === out.type) ?? null;
    const subcategory = category
      ? subcategories.find((sc) => sc.id === out.subcategory_id && sc.category_id === category.id) ?? null
      : null;
    const account = accounts.find((a) => a.id === out.account_id) ?? null;
    const card = out.type === 'expense' ? cards.find((c) => c.id === out.card_id) ?? null : null;

    const params = {
      type: out.type,
      description: out.description.trim() || transcript.slice(0, 200),
      amount: Math.round(out.amount * 100) / 100,
      date: out.date,
      paid: card ? false : out.paid,
      ...(account && !card ? { account_id: account.id } : {}),
      ...(card ? { card_id: card.id } : {}),
      ...(category ? { category_id: category.id } : {}),
      ...(subcategory ? { subcategory_id: subcategory.id } : {}),
    };

    events.onTool?.('create_transaction');
    const result = await callTool('create_transaction', auth, params, context);
    events.onAction?.(result.action);
    const content = proposalAnswer(params, { account, card, category, subcategory });
    events.onDelta?.(content);
    return {
      content,
      tool_calls: [{ name: 'create_transaction', arguments: params, result: truncate(JSON.stringify(result)) }],
      action_ids: [result.action.id],
      references: [],
    };
  } catch (err) {
    logger.warn({ err: err.message }, 'Lançamento determinístico falhou; caindo para o loop do agente');
    return null;
  }
}
