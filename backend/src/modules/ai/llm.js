import crypto from 'node:crypto';
import { config } from '../../config.js';
import { logger } from '../../logger.js';

/** Erro tipado do provedor LLM. `transient` indica que vale re-tentar. */
export class LlmError extends Error {
  constructor(message, {
    status, transient = false, failover = transient, retryAfterMs = 0, provider, cause,
  } = {}) {
    super(message, { cause });
    this.name = 'LlmError';
    this.status = status;
    this.transient = transient;
    this.failover = failover;
    this.retryAfterMs = retryAfterMs;
    this.provider = provider;
  }
}

const RETRY_BACKOFF_MS = 500;
const MODEL_KEYS = ['default', 'chat', 'fast'];

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

const configuredProviders = () => config.llm.providers.filter((provider) => provider.apiKey);

const parseRetryAfterMs = (res, detail) => {
  const header = res.headers?.get?.('retry-after') || res.headers?.get?.('x-ratelimit-reset-tokens');
  if (header) {
    const seconds = Number.parseFloat(header);
    if (Number.isFinite(seconds)) return Math.max(0, Math.ceil(seconds * 1_000));
    const date = Date.parse(header);
    if (Number.isFinite(date)) return Math.max(0, date - Date.now());
  }
  const match = detail.match(/try again in\s+([0-9.]+)s/i);
  return match ? Math.ceil(Number(match[1]) * 1_000) : 0;
};

const modelKeyFor = (model, modelKey) => {
  if (MODEL_KEYS.includes(modelKey)) return modelKey;
  return MODEL_KEYS.find((key) => config.llm.models[key] === model) ?? null;
};

const providerModel = (provider, model, modelKey) => {
  const key = modelKeyFor(model, modelKey);
  return key ? provider.models[key] : model || provider.models.default;
};

async function request(provider, path, { method = 'POST', body, timeoutMs } = {}) {
  if (!config.ai.enabled) throw new LlmError('Hope desabilitada neste ambiente', { status: 503 });
  if (!provider?.apiKey) throw new LlmError(`Chave da ${provider?.id || 'LLM'} não configurada`, { status: 503 });
  let res;
  try {
    res = await fetch(`${provider.url}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${provider.apiKey}`,
        ...(body ? { 'content-type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeoutMs ?? provider.timeoutMs),
    });
  } catch (cause) {
    const isTimeout = cause.name === 'TimeoutError' || cause.name === 'AbortError';
    throw new LlmError(
      isTimeout ? `Tempo esgotado ao consultar ${provider.id}` : `Falha de rede ao consultar ${provider.id}`,
      {
        transient: !isTimeout, failover: true, provider: provider.id, cause,
      },
    );
  }
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    const transient = res.status === 429 || res.status >= 500;
    const failover = transient || [401, 402, 403, 404, 408, 409].includes(res.status);
    throw new LlmError(`${provider.id} respondeu ${res.status}${detail ? `: ${detail.slice(0, 500)}` : ''}`, {
      status: res.status,
      transient,
      failover,
      retryAfterMs: parseRetryAfterMs(res, detail),
      provider: provider.id,
    });
  }
  return res;
}

async function withRetry(provider, fn) {
  try { return await fn(); } catch (err) {
    if (!(err instanceof LlmError) || !err.transient) throw err;
    const waitMs = Math.min(err.retryAfterMs || RETRY_BACKOFF_MS, config.llm.retryMaxWaitMs);
    logger.warn({ provider: provider.id, waitMs, err: err.message }, 'LLM falhou; re-tentando uma vez');
    await new Promise((resolve) => setTimeout(resolve, waitMs));
    return fn();
  }
}

async function withFailover(fn) {
  const providers = configuredProviders();
  if (!providers.length) {
    throw new LlmError('Nenhum provedor LLM possui chave configurada', { status: 503 });
  }
  let lastError;
  for (let index = 0; index < providers.length; index += 1) {
    const provider = providers[index];
    try {
      return await withRetry(provider, () => fn(provider));
    } catch (err) {
      lastError = err;
      const fallback = providers[index + 1];
      if (!(err instanceof LlmError) || !err.failover || !fallback) throw err;
      logger.warn({ provider: provider.id, fallback: fallback.id, err: err.message }, 'Ativando failover do LLM');
    }
  }
  throw lastError;
}

const completionBody = ({ provider, model, modelKey, messages, format, tools, temperature, stream, maxCompletionTokens }) => ({
  model: providerModel(provider, model, modelKey),
  messages: providerMessages(messages),
  stream,
  temperature,
  reasoning_effort: provider.reasoningEffort,
  reasoning_format: 'hidden',
  max_completion_tokens: maxCompletionTokens ?? config.llm.maxCompletionTokens,
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

  async chat({
    model = config.llm.models.default, modelKey = 'default', messages, format, tools,
    temperature = 0, timeoutMs, maxCompletionTokens,
  } = {}) {
    return withFailover(async (provider) => {
      const res = await request(provider, '/chat/completions', {
        timeoutMs,
        body: completionBody({ provider, model, modelKey, messages, format, tools, temperature, stream: false, maxCompletionTokens }),
      });
      const data = await res.json();
      return normalizeMessage(data.choices?.[0]?.message);
    });
  },

  async chatJson({ format, ...rest }) {
    const message = await this.chat({ ...rest, format });
    try { return JSON.parse(message.content ?? ''); } catch (cause) {
      throw new LlmError('Resposta do LLM fora do formato JSON esperado', { cause });
    }
  },

  async *chatStream({
    model = config.llm.models.chat, modelKey = 'chat', messages, tools,
    temperature = 0.3, timeoutMs, maxCompletionTokens,
  } = {}) {
    const res = await withFailover((provider) => request(provider, '/chat/completions', {
      timeoutMs,
      body: completionBody({ provider, model, modelKey, messages, tools, temperature, stream: true, maxCompletionTokens }),
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
    throw new LlmError('Os provedores configurados não oferecem embeddings neste contrato', { status: 501 });
  },

  async health() {
    if (!config.ai.enabled) return { ok: false, disabled: true, reason: 'AI_DISABLED' };
    const providers = configuredProviders();
    if (!providers.length) return { ok: false, error: 'Nenhum provedor LLM possui chave configurada', providers: [] };
    const results = await Promise.all(providers.map(async (provider) => {
      try {
        const res = await request(provider, '/models', { method: 'GET', timeoutMs: 5_000 });
        const data = await res.json();
        const installedModels = (data.data ?? []).map((model) => ({ name: model.id, active: model.active !== false }));
        const available = new Set(installedModels.filter((model) => model.active).map((model) => model.name));
        return {
          ok: [...new Set(Object.values(provider.models))].every((model) => available.has(model)),
          provider: provider.id,
          configured_models: provider.models,
          installed_models: installedModels,
        };
      } catch (err) {
        return { ok: false, provider: provider.id, configured_models: provider.models, error: err.message };
      }
    }));
    const active = results.find((result) => result.ok) ?? results[0];
    return {
      ...active,
      ok: results.some((result) => result.ok),
      provider: active.provider,
      primary_provider: providers[0].id,
      failover_available: results.slice(1).some((result) => result.ok),
      providers: results,
    };
  },
};
