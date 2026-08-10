import { getMessaging } from 'firebase-admin/messaging';
import { isPermanentErrorCode, sanitizeErrorMessage } from './errorClassification.js';

/**
 * Provedor de produção: envia via Firebase Cloud Messaging HTTP v1.
 * `data` deve conter apenas strings (exigência do FCM).
 */
export class FirebasePushProvider {
  constructor(app) {
    this.messaging = getMessaging(app);
  }

  async send({ token, title, body, data = {}, deepLink }) {
    const stringData = Object.fromEntries(
      Object.entries({ ...data, ...(deepLink ? { deep_link: deepLink } : {}) })
        .filter(([, v]) => v != null)
        .map(([k, v]) => [k, String(v)]),
    );

    try {
      const messageId = await this.messaging.send({
        token,
        notification: { title, body },
        data: stringData,
        android: { priority: 'high', notification: { channelId: 'hopecash_default' } },
        apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } },
        webpush: { headers: { Urgency: 'high' }, fcmOptions: deepLink ? { link: deepLink } : undefined },
      });
      return { ok: true, messageId, permanent: false };
    } catch (err) {
      const code = err?.code || 'messaging/unknown-error';
      return {
        ok: false,
        errorCode: code,
        permanent: isPermanentErrorCode(code),
        error: sanitizeErrorMessage(code, err?.message),
      };
    }
  }
}
