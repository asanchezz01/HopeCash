import crypto from 'node:crypto';

/**
 * Provedor de testes — nunca acessa o Firebase real. O comportamento por
 * token é configurável (`setBehavior`) para simular sucesso, falha
 * permanente ou temporária; por padrão qualquer envio é bem-sucedido.
 * Também aceita convenções de prefixo no token, úteis quando o teste só
 * precisa de um token descartável: `invalid-*` → falha permanente,
 * `tempfail-*` → falha temporária.
 */
export class FakePushProvider {
  constructor() {
    this.sent = [];
    this.behaviors = new Map(); // token -> 'ok' | 'permanent' | 'temporary'
  }

  setBehavior(token, behavior) {
    this.behaviors.set(token, behavior);
  }

  async send({ token, title, body, data = {}, deepLink }) {
    this.sent.push({ token, title, body, data, deepLink });

    const behavior = this.behaviors.get(token)
      ?? (token.startsWith('invalid-') ? 'permanent' : token.startsWith('tempfail-') ? 'temporary' : 'ok');

    if (behavior === 'permanent') {
      return {
        ok: false,
        permanent: true,
        errorCode: 'messaging/registration-token-not-registered',
        error: 'Token não registrado (simulado em teste)',
      };
    }
    if (behavior === 'temporary') {
      return {
        ok: false,
        permanent: false,
        errorCode: 'messaging/internal-error',
        error: 'Falha temporária simulada em teste',
      };
    }
    return { ok: true, messageId: `fake-${crypto.randomUUID()}`, permanent: false };
  }
}
