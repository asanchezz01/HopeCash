import { logger } from '../../../logger.js';

/** Provedor dry-run — usado quando FIREBASE_ENABLED=false ou a config é inválida fora de produção. */
export class DisabledPushProvider {
  async send({ token }) {
    logger.debug({ tokenPreview: `${token.slice(0, 6)}…` }, 'Push desabilitado (dry-run) — envio ignorado');
    return { ok: true, messageId: null, permanent: false, dryRun: true };
  }
}
