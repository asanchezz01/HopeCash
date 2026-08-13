import crypto from 'node:crypto';
import { config } from '../../config.js';
import { logger } from '../../logger.js';

/** Erro tipado do provedor LLM. `transient` indica que vale re-tentar. */
export class LlmError extends Error {
  constructor(message, { status, transient = false, cause } = {}) {
    super(message, { cause });
    this.name = 'LlmError';
    this.status = status;
    this.transient = transient;
  }
}

const RETRY_BACKOFF_MS = 500;

const parseArguments = (value) => {
  if (typeof value !== 'string') return value ?? {};
  try { return JSON.parse(value); } catch { return {}; }
};

const normalizeToolCall = (call, index = 0) => ({
  id: call.id || `call_${index}_${crypto.randomUUID()}`,
  type: 'function',
  function: {
    name: call.function?.name ?? '',
    arguments: parseArguments(call.function?.arguments),
  },
});

const normalizeMessage = (message = {}) => ({
  role: message.role || 'assistant',
  content: message.content ?? '',
  tool_calls: (message.tool_calls ?? []).map(normalizeToolCall),
});

const providerMessages = (messages) => messages.map((message) => {
  if (message.role === 'assistant' && message.tool_calls?.length) {
    return {
      role: 'assistant',
      content: message.content || null,
      tool_calls: message.tool_calls.map((call, index) => ({
        id: call.id || `call_${index}`,
        type: 'function',
        function: {
          name: call.function?.name ?? '',
          arguments: typeof call.function?.arguments === 'string'
            ? call.function.arguments
            : JSON.stringify(call.function?.arguments ?? {}),
        },
      })),
    };
  }
  if (message.role === 'tool') {
    return {
      role: 'tool',
      tool_call_id: message.tool_call_id,
      content: message.content ?? '',
    };
  }
  return { role: message.role, content: message.content ?? '' };
});

async function request(path, { method = 'POST', body, timeoutMs = config.llm.timeoutMs } = {}) {
  if (!config.ai.enabled) throw new LlmError('Hope desabilitada neste ambiente', { status: 503 });
  if (config.ai.provider !== 'groq') throw new LlmError(`Provedor LLM não suportado: ${config.ai.provider}`, { status: 503 });
  if (!config.llm.apiKey) throw new LlmError('GROQ_API_KEY não configurada', { status: 503 });
  let res;
  try {
    res = await fetch(`${config.llm.url}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${config.llm.apiKey}`,
        ...(body ? { 'content-type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (cause) {
    const isTimeout = cause.name === 'TimeoutError' || cause.name === 'AbortError';
    throw new LlmError(isTimeout ? 'Tempo esgotado ao consultar o Groq' : 'Falha de rede ao consultar o Groq', {
      transient: !isTimeout, cause,
    });
  }
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new LlmError(`Groq respondeu ${res.status}${detail ? `: ${detail.slice(0, 500)}` : ''}`, {
      status: res.status,
      transient: res.status === 429 || res.status >= 500,
    });
  }
  return res;
}

async function withRetry(fn) {
  try { return await fn(); } catch (err) {
    if (!(err instanceof LlmError) || !err.transient) throw err;
    logger.warn({ err: err.message }, 'Groq falhou; re-tentando uma vez');
    await new Promise((resolve) => setTimeout(resolve, RETRY_BACKOFF_MS));
    return fn();
  }
}

const completionBody = ({ model, messages, format, tools, temperature, stream }) => ({
  model,
  messages: providerMessages(messages),
  stream,
  temperature,
  reasoning_effort: config.llm.reasoningEffort,
  reasoning_format: 'hidden',
  ...(tools ? { tools, tool_choice: 'auto' } : {}),
  ...(format ? {
    response_format: {
      type: 'json_schema',
      json_schema: { name: 'hope_structured_output', strict: true, schema: format },
    },
  } : {}),
});

async function* sseData(body) {
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });
    let newline;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (line.startsWith('data:')) yield line.slice(5).trim();
    }
  }
  const line = buffer.trim();
  if (line.startsWith('data:')) yield line.slice(5).trim();
}

export const llm = {
  models: config.llm.models,

  async chat({ model = config.llm.models.default, messages, format, tools, temperature = 0, timeoutMs } = {}) {
    return withRetry(async () => {
      const res = await request('/chat/completions', {
        timeoutMs,
        body: completionBody({ model, messages, format, tools, temperature, stream: false }),
      });
      const data = await res.json();
      return normalizeMessage(data.choices?.[0]?.message);
    });
  },

  async chatJson({ format, ...rest }) {
    const message = await this.chat({ ...rest, format });
    try { return JSON.parse(message.content ?? ''); } catch (cause) {
      throw new LlmError('Resposta do Groq fora do formato JSON esperado', { cause });
    }
  },

  async *chatStream({ model = config.llm.models.chat, messages, tools, temperature = 0.3, timeoutMs } = {}) {
    const res = await withRetry(() => request('/chat/completions', {
      timeoutMs,
      body: completionBody({ model, messages, tools, temperature, stream: true }),
    }));
    const toolCalls = new Map();
    let finished = false;
    for await (const raw of sseData(res.body)) {
      if (raw === '[DONE]') break;
      const data = JSON.parse(raw);
      const choice = data.choices?.[0] ?? {};
      const delta = choice.delta ?? {};
      if (delta.content) yield { message: { role: 'assistant', content: delta.content }, done: false };
      for (const fragment of delta.tool_calls ?? []) {
        const index = fragment.index ?? 0;
        const current = toolCalls.get(index) ?? { id: '', type: 'function', function: { name: '', arguments: '' } };
        if (fragment.id) current.id = fragment.id;
        if (fragment.function?.name) current.function.name += fragment.function.name;
        if (fragment.function?.arguments) current.function.arguments += fragment.function.arguments;
        toolCalls.set(index, current);
      }
      if (choice.finish_reason) finished = true;
    }
    yield {
      message: {
        role: 'assistant', content: '',
        tool_calls: [...toolCalls.values()].map(normalizeToolCall),
      },
      done: true,
      finished,
    };
  },

  async embed() {
    throw new LlmError('O provedor Groq não oferece embeddings neste contrato', { status: 501 });
  },

  async health() {
    if (!config.ai.enabled) return { ok: false, disabled: true, reason: 'AI_DISABLED' };
    try {
      const res = await request('/models', { method: 'GET', timeoutMs: 5_000 });
      const data = await res.json();
      const available = new Set((data.data ?? []).filter((m) => m.active !== false).map((m) => m.id));
      const configured = Object.values(config.llm.models);
      return {
        ok: configured.every((model) => available.has(model)),
        provider: 'groq',
        configured_models: config.llm.models,
        installed_models: (data.data ?? []).map((model) => ({ name: model.id, active: model.active !== false })),
      };
    } catch (err) {
      return { ok: false, provider: 'groq', configured_models: config.llm.models, error: err.message };
    }
  },
};
