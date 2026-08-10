/**
 * Provedor de e-mail de testes — nunca acessa SMTP/rede real. Comportamento
 * por destinatário configurável (`setBehavior`), como o `FakePushProvider`;
 * por padrão qualquer envio é bem-sucedido.
 */
export class FakeEmailNotificationProvider {
  constructor() {
    this.sent = [];
    this.behaviors = new Map(); // to -> 'ok' | 'temporary'
  }

  setBehavior(to, behavior) {
    this.behaviors.set(to, behavior);
  }

  async send({ to, subject, html, text }) {
    this.sent.push({ to, subject, html, text });
    const behavior = this.behaviors.get(to) ?? 'ok';
    if (behavior === 'temporary') {
      return { ok: false, error: 'Falha de SMTP simulada em teste', permanent: false };
    }
    return { ok: true };
  }
}
