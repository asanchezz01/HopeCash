import { logger } from '../../logger.js';
import { addDays, addMonths, monthStart, today } from '../../utils/time.js';
import { llm, LlmError } from './llm.js';
import { TOOLS, TOOLS_BY_NAME, callTool, toLlmTool } from './tools/index.js';
import { chatSystemPrompt } from './prompts/chat.js';
import { deterministicWriteRoute } from './deterministicWrite.js';

const MAX_ITERATIONS = 6;
const AGENT_DEADLINE_MS = 120_000;
const MAX_TOOL_RESULT_CHARS = 6_000;
const SAFE_GROUNDING_FALLBACK = 'Não consegui consultar dados suficientes para responder com segurança. Tente reformular a pergunta ou tente novamente em instantes.';
const FINANCIAL_INTENT = /\b(saldos?|extratos?|lancamentos?|transa(?:cao|coes)|movimenta(?:cao|coes)|despesas?|receitas?|gast\w*|pag\w*|receb\w*|contas?|cart(?:ao|oes)|carteiras?|faturas?|venc\w*|orcamentos?|metas?|dividas?|financiamentos?|investimentos?|patrimonios?|fluxos?|categorias?|transfer\w*|pix|boletos?|farmacias?|mercados?|assinaturas?|parcelas?|juros?|rendas?|economi\w*|valores?)\b/i;
const FINANCIAL_ACTION = /\b(cria(?:r|ndo)?|crie|criou|lanca(?:r|ndo)?|lance|lancou|adicion\w*|alter\w*|edit\w*|pagu\w*|quit\w*|transfer\w*|registr\w*|orc\w*)\b/i;
const SHORT_FOLLOW_UP = /^(sim|nao|pode|quero|mostre|detalhe|detalhar|mais|esse|essa|isso|dele|dela)(\s+.*)?[?!.]*$/i;
const SOCIAL_ONLY = /^(oi|ola|obrigad[oa]?|valeu|tchau|bom dia|boa tarde|boa noite)[!., ]*$/i;

const normalizeIntent = (value) => String(value ?? '')
  .normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().trim();

const latestBefore = (history, index, role) => {
  for (let i = index - 1; i >= 0; i--) if (history[i].role === role) return history[i].content ?? '';
  return '';
};

const latestUserContent = (history) => {
  for (let i = history.length - 1; i >= 0; i--) {
    if (history[i].role === 'user') return String(history[i].content ?? '').trim();
  }
  return '';
};

/**
 * "Quanto gastei/recebi este mês (ou mês passado)?" → total por categoria.
 * O qwen3:8b erra a aritmética de datas ("este mês" vira o mês anterior),
 * então o período do mês nunca é delegado ao modelo.
 */
function monthSpendingRoute(normalized, date) {
  if (!/\bquanto\b/.test(normalized)) return null;
  const lastMonth = /\bmes\s+passado\b/.test(normalized);
  const currentMonth = !lastMonth
    && (/\b(?:n?est[ea]|n?ess[ea]|no|do)\s+mes\b/.test(normalized) || /\bmes\s+atual\b/.test(normalized));
  if (!currentMonth && !lastMonth) return null;
  // Qualquer filtro extra ("com mercado", "no Nubank") sai da rota direta.
  const residue = normalized
    .replace(/[?!.,;]/g, ' ')
    .replace(/\b(quanto|quanta|qual|total|foi|foram|eu|ja|gast(?:o|os|ei|amos|ando)|despes(?:a|as)|receb(?:i|emos|ido)|receit(?:a|as)|em|no|na|do|da|de|[nd]?est[ea]|[nd]?ess[ea]|mes|atual|passado|ate|agora|o|a|que|me|meu|minha)\b/g, ' ')
    .replace(/\s+/g, ' ').trim();
  if (residue) return null;
  const type = /\b(?:receb\w*|receit\w*)\b/.test(normalized) ? 'income' : 'expense';
  const from = lastMonth ? monthStart(addMonths(date, -1)) : monthStart(date);
  const to = addDays(addMonths(from, 1), -1);
  return {
    name: 'spending_by_category',
    args: { from, to, type },
    kind: 'spending',
    period: lastMonth ? { type: 'last_month', label: 'no mês passado' } : { type: 'month', label: 'este mês' },
  };
}

