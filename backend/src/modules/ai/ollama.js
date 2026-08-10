import { config } from '../../config.js';
import { logger } from '../../logger.js';

/**
 * Cliente único do Ollama — toda chamada de IA do backend passa por aqui.
 * Timeouts por requisição, uma re-tentativa para falhas transientes e erros
 * tipados que as rotas convertem em AI_UNAVAILABLE.
 */

/** Erro tipado do cliente. `transient` indica que vale re-tentar. */
export class OllamaError extends Error {
  constructor(message, { status, transient = false, cause } = {}) {
    super(message, { cause });
    this.name = 'OllamaError';
    this.status = status;
    this.transient = transient;
  }
}

const RETRY_BACKOFF_MS = 300;

async function request(path, { method = 'POST', body, timeoutMs = config.ollama.timeoutMs } = {}) {
  let res;
  try {
    res = await fetch(`${config.ollama.url}${path}`, {
      method,
      headers: body ? { 'content-type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    // Timeout não é transiente: re-tentar dobraria a espera percebida no app.
    const isTimeout = err.name === 'TimeoutError' || err.name === 'AbortError';
    throw new OllamaError(
      isTimeout ? 'Tempo esgotado ao consultar o Ollama' : 'Falha de rede ao consultar o Ollama',
      { transient: !isTimeout, cause: err },
    );
  }
  if (!res.ok) {
    const body = typeof res.text === 'function' ? await res.text().catch(() => '') : '';
    const detail = body ? `: ${body.slice(0, 300)}` : '';
    throw new OllamaError(`Ollama respondeu ${res.status}${detail}`, {
      status: res.status,
      transient: res.status >= 500,
    });
  }
  return res;
}

async function withRetry(fn) {
  try {
    return await fn();
  } catch (err) {
    if (!(err instanceof OllamaError) || !err.transient) throw err;
    logger.warn({ err: err.message }, 'Ollama falhou; re-tentando uma vez');
    await new Promise((resolve) => setTimeout(resolve, RETRY_BACKOFF_MS));
    return fn();
  }
}

export const ollama = {
  /** Modelos por tarefa (default | chat | fast), resolvidos do .env. */
  models: config.ollama.models,

  /**
   * Chat sem streaming. Devolve a mensagem do assistente completa —
   * `content` e, quando `tools` for usado, `tool_calls`.
   */
  async chat({ model = config.ollama.models.default, messages, format, tools, think, temperature = 0, timeoutMs } = {}) {
    return withRetry(async () => {
      const res = await request('/api/chat', {
        timeoutMs,
        body: {
          model,
          messages,
          stream: false,
          ...(format ? { format } : {}),
          ...(tools ? { tools } : {}),
          ...(think !== undefined ? { think } : {}),
          options: { temperature },
        },
      });
      const data = await res.json();
      return data.message ?? { role: 'assistant', content: '' };
    });
  },

  /**
   * Chat com structured outputs: impõe `format` (JSON Schema) e devolve o
   * objeto já parseado. Uso típico: extração/classificação com temperature 0.
   */
  async chatJson({ format, think = false, ...rest }) {
    const message = await this.chat({ ...rest, format, think });
    const content = message.content ?? '';
    // Templates defeituosos vazam tokens especiais após o JSON (ex.: o gemma4
    // emite "<|tool_response>" em vez de parar) — extrai o primeiro valor
    // JSON completo antes de parsear.
    const start = content.search(/[[{]/);
    const end = Math.max(content.lastIndexOf('}'), content.lastIndexOf(']'));
    const candidate = start >= 0 && end > start ? content.slice(start, end + 1) : content;
    try {
      return JSON.parse(candidate);
    } catch (cause) {
      throw new OllamaError('Resposta do Ollama fora do formato JSON esperado', { cause });
    }
  },

  /**
   * Chat com streaming: gera cada chunk NDJSON já parseado (`message.content`
   * parcial; o último chunk vem com `done: true`).
   */
  async *chatStream({ model = config.ollama.models.chat, messages, tools, think, temperature = 0.4, timeoutMs } = {}) {
    const res = await withRetry(() => request('/api/chat', {
      timeoutMs,
      body: {
        model,
        messages,
        stream: true,
        ...(tools ? { tools } : {}),
        ...(think !== undefined ? { think } : {}),
        options: { temperature },
      },
    }));
    const decoder = new TextDecoder();
    let buffer = '';
    for await (const chunk of res.body) {
      buffer += decoder.decode(chunk, { stream: true });
      let newline;
      while ((newline = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (line) yield JSON.parse(line);
      }
    }
    if (buffer.trim()) yield JSON.parse(buffer);
  },

  /** Embeddings (/api/embed). Aceita string ou lista; devolve a lista de vetores. */
  async embed({ input, model = config.ollama.models.fast } = {}) {
    return withRetry(async () => {
      const res = await request('/api/embed', { body: { model, input } });
      const data = await res.json();
      return data.embeddings ?? [];
    });
  },

  /**
   * Estado do servidor e modelos instalados. Nunca lança — indisponibilidade
   * vira `{ ok: false }` para a UI esconder os recursos de IA com graça.
   */
  async health() {
    try {
      const [versionRes, tagsRes] = await Promise.all([
        request('/api/version', { method: 'GET', timeoutMs: 5_000 }),
        request('/api/tags', { method: 'GET', timeoutMs: 5_000 }),
      ]);
      const version = await versionRes.json();
      const tags = await tagsRes.json();
      return {
        ok: true,
        url: config.ollama.url,
        version: version.version ?? null,
        configured_models: config.ollama.models,
        installed_models: (tags.models ?? []).map((m) => ({
          name: m.name,
          size_bytes: m.size ?? null,
          parameter_size: m.details?.parameter_size ?? null,
          family: m.details?.family ?? null,
        })),
      };
    } catch (err) {
      return { ok: false, url: config.ollama.url, configured_models: config.ollama.models, error: err.message };
    }
  },
};
