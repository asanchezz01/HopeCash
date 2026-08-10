import 'dotenv/config';

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),
  jwt: {
    secret: process.env.JWT_SECRET || 'dev-secret-do-not-use-in-production',
    accessTtl: process.env.JWT_ACCESS_TTL || '15m',
    refreshTtlDays: Number(process.env.JWT_REFRESH_TTL_DAYS || 30),
  },
  logLevel: process.env.LOG_LEVEL || 'info',
  ollama: {
    url: process.env.OLLAMA_URL,
    timeoutMs: Number(process.env.OLLAMA_TIMEOUT_MS || 30_000),
    // Modelo por tarefa: chat conversacional × extração/classificação (fast).
    // Sem as variáveis específicas, tudo cai no OLLAMA_MODEL.
    models: {
      default: process.env.OLLAMA_MODEL || 'qwen3.6:35b',
      chat: process.env.OLLAMA_MODEL_CHAT || process.env.OLLAMA_MODEL || 'qwen3.6:35b',
      fast: process.env.OLLAMA_MODEL_FAST || process.env.OLLAMA_MODEL || 'qwen3.6:35b',
    },
  },
  tts: {
    // "Hope Velvet": voz feminina pt-BR, calorosa e elegante. O Coqui
    // existente permanece como contingência sem expor dados fora da LAN.
    provider: process.env.TTS_PROVIDER || 'kokoro',
    url: process.env.TTS_URL,
    fallbackProvider: process.env.TTS_FALLBACK_PROVIDER || 'coqui',
    fallbackUrl: process.env.TTS_FALLBACK_URL,
    model: process.env.TTS_MODEL || 'kokoro',
    // 2 partes da dicção pt-BR + 1 parte de um timbre feminino mais claro.
    voice: process.env.TTS_VOICE || 'pf_dora(2)+af_bella(1)',
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