/** Consultas temporais inequívocas não dependem da escolha probabilística do modelo. */
export function deterministicReadRoute(history, date = today()) {
  const raw = latestUserContent(history);
  const normalized = normalizeIntent(raw);
  if (FINANCIAL_ACTION.test(normalized)) return null;
  const transactionIntent = /\b(lancamentos?|transa(?:cao|coes)|movimenta(?:cao|coes)|despesas?|receitas?|gast\w*|receb\w*)\b/.test(normalized);
  if (!transactionIntent) return null;

  const monthSpending = monthSpendingRoute(normalized, date);
  if (monthSpending) return monthSpending;

  let period = null;
  let args;
  if (/\bhoje\b/.test(normalized)) {
    period = { type: 'today', label: 'hoje' };
    args = { from: date, to: date, limit: 100 };
  } else if (/\bultim[ao]s?\s+\d/.test(normalized)) {
    const recentDays = normalized.match(/\bultimos?\s+(\d{1,2})\s+dias?\b/);
    const days = Number(recentDays?.[1]);
    if (!days || days > 90) return null;
    period = { type: 'recent_days', days, label: `nos últimos ${days} dias` };
    // Período inclusivo: hoje + os N-1 dias anteriores.
    args = { from: addDays(date, 1 - days), to: date, limit: 100 };
  } else if (/\bultim[ao]s?\b/.test(normalized) || /\brecente(s|mente)?\b/.test(normalized)) {
    // "Últimas despesas" = o que já foi lançado, nunca projeções futuras. O
    // teto em `to` evita que parcelas de meses seguintes liderem a ordenação.
    period = { type: 'recent', label: 'mais recentes' };
    args = { to: date, limit: 10 };
  } else {
    return null;
  }

  let kind = 'transactions';
  if (/\b(despesas?|gast\w*|pag\w*)\b/.test(normalized)) {
    args.type = 'expense';
    kind = 'expenses';
  } else if (/\b(receitas?|receb\w*)\b/.test(normalized)) {
    args.type = 'income';
    kind = 'income';
  }

  const creditCard = /\b(?:no|nos|em|do|dos)?\s*cart(?:ao|oes)(?:\s+de\s+credito)?\b/.test(normalized);
  if (creditCard) args.on_credit_card = true;

  const topicMatch = period.type === 'today' ? raw.match(/\bcom\s+(.+?)\s+hoje\b/i) : null;
  let topic = topicMatch?.[1]?.trim().replace(/[?!.]+$/, '') ?? null;
  if (topic) {
    topic = topic.replace(/^(?:a|o|um|uma|uns|umas)\s+/i, '');
    if (/^(?:cart[aã]o|conta|categoria)\b/i.test(topic)) topic = null;
  }
  if (topic) args.text = topic;
  return { name: 'list_transactions', args, kind, topic, creditCard, period };
}

const formatMoney = (value) => new Intl.NumberFormat('pt-BR', {
  style: 'currency', currency: 'BRL',
}).format(Number(value ?? 0));

const deterministicSpendingAnswer = (route, result) => {
  const label = route.args.type === 'income' ? 'Receitas' : 'Despesas';
  const timeLabel = route.period.type === 'month' ? 'neste mês' : route.period.label;
  if (!(result.total > 0) || !result.categories?.length) {
    return { content: `Não encontrei ${label.toLowerCase()} ${timeLabel}.`, references: [] };
  }
  const lines = result.categories.slice(0, 8).map((row) =>
    `- **${row.category?.name ?? 'Sem categoria'}:** ${formatMoney(row.total)}`);
  return {
    content: `**${label} ${route.period.label}: ${formatMoney(result.total)}**\n\n${lines.join('\n')}`,
    references: [],
  };
};

const deterministicTransactionsAnswer = (route, result) => {
  const labels = { transactions: 'Lançamentos', expenses: 'Despesas', income: 'Receitas' };
  let subject = route.topic ? `${labels[route.kind]} com ${route.topic}` : labels[route.kind];
  if (route.creditCard) subject += ' no cartão de crédito';
  const timeLabel = route.period.type === 'today'
    ? (route.topic || route.creditCard ? 'hoje' : 'de hoje')
    : route.period.label;
  if (!result.count) return { content: `Não encontrei ${subject.toLowerCase()} ${timeLabel}.`, references: [] };
  const lines = result.transactions.map((transaction) => {
    const amount = transaction.amount ?? transaction.amount_planned;
    const type = transaction.type === 'income' ? 'Receita' : transaction.type === 'expense' ? 'Despesa' : 'Transferência';
    const status = transaction.status === 'planned' || transaction.status === 'overdue'
      ? ` — ${transaction.status === 'overdue' ? 'vencido' : 'previsto'}` : '';
    return `- **${transaction.description}:** ${formatMoney(amount)} (${type})${status}`;
  });
  const title = `${subject} ${timeLabel}`;
  const references = result.transactions.map((transaction) => ({
    id: transaction.id, label: transaction.description,
  }));
  return { content: `**${title}:**\n\n${lines.join('\n')}`, references };
};

