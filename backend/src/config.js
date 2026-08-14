import 'dotenv/config';
import fs from 'node:fs';

const aiEnabled = process.env.AI_ENABLED !== 'false';

const secret = (value, file) => {
  if (value?.trim()) return value.trim();
  // Testes nunca devem buscar credenciais reais no filesystem da máquina.
  if (process.env.NODE_ENV === 'test') return '';
  if (!file?.trim()) return '';
  try { return fs.readFileSync(file.trim(), 'utf8').trim(); } catch { return ''; }
};

const cerebras = {
  id: 'cerebras',
  url: (process.env.CEREBRAS_BASE_URL || 'https://api.cerebras.ai/v1').replace(/\/+$/, ''),
  apiKey: secret(process.env.CEREBRAS_API_KEY, process.env.CEREBRAS_API_KEY_FILE),
  timeoutMs: Number(process.env.CEREBRAS_TIMEOUT_MS || 30_000),
  reasoningEffort: process.env.CEREBRAS_REASONING_EFFORT || 'low',
  models: {
    default: process.env.CEREBRAS_MODEL || 'gpt-oss-120b',
    chat: process.env.CEREBRAS_MODEL_CHAT || process.env.CEREBRAS_MODEL || 'gpt-oss-120b',
    fast: process.env.CEREBRAS_MODEL_FAST || process.env.CEREBRAS_MODEL || 'gpt-oss-120b',
  },
};

const groq = {
  id: 'groq',
  url: (process.env.GROQ_BASE_URL || 'https://api.groq.com/openai/v1').replace(/\/+$/, ''),
  apiKey: secret(process.env.GROQ_API_KEY, process.env.GROQ_API_KEY_FILE),
  timeoutMs: Number(process.env.GROQ_TIMEOUT_MS || 30_000),
  reasoningEffort: process.env.GROQ_REASONING_EFFORT || 'low',
  models: {
    default: process.env.GROQ_MODEL || 'openai/gpt-oss-120b',
    chat: process.env.GROQ_MODEL_CHAT || process.env.GROQ_MODEL || 'openai/gpt-oss-120b',
    fast: process.env.GROQ_MODEL_FAST || 'openai/gpt-oss-20b',
  },
};

