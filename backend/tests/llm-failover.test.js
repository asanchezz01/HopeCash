import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { config } from '../src/config.js';
import { llm } from '../src/modules/ai/llm.js';

const providers = () => [
  {
    id: 'groq', url: 'https://groq.test/v1', apiKey: 'groq-test',
    timeoutMs: 1_000, reasoningEffort: 'low',
    models: {
      default: 'openai/gpt-oss-120b', chat: 'openai/gpt-oss-120b', fast: 'openai/gpt-oss-20b',
    },
  },
  {
    id: 'cerebras', url: 'https://cerebras.test/v1', apiKey: 'cerebras-test',
    timeoutMs: 1_000, reasoningEffort: 'low',
    models: { default: 'gpt-oss-120b', chat: 'gpt-oss-120b', fast: 'gpt-oss-120b' },
  },
];

const okCompletion = (content = 'ok') => ({
  ok: true,
  json: async () => ({ choices: [{ message: { role: 'assistant', content } }] }),
});

const providerError = (status, detail, retryAfter = null) => ({
  ok: false,
  status,
  headers: { get: (name) => (name.toLowerCase() === 'retry-after' ? retryAfter : null) },
  text: async () => detail,
});

let originalProviders;
let originalModels;
let originalRetryMaxWaitMs;

beforeEach(() => {
  originalProviders = config.llm.providers;
  originalModels = config.llm.models;
  originalRetryMaxWaitMs = config.llm.retryMaxWaitMs;
  config.llm.providers = providers();
  config.llm.models = config.llm.providers[0].models;
  config.llm.retryMaxWaitMs = 5;
});

afterEach(() => {
  config.llm.providers = originalProviders;
  config.llm.models = originalModels;
  config.llm.retryMaxWaitMs = originalRetryMaxWaitMs;
  vi.unstubAllGlobals();
});

describe('Cliente LLM — Groq com fallback para Cerebras', () => {
  it('usa Cerebras quando o Groq continua limitado após o retry', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(providerError(429, 'Please try again in 0s.', '0'))
      .mockResolvedValueOnce(providerError(429, 'Rate limit reached', '0'))
      .mockResolvedValueOnce(okCompletion('fallback ok'));
    vi.stubGlobal('fetch', fetchMock);

    const message = await llm.chat({
      modelKey: 'chat', messages: [{ role: 'user', content: 'oi' }],
    });

    expect(message.content).toBe('fallback ok');
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls[0][0]).toContain('groq.test');
    expect(fetchMock.mock.calls[1][0]).toContain('groq.test');
    expect(fetchMock.mock.calls[2][0]).toContain('cerebras.test');
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).model).toBe('openai/gpt-oss-120b');
    expect(JSON.parse(fetchMock.mock.calls[2][1].body).model).toBe('gpt-oss-120b');
  });

  it('respeita Retry-After e tenta novamente antes do failover', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(providerError(429, 'Please try again in 0s.', '0'))
      .mockResolvedValueOnce(okCompletion('retry ok'));
    vi.stubGlobal('fetch', fetchMock);

    const message = await llm.chat({ messages: [{ role: 'user', content: 'oi' }] });

    expect(message.content).toBe('retry ok');
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls.every(([url]) => String(url).includes('groq.test'))).toBe(true);
  });

  it('faz failover após timeout sem repetir a espera no provedor primário', async () => {
    const timeout = new Error('timeout');
    timeout.name = 'TimeoutError';
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(timeout)
      .mockResolvedValueOnce(okCompletion('fallback após timeout'));
    vi.stubGlobal('fetch', fetchMock);

    const message = await llm.chat({ messages: [{ role: 'user', content: 'oi' }] });

    expect(message.content).toBe('fallback após timeout');
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[1][0]).toContain('cerebras.test');
  });

  it('envia limite explícito de saída para evitar reserva excessiva de TPM', async () => {
    const fetchMock = vi.fn().mockResolvedValue(okCompletion());
    vi.stubGlobal('fetch', fetchMock);

    await llm.chat({ messages: [{ role: 'user', content: 'oi' }], maxCompletionTokens: 321 });

    expect(JSON.parse(fetchMock.mock.calls[0][1].body).max_completion_tokens).toBe(321);
  });
});