/**
 * Decide deterministicamente se o turno depende de dados financeiros.
 * O modelo não pode tomar essa decisão sozinho: foi exatamente isso que
 * permitiu respostas inventadas sem nenhuma consulta.
 */
export function requiresFinancialGrounding(history) {
  let userIndex = -1;
  for (let i = history.length - 1; i >= 0; i--) {
    if (history[i].role === 'user') { userIndex = i; break; }
  }
  if (userIndex < 0) return false;
  const current = normalizeIntent(history[userIndex].content);
  if (!current || SOCIAL_ONLY.test(current)) return false;
  if (FINANCIAL_INTENT.test(current) || FINANCIAL_ACTION.test(current)) return true;
  if (!SHORT_FOLLOW_UP.test(current)) return false;
  return FINANCIAL_INTENT.test(normalizeIntent(latestBefore(history, userIndex, 'assistant')));
}

const isEvidenceTool = (name) => {
  const tool = TOOLS_BY_NAME[name];
  return Boolean(tool && (tool.scope === 'write' || !name.startsWith('search_')));
};

const groundingReminder = (hadFailedTool = false) => ({
  role: 'system',
  content: hadFailedTool
    ? 'A consulta anterior falhou ou não trouxe evidência suficiente. Tente outra ferramenta adequada. Não informe nenhum fato financeiro sem um resultado bem-sucedido neste turno.'
    : 'Você tentou responder sem consultar os dados. Antes de responder, chame uma ferramenta que consulte exatamente o dado financeiro solicitado. Ferramentas search_* sozinhas não são evidência. Se o resultado vier vazio, diga claramente que não encontrou; nunca complete com exemplos ou suposições.',
});

const answerFromEvidenceReminder = {
  role: 'system',
  content: 'Responda agora usando exclusivamente os fatos retornados pelas ferramentas neste turno. Não invente, complete ou deduza lançamentos, valores, datas, descrições, categorias ou contas. Se o resultado estiver vazio, diga que não encontrou.',
};

const clarificationReminder = {
  role: 'system',
  content: 'A ferramenta indicou nome não encontrado ou ambíguo. Se o contexto da conversa apontar a opção correta entre as "disponiveis", chame a ferramenta de novo com ela; caso contrário, faça ao usuário uma pergunta curta e objetiva citando as opções. Não invente dados.',
};

const truncate = (text) => (text.length > MAX_TOOL_RESULT_CHARS
  ? `${text.slice(0, MAX_TOOL_RESULT_CHARS)}…(resultado truncado)`
  : text);

/**
 * Uma rodada de chat em streaming: acumula a mensagem completa e repassa
 * os deltas de texto retornados pelo Groq.
 */
async function streamOnce({ messages, tools, onDelta }) {
  const message = { role: 'assistant', content: '', tool_calls: [] };
  const stream = llm.chatStream({
    model: llm.models.chat,
    modelKey: 'chat',
    messages,
    tools,
    temperature: 0.3,
    timeoutMs: AGENT_DEADLINE_MS,
  });
  for await (const chunk of stream) {
    const m = chunk.message ?? {};
    if (m.content) {
      message.content += m.content;
      onDelta?.(m.content);
    }
    if (m.tool_calls?.length) message.tool_calls.push(...m.tool_calls);
    if (chunk.done) break;
  }
  return message;
}

/**
 * Loop do agente Hope: alterna entre chamadas ao modelo (com o catálogo de
 * tools) e execução das tools solicitadas, até o modelo
 * produzir a resposta final em texto.
 *
 * - `history`: mensagens anteriores da conversa ({ role, content }).
 * - `events.onDelta(text)`: trecho da resposta final, conforme chega.
 * - `events.onTool(name)`: uma tool começou a executar (feedback de UI).
 *
 * Devolve `{ content, tool_calls }` — tool_calls é o log de auditoria
 * (nome, argumentos e resultado truncado de cada execução).
 */
