/**
 * Erros do FCM que indicam que o token nunca mais vai funcionar (app
 * desinstalado, token revogado, formato inválido, projeto Firebase errado).
 * Qualquer outro erro é tratado como temporário (timeout, indisponibilidade,
 * limitação de taxa) e entra no fluxo de retry com backoff.
 */
export const PERMANENT_ERROR_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  'messaging/invalid-argument',
  'messaging/mismatched-credential',
  'messaging/invalid-recipient',
  'messaging/sender-id-mismatch',
]);

export function isPermanentErrorCode(code) {
  return PERMANENT_ERROR_CODES.has(code);
}

/** Sanitiza uma mensagem de erro para armazenamento — nunca inclui o token. */
export function sanitizeErrorMessage(code, message) {
  const safe = String(message ?? code ?? 'erro desconhecido').slice(0, 280);
  return safe.replace(/[A-Za-z0-9_-]{100,}/g, '<token omitido>');
}
