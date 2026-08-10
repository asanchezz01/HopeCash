import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { config } from '../../config.js';
import { logger } from '../../logger.js';

/**
 * Decodifica FIREBASE_PRIVATE_KEY_BASE64 (o campo `private_key` da credencial
 * de serviço, em Base64 UTF-8) e valida o formato PEM. Nunca loga o conteúdo.
 */
export function decodePrivateKeyBase64(base64) {
  const decoded = Buffer.from(String(base64 ?? ''), 'base64').toString('utf8');
  const looksLikePem = decoded.includes('-----BEGIN PRIVATE KEY-----')
    && decoded.includes('-----END PRIVATE KEY-----');
  if (!looksLikePem) {
    throw new Error('FIREBASE_PRIVATE_KEY_BASE64 não decodifica para uma chave PEM válida');
  }
  return decoded;
}

let cachedApp;
let cachedAppAttempted = false;

/**
 * Inicializa (uma única vez) o Firebase Admin a partir das variáveis de
 * ambiente. Retorna `null` quando o push está desabilitado ou mal configurado
 * fora de produção — em produção, configuração inválida com push habilitado
 * derruba o processo de propósito (falha clara, não silenciosa).
 */
export function getFirebaseApp() {
  if (!config.push.firebaseEnabled) return null;
  if (cachedAppAttempted) return cachedApp ?? null;
  cachedAppAttempted = true;

  const existing = getApps();
  if (existing.length) {
    cachedApp = existing[0];
    return cachedApp;
  }

  const { firebaseProjectId: projectId, firebaseClientEmail: clientEmail, firebasePrivateKeyBase64 } = config.push;
  if (!projectId || !clientEmail || !firebasePrivateKeyBase64) {
    const message = 'FIREBASE_ENABLED=true mas FIREBASE_PROJECT_ID/FIREBASE_CLIENT_EMAIL/FIREBASE_PRIVATE_KEY_BASE64 estão ausentes';
    if (config.isProd) throw new Error(message);
    logger.error(message);
    return null;
  }

  try {
    const privateKey = decodePrivateKeyBase64(firebasePrivateKeyBase64);
    cachedApp = initializeApp({ credential: cert({ projectId, clientEmail, privateKey }) });
    logger.info({ projectId }, 'Firebase Admin inicializado');
    return cachedApp;
  } catch (err) {
    if (config.isProd) throw err;
    logger.error({ err: err.message }, 'Falha ao inicializar o Firebase Admin — push seguirá desabilitado');
    return null;
  }
}

/** Usado apenas pelos testes para resetar o cache entre cenários. */
export function _resetFirebaseAppCacheForTests() {
  cachedApp = undefined;
  cachedAppAttempted = false;
}