const requestedProvider = (process.env.AI_PROVIDER || 'groq').toLowerCase();
const providerOrder = requestedProvider === 'cerebras' ? [cerebras, groq] : [groq, cerebras];
const primaryProvider = providerOrder.find((provider) => provider.apiKey) ?? providerOrder[0];

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),
  jwt: {
    secret: process.env.JWT_SECRET || 'dev-secret-do-not-use-in-production',
    accessTtl: process.env.JWT_ACCESS_TTL || '15m',
    refreshTtlDays: Number(process.env.JWT_REFRESH_TTL_DAYS || 30),
  },
  logLevel: process.env.LOG_LEVEL || 'info',
  ai: {
    // Chave operacional para ambientes que devem manter a Hope totalmente
    // inativa. O bloqueio também é aplicado nos clientes LLM e TTS.
    enabled: aiEnabled,
    provider: requestedProvider,
  },
  llm: {
    // A lista é ordenada pelo provedor primário. Provedores sem chave são
    // ignorados em runtime; assim uma instalação só com Groq continua válida.
    providers: providerOrder,
    models: primaryProvider.models,
    maxCompletionTokens: Number(process.env.LLM_MAX_COMPLETION_TOKENS || 1_200),
    retryMaxWaitMs: Number(process.env.LLM_RETRY_MAX_WAIT_MS || 15_000),
  },
  tts: {
    enabled: aiEnabled && process.env.TTS_ENABLED !== 'false',
    provider: process.env.TTS_PROVIDER || 'azure',
    apiKey: process.env.AZURE_SPEECH_KEY || '',
    region: process.env.AZURE_SPEECH_REGION || 'brazilsouth',
    endpoint: (process.env.AZURE_SPEECH_ENDPOINT || 'https://brazilsouth.api.cognitive.microsoft.com/').replace(/\/+$/, ''),
    url: process.env.AZURE_SPEECH_TTS_URL
      || `https://${process.env.AZURE_SPEECH_REGION || 'brazilsouth'}.tts.speech.microsoft.com/cognitiveservices/v1`,
    voicesUrl: process.env.AZURE_SPEECH_VOICES_URL
      || `https://${process.env.AZURE_SPEECH_REGION || 'brazilsouth'}.tts.speech.microsoft.com/cognitiveservices/voices/list`,
    voice: process.env.AZURE_SPEECH_VOICE || 'pt-BR-ThalitaMultilingualNeural',
    format: process.env.TTS_FORMAT || 'mp3',
    speed: Number(process.env.TTS_SPEED || 0.96),
    timeoutMs: Number(process.env.TTS_TIMEOUT_MS || 45_000),
    maxChars: Number(process.env.TTS_MAX_CHARS || 4000),
  },
  // Superusuário da retaguarda, provisionado na inicialização a partir do .env.
  superuser: {
    email: (process.env.SUPERUSER_EMAIL || 'admin@hopecash.app').toLowerCase(),
    password: process.env.SUPERUSER_PASSWORD || 'newhope',
    name: process.env.SUPERUSER_NAME || 'Super Admin',
  },
  // Envio de e-mail (SMTP). Com MAIL_ENABLED=false nada é enviado — o conteúdo
  // é apenas registrado no log (útil em dev e em ambientes sem SMTP).
  mail: {
    enabled: process.env.MAIL_ENABLED === 'true',
    host: process.env.MAIL_SMTP || 'smtp.gmail.com',
    port: Number(process.env.MAIL_PORT || 587),
    user: process.env.MAIL_USER || '',
    pass: process.env.MAIL_PASS || '',
    from: process.env.MAIL_FROM || process.env.MAIL_USER || 'no-reply@hopecash.app',
    useTls: process.env.MAIL_USE_TLS !== 'false',
  },
  support: {
    emailTo:
      process.env.SUPPORT_EMAIL_TO ||
      process.env.MAIL_FROM ||
      process.env.MAIL_USER ||
      'suporte@hopecash.app',
    subjectPrefix: process.env.SUPPORT_EMAIL_SUBJECT_PREFIX || '[HopeCash Suporte]',
    rateLimitMax: Number(process.env.SUPPORT_RATE_LIMIT_MAX || 5),
    rateLimitWindowMs: Number(process.env.SUPPORT_RATE_LIMIT_WINDOW_MINUTES || 15) * 60_000,
  },
  // URL pública deste backend — usada nos metadados de descoberta OAuth do
  // MCP (issuer + authorization/token/registration endpoints, RFC 8414).
  publicUrl: (process.env.API_BASE_URL || 'http://localhost:3000').replace(/\/+$/, ''),
  corsOrigins: (process.env.CORS_ALLOWED_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  // Notificações push (Firebase Cloud Messaging). Com FIREBASE_ENABLED=false o
  // provedor cai em modo dry-run — nada é enviado, mas a API funciona normalmente.
  push: {
    firebaseEnabled: process.env.FIREBASE_ENABLED === 'true',
    firebaseProjectId: process.env.FIREBASE_PROJECT_ID || '',
    firebaseClientEmail: process.env.FIREBASE_CLIENT_EMAIL || '',
    firebasePrivateKeyBase64: process.env.FIREBASE_PRIVATE_KEY_BASE64 || '',
    schedulerEnabled: process.env.PUSH_SCHEDULER_ENABLED === 'true',
    schedulerIntervalMs: Number(process.env.PUSH_SCHEDULER_INTERVAL_MS || 60_000),
    dueReminderDays: Number(process.env.PUSH_DUE_REMINDER_DAYS || 3),
    defaultTimezone: process.env.PUSH_DEFAULT_TIMEZONE || 'America/Sao_Paulo',
    // URL pública do app Web/PWA — usada só para montar o botão de ação do
    // e-mail de fallback (quem não tem nenhum dispositivo push ativo). Sem
    // isso definido, o e-mail sai sem botão (só o texto informativo).
    emailAppUrl: (process.env.PUSH_EMAIL_APP_URL || '').replace(/\/+$/, ''),
  },
  isTest: (process.env.NODE_ENV || '') === 'test',
  isProd: (process.env.NODE_ENV || '') === 'production',
};
