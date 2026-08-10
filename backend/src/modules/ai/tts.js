import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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

/**
 * Converte o markdown enxuto usado pelo chat em texto natural para leitura.
 * Links preservam o rótulo e cartões/ações continuam visuais, fora do áudio.
 */
export function normalizeSpeechText(value) {
  return String(value ?? '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}#{1,6}\s+/gm, '')
    .replace(/^\s*[-*+]\s+/gm, '')
    .replace(/^\s*\d+[.)]\s+/gm, '')
    // Bullets Unicode viram ponto final: o sintetizador pausa em vez de
    // tentar pronunciar o caractere.
    .replace(/\s*[•◦▪‣]\s*/g, '. ')
    .replace(/([.!?,;:])\s*\./g, '$1')
    .replace(/[*_~>#]/g, '')
    .replace(/R\$\s*(\d+(?:\.\d{3})*(?:,\d{1,2})?)/gi, (_, amount) => speakCurrency(amount))
    .replace(/(\d+(?:[.,]\d+)?)\s*%/g, '$1 por cento')
    .replace(/\s+/g, ' ')
    .replace(/^[.,;:\s]+/, '')
    .trim();
}

const formatContentType = {
  mp3: 'audio/mpeg',
  wav: 'audio/wav',
  opus: 'audio/ogg',
  flac: 'audio/flac',
  m4a: 'audio/mp4',
};

const isQuestion = (text) => /\?\s*["')\]]?\s*$/.test(text);

function wavVoiceInfo(bytes) {
  if (bytes.length < 44 || bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE') return null;
  let offset = 12;
  let sampleRate;
  let channels;
  let bitsPerSample;
  let dataOffset;
  while (offset + 8 <= bytes.length) {
    const id = bytes.toString('ascii', offset, offset + 4);
    const size = bytes.readUInt32LE(offset + 4);
    if (id === 'fmt ' && offset + 24 <= bytes.length) {
      channels = bytes.readUInt16LE(offset + 10);
      sampleRate = bytes.readUInt32LE(offset + 12);
      bitsPerSample = bytes.readUInt16LE(offset + 22);
    }
    if (id === 'data') {
      dataOffset = offset + 8;
      break;
    }
    if (size === 0xffffffff) break;
    offset += 8 + size + (size % 2);
  }
  if (!dataOffset || !sampleRate || channels !== 1 || bitsPerSample !== 16) return null;

  const frameBytes = channels * (bitsPerSample / 8);
  const frames = Math.floor((bytes.length - dataOffset) / frameBytes);
  const windowFrames = Math.max(1, Math.floor(sampleRate * 0.02));
  const silenceRms = 180; // aproximadamente -45 dB em PCM16
  let lastVoicedFrame = frames;
  for (let end = frames; end > 0; end -= windowFrames) {
    const start = Math.max(0, end - windowFrames);
    let sumSquares = 0;
    for (let frame = start; frame < end; frame++) {
      const sample = bytes.readInt16LE(dataOffset + frame * frameBytes);
      sumSquares += sample * sample;
    }
    if (Math.sqrt(sumSquares / (end - start)) >= silenceRms) {
      lastVoicedFrame = end;
      break;
    }
  }
  return { sampleRate, frames, lastVoicedFrame, voiceEnd: lastVoicedFrame / sampleRate };
}

function runRubberband(args) {
  return new Promise((resolve, reject) => {
    const child = spawn('rubberband', args, { stdio: ['ignore', 'ignore', 'pipe'] });
    const stderr = [];
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', (cause) => reject(new TtsError('Não foi possível iniciar o tratamento de prosódia', { cause })));
    child.on('close', (code) => {
      if (code === 0) return resolve();
      reject(new TtsError(`Tratamento de prosódia falhou (${code}): ${Buffer.concat(stderr).toString().slice(-300)}`));
    });
  });
}

async function addQuestionIntonation(wav) {
  const info = wavVoiceInfo(wav);
  if (!info || info.voiceEnd < 0.8) return null;
  const riseDuration = Math.min(0.6, info.voiceEnd * 0.3);
  const riseFrames = Math.round(riseDuration * info.sampleRate);
  const startFrame = Math.max(0, info.lastVoicedFrame - riseFrames);
  const oneThird = Math.round(riseFrames / 3);
  // A curva forte no mapa se torna uma subida natural após a suavização do
  // Rubber Band: no golden sample, −49 Hz de queda virou +34 Hz de subida.
  const pitchMap = [
    `0 0`,
    `${startFrame} 0`,
    `${startFrame + oneThird} 2`,
    `${startFrame + oneThird * 2} 7`,
    `${info.lastVoicedFrame} 9`,
    `${info.frames} 9`,
  ].join('\n');
  const directory = await mkdtemp(join(tmpdir(), 'hope-question-'));
  const inputPath = join(directory, 'input.wav');
  const mapPath = join(directory, 'pitch.map');
  const outputPath = join(directory, 'output.wav');
  try {
    await Promise.all([writeFile(inputPath, wav), writeFile(mapPath, pitchMap)]);
    await runRubberband(['-3', '-F', '-q', '--pitchmap', mapPath, inputPath, outputPath]);
    const output = await readFile(outputPath);
    return output.length ? output : null;
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function synthesize(provider, url, input) {
  const kokoro = provider === 'kokoro';
  const question = kokoro && isQuestion(input);
  let response;
  try {
    response = await fetch(`${url}${kokoro ? '/v1/audio/speech' : '/fale'}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(kokoro ? {
        model: config.tts.model, voice: config.tts.voice, input,
        response_format: question ? 'wav' : config.tts.format, speed: config.tts.speed,
      } : { texto: input }),
      signal: AbortSignal.timeout(config.tts.timeoutMs),
    });
  } catch (cause) {
    throw new TtsError(`Falha de rede ao consultar ${provider}`, { cause });
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new TtsError(`${provider} respondeu ${response.status}${detail ? `: ${detail.slice(0, 300)}` : ''}`);
  }

  let bytes = Buffer.from(await response.arrayBuffer());
  if (!bytes.length) throw new TtsError(`${provider} devolveu áudio vazio`);
  if (question) {
    const processed = await addQuestionIntonation(bytes);
    if (processed) bytes = processed;
  }
  return {
    bytes,
    contentType: question ? 'audio/wav' : response.headers?.get?.('content-type') || (kokoro
      ? formatContentType[config.tts.format] || 'audio/mpeg'
      : 'audio/wav'),
    provider,
  };
}

export const tts = {
  async speech(text) {
    const input = normalizeSpeechText(text).slice(0, config.tts.maxChars);
    if (!input) throw new TtsError('Texto vazio para síntese de voz');

    try {
      return await synthesize(config.tts.provider, config.tts.url, input);
    } catch (primaryError) {
      if (!config.tts.fallbackUrl || config.tts.fallbackProvider === config.tts.provider) throw primaryError;
      return synthesize(config.tts.fallbackProvider, config.tts.fallbackUrl, input);
    }
  },

  async health() {
    try {
      // O serviço Coqui legado não expõe /health; o OpenAPI confirma que a
      // aplicação e a rota /fale estão publicadas sem gerar áudio de teste.
      const path = config.tts.provider === 'kokoro' ? '/health' : '/openapi.json';
      const response = await fetch(`${config.tts.url}${path}`, {
        signal: AbortSignal.timeout(5_000),
      });
      return {
        ok: response.ok, profile: 'hope_velvet', provider: config.tts.provider,
        url: config.tts.url, voice: config.tts.voice, speed: config.tts.speed,
      };
    } catch (err) {
      return { ok: false, provider: config.tts.provider, url: config.tts.url, error: err.message };
    }
  },
};
