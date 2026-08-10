import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { normalizeSpeechText } from '../src/modules/ai/tts.js';
import { auth, makeApp, registerUser } from './helpers.js';

let api;
let token;

beforeAll(async () => {
  api = await makeApp();
  token = (await registerUser(api)).access_token;
});

afterEach(() => vi.unstubAllGlobals());

describe('Voz da Hope — TTS privado', () => {
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

  it('usa o perfil feminino Hope Velvet no Kokoro', async () => {
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
    expect(res.headers['x-hope-voice']).toBe('hope-velvet');
    expect(res.headers['x-tts-provider']).toBe('kokoro');
    expect(Buffer.compare(res.body, Buffer.from(audio))).toBe(0);
    const [url, options] = fetchMock.mock.calls[0];
    expect(new URL(String(url)).pathname).toBe('/v1/audio/speech');
    expect(JSON.parse(options.body)).toEqual({
      model: 'kokoro', voice: 'pf_dora(2)+af_bella(1)', input: 'Seu saldo é 10 reais.',
      response_format: 'mp3', speed: 0.96,
    });
  });

  it('cai no Coqui local quando a voz principal está indisponível', async () => {
    const audio = Uint8Array.from([82, 73, 70, 70, 4, 5, 6]);
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new Error('ECONNREFUSED'))
      .mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'audio/wav' }),
        arrayBuffer: async () => audio.buffer,
      });
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.post('/api/v1/ai/speech').set(auth(token))
      .send({ text: 'Teste da contingência' });

    expect(res.status).toBe(200);
    expect(res.headers['x-tts-provider']).toBe('coqui');
    expect(new URL(String(fetchMock.mock.calls[1][0])).pathname).toBe('/fale');
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({ texto: 'Teste da contingência' });
  });

  it('solicita WAV para aplicar a curva interrogativa', async () => {
    const audio = Uint8Array.from([82, 73, 70, 70, 1, 2, 3]);
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      headers: new Headers({ 'content-type': 'audio/wav' }),
      arrayBuffer: async () => audio.buffer,
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await api.post('/api/v1/ai/speech').set(auth(token))
      .send({ text: 'Você gostaria que eu detalhasse por categoria?' });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('audio/wav');
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).response_format).toBe('wav');
  });

  it('responde 503 quando a voz local está indisponível', async () => {
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