export async function runAgent(auth, history, events = {}, context = {}) {
  const startedAt = Date.now();
  const messages = [
    { role: 'system', content: chatSystemPrompt(today()) },
    ...history,
  ];
  const tools = TOOLS.map(toLlmTool);
  const toolLog = [];
  const actionIds = [];
  const groundingRequired = requiresFinancialGrounding(history);
  let hasEvidence = false;
  // Texto exibido ao usuário: inclui eventuais preâmbulos emitidos antes de
  // uma tool call ("Vou verificar seu saldo…"), não só a resposta final.
  const parts = [];

  const directRoute = deterministicReadRoute(history);
  if (directRoute) {
    events.onTool?.(directRoute.name);
    try {
      const result = await callTool(directRoute.name, auth, directRoute.args, context);
      const payload = truncate(JSON.stringify(result));
      toolLog.push({ name: directRoute.name, arguments: directRoute.args, result: payload });
      const { content, references } = directRoute.kind === 'spending'
        ? deterministicSpendingAnswer(directRoute, result)
        : deterministicTransactionsAnswer(directRoute, result);
      events.onDelta?.(content);
      return { content, tool_calls: toolLog, action_ids: actionIds, references };
    } catch (err) {
      const payload = JSON.stringify({ error: err.message, details: err.details ?? null });
      toolLog.push({ name: directRoute.name, arguments: directRoute.args, result: payload });
      logger.warn({ tool: directRoute.name, err: err.message }, 'Roteamento determinístico falhou');
      // Em caso de falha real da tool, o loop normal ainda pode tentar outra consulta.
    }
  }

  const directWrite = await deterministicWriteRoute(auth, history, events, context);
  if (directWrite) return directWrite;

  // Erro de nome/ambiguidade libera uma pergunta de esclarecimento ao usuário,
  // que a barreira de evidência bloquearia (o modelo não tem outra saída).
  let clarificationNeeded = false;

  for (let i = 0; i < MAX_ITERATIONS; i++) {
    if (Date.now() - startedAt > AGENT_DEADLINE_MS) {
      throw new LlmError('Tempo total do agente esgotado');
    }
    // Última iteração roda sem tools para forçar uma resposta em texto.
    const isLast = i === MAX_ITERATIONS - 1;
    const canStream = !groundingRequired || hasEvidence || clarificationNeeded;
    const message = await streamOnce({
      messages,
      tools: isLast && (!groundingRequired || hasEvidence) ? undefined : tools,
      // O texto só é transmitido depois da barreira de evidência. Assim uma
      // tentativa alucinada nunca chega parcialmente ao aplicativo.
      onDelta: canStream ? events.onDelta : undefined,
    });

    if (!message.tool_calls?.length) {
      if (groundingRequired && !hasEvidence && !clarificationNeeded) {
        logger.warn({ userId: auth.userId }, 'Resposta financeira sem evidência foi bloqueada');
        messages.push(groundingReminder(toolLog.length > 0));
        continue;
      }
      if (message.content) {
        parts.push(message.content);
        if (!canStream) events.onDelta?.(message.content);
      }
      return { content: parts.join('\n\n'), tool_calls: toolLog, action_ids: actionIds, references: [] };
    }

    messages.push({ role: 'assistant', content: message.content, tool_calls: message.tool_calls });
    if (message.content && canStream) parts.push(message.content);
    let roundHasEvidence = false;
    for (const call of message.tool_calls) {
      const name = call.function?.name ?? '';
      const args = call.function?.arguments ?? {};
      events.onTool?.(name);
      let payload;
      try {
        const result = await callTool(name, auth, args, context);
        if (result?.proposed && result.action) {
          actionIds.push(result.action.id);
          events.onAction?.(result.action);
        }
        if (isEvidenceTool(name)) {
          hasEvidence = true;
          roundHasEvidence = true;
        }
        payload = truncate(JSON.stringify(result));
      } catch (err) {
        // Erro vira dado para o modelo se corrigir (ex.: parâmetro inválido).
        payload = JSON.stringify({ error: err.message, details: err.details ?? null });
        if (err.details?.disponiveis) clarificationNeeded = true;
        logger.warn({ tool: name, err: err.message }, 'Tool do agente falhou');
      }
      toolLog.push({ name, arguments: args, result: payload });
      messages.push({ role: 'tool', tool_call_id: call.id, tool_name: name, content: payload });
    }
    if (groundingRequired) {
      messages.push(roundHasEvidence
        ? answerFromEvidenceReminder
        : clarificationNeeded ? clarificationReminder : groundingReminder(true));
    }
  }

  if (groundingRequired && !hasEvidence) {
    events.onDelta?.(SAFE_GROUNDING_FALLBACK);
    return { content: SAFE_GROUNDING_FALLBACK, tool_calls: toolLog, action_ids: actionIds, references: [] };
  }
  throw new LlmError('O agente excedeu o número máximo de iterações');
}
