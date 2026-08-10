import { config } from '../../../config.js';
import { getFirebaseApp } from '../firebaseAdmin.js';
import { FirebasePushProvider } from './firebasePushProvider.js';
import { FakePushProvider } from './fakePushProvider.js';
import { DisabledPushProvider } from './disabledPushProvider.js';
import { RealEmailNotificationProvider } from './emailNotificationProvider.js';
import { FakeEmailNotificationProvider } from './fakeEmailNotificationProvider.js';

/**
 * Fábrica do provedor push ativo no processo:
 * - `NODE_ENV=test` → sempre `FakePushProvider` (nunca acessa o Firebase real);
 * - `FIREBASE_ENABLED=false` ou config inválida fora de produção → `DisabledPushProvider` (dry-run);
 * - caso contrário → `FirebasePushProvider` sobre uma única instância do Firebase Admin.
 */
function build() {
  if (config.isTest) return new FakePushProvider();
  if (!config.push.firebaseEnabled) return new DisabledPushProvider();
  const app = getFirebaseApp();
  if (!app) return new DisabledPushProvider();
  return new FirebasePushProvider(app);
}

let current = build();

export const getPushProvider = () => current;

/** Usado apenas pelos testes para injetar um FakePushProvider controlado. */
export function _setPushProviderForTests(provider) {
  current = provider;
}

export function _rebuildPushProviderForTests() {
  current = build();
  return current;
}

/**
 * Fábrica do provedor de e-mail: `NODE_ENV=test` → sempre
 * `FakeEmailNotificationProvider` (nunca acessa SMTP real); caso contrário →
 * `RealEmailNotificationProvider` (que por sua vez respeita `MAIL_ENABLED`).
 */
function buildEmail() {
  return config.isTest ? new FakeEmailNotificationProvider() : new RealEmailNotificationProvider();
}

let currentEmail = buildEmail();

export const getEmailNotificationProvider = () => currentEmail;

/** Usado apenas pelos testes para injetar um FakeEmailNotificationProvider controlado. */
export function _setEmailNotificationProviderForTests(provider) {
  currentEmail = provider;
}
