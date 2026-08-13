import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { config } from '../src/config.js';
import { normalizeSpeechText } from '../src/modules/ai/tts.js';
import { auth, makeApp, registerUser } from './helpers.js';

let api;
let token;

beforeAll(async () => {
  api = await makeApp();
  token = (await registerUser(api)).access_token;
  config.tts.apiKey = 'test-azure-key';
  config.tts.region = 'brazilsouth';
});

afterEach(() => {
  config.tts.enabled = true;
  vi.unstubAllGlobals();
});

describe('Voz da Hope — Azure Speech', () => {
  it('não consulta o TTS quando a voz está desabilitada', async () => {
    config.tts.enabled = false;
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.post('/api/v1/ai/speech').set(auth(token))
      .send({ text: 'Teste' });

    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('TTS_UNAVAILABLE');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('remove markdown antes da síntese', () => {
    expect(normalizeSpeechText('## Saldo\n- **Total:** [R$ 10](https://local)'))
      .toBe('Saldo Total: 10 reais');
  });

  it('converte bullets Unicode em pausa', () => {
    expect(normalizeSpeechText('Seu orçamento:\n• Moradia: R$ 100,00\n• Saúde: R$ 50,00'))
      .toBe('Seu orçamento: Moradia: 100 reais. Saúde: 50 reais');
    expect(normalizeSpeechText('Total: R$ 10,00.\n•\tMercado'))
      .toBe('Total: 10 reais. Mercado');
  });

  it('torna valores financeiros naturais para pt-BR', () => {
    expect(normalizeSpeechText('Saldo: **R$ 5.000,20**; rendimento de 12,5%.'))
      .toBe('Saldo: 5000 reais e 20 centavos; rendimento de 12,5 por cento.');
    expect(normalizeSpeechText('R$ 1,01 e R$ 0,50'))
      .toBe('1 real e 1 centavo e 50 centavos');
  });

  it('usa SSML e a voz neural brasileira configurada no Azure', async () => {
    const audio = Uint8Array.from([73, 68, 51, 4, 5, 6]);
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      headers: new Headers({ 'content-type': 'audio/mpeg' }),
      arrayBuffer: async () => audio.buffer,
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.post('/api/v1/ai/speech').set(auth(token))
      .send({ text: '**Seu saldo** é R$ 10,00.' });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('audio/mpeg');
    expect(res.headers['x-hope-voice']).toBe('pt-BR-ThalitaMultilingualNeural');
    expect(res.headers['x-tts-provider']).toBe('azure');
    expect(Buffer.compare(res.body, Buffer.from(audio))).toBe(0);
    const [url, options] = fetchMock.mock.calls[0];
    expect(new URL(String(url)).pathname).toBe('/cognitiveservices/v1');
    expect(options.headers['Ocp-Apim-Subscription-Key']).toBeTruthy();
    expect(options.headers['X-Microsoft-OutputFormat']).toContain('mp3');
    expect(options.body).toContain('<voice name="pt-BR-ThalitaMultilingualNeural">');
    expect(options.body).toContain('Seu saldo é 10 reais.');
  });

  it('responde 503 quando o Azure Speech está indisponível', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));
    const res = await api.post('/api/v1/ai/speech').set(auth(token))
      .send({ text: 'Teste de voz' });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('TTS_UNAVAILABLE');
  });

  it('exige autenticação', async () => {
    const res = await api.post('/api/v1/ai/speech').send({ text: 'Teste' });
    expect(res.status).toBe(401);
  });
});
