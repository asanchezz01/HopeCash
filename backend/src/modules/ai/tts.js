import { config } from '../../config.js';

export class TtsError extends Error {
  constructor(message, options = {}) {
    super(message, options);
    this.name = 'TtsError';
  }
}

function speakCurrency(raw) {
  const normalized = raw.replace(/\./g, '').replace(',', '.');
  const value = Number(normalized);
  if (!Number.isFinite(value)) return `R$ ${raw}`;
  const centsTotal = Math.round(value * 100);
  const reais = Math.floor(centsTotal / 100);
  const centavos = centsTotal % 100;
  const parts = [];
  if (reais) parts.push(`${reais} ${reais === 1 ? 'real' : 'reais'}`);
  if (centavos) parts.push(`${centavos} ${centavos === 1 ? 'centavo' : 'centavos'}`);
  return parts.join(' e ') || 'zero reais';
}

/** Converte o markdown enxuto do chat em texto natural para leitura. */
export function normalizeSpeechText(value) {
  return String(value ?? '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}#{1,6}\s+/gm, '')
    .replace(/^\s*[-*+]\s+/gm, '')
    .replace(/^\s*\d+[.)]\s+/gm, '')
    .replace(/\s*[•◦▪‣]\s*/g, '. ')
    .replace(/([.!?,;:])\s*\./g, '$1')
    .replace(/[*_~>#]/g, '')
    .replace(/R\$\s*(\d+(?:\.\d{3})*(?:,\d{1,2})?)/gi, (_, amount) => speakCurrency(amount))
    .replace(/(\d+(?:[.,]\d+)?)\s*%/g, '$1 por cento')
    .replace(/\s+/g, ' ')
    .replace(/^[.,;:\s]+/, '')
    .trim();
}

const escapeXml = (value) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&apos;');

function buildSsml(input) {
  const rate = Math.round((config.tts.speed - 1) * 100);
  const rateValue = `${rate >= 0 ? '+' : ''}${rate}%`;
  return `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="pt-BR"><voice name="${escapeXml(config.tts.voice)}"><prosody rate="${rateValue}">${escapeXml(input)}</prosody></voice></speak>`;
}

async function azureSpeech(input) {
  if (!config.tts.apiKey || !config.tts.region) {
    throw new TtsError('Azure Speech não configurado: defina AZURE_SPEECH_KEY e AZURE_SPEECH_REGION');
  }

  const wav = config.tts.format === 'wav';
  let response;
  try {
    response = await fetch(config.tts.url, {
      method: 'POST',
      headers: {
        'Ocp-Apim-Subscription-Key': config.tts.apiKey,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': wav
          ? 'riff-24khz-16bit-mono-pcm'
          : 'audio-24khz-160kbitrate-mono-mp3',
        'User-Agent': 'HopeCash',
      },
      body: buildSsml(input),
      signal: AbortSignal.timeout(config.tts.timeoutMs),
    });
  } catch (cause) {
    throw new TtsError('Falha de rede ao consultar Azure Speech', { cause });
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new TtsError(`Azure Speech respondeu ${response.status}${detail ? `: ${detail.slice(0, 300)}` : ''}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (!bytes.length) throw new TtsError('Azure Speech devolveu áudio vazio');
  return { bytes, contentType: wav ? 'audio/wav' : 'audio/mpeg', provider: 'azure' };
}

export const tts = {
  async speech(text) {
    if (!config.tts.enabled) throw new TtsError('Voz da Hope desabilitada neste ambiente');
    const input = normalizeSpeechText(text).slice(0, config.tts.maxChars);
    if (!input) throw new TtsError('Texto vazio para síntese de voz');
    if (config.tts.provider !== 'azure') throw new TtsError(`Provedor TTS não suportado: ${config.tts.provider}`);
    return azureSpeech(input);
  },

  async health() {
    if (!config.tts.enabled) return { ok: false, disabled: true, reason: 'TTS_DISABLED' };
    if (!config.tts.apiKey || !config.tts.region) {
      return { ok: false, provider: 'azure', reason: 'AZURE_SPEECH_NOT_CONFIGURED' };
    }
    try {
      const response = await fetch(config.tts.voicesUrl, {
        headers: { 'Ocp-Apim-Subscription-Key': config.tts.apiKey },
        signal: AbortSignal.timeout(5_000),
      });
      if (!response.ok) return { ok: false, provider: 'azure', region: config.tts.region, status: response.status };
      const voices = await response.json();
      return {
        ok: Array.isArray(voices) && voices.some((voice) => voice.ShortName === config.tts.voice),
        profile: 'hope_azure', provider: 'azure', region: config.tts.region,
        voice: config.tts.voice, speed: config.tts.speed,
      };
    } catch (err) {
      return { ok: false, provider: 'azure', region: config.tts.region, error: err.message };
    }
  },
};
