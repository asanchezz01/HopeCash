import crypto from 'node:crypto';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

// Este arquivo nunca importa `helpers.js`/`db` — só testa a inicialização do
// Firebase Admin isoladamente, manipulando variáveis de ambiente e
// reimportando os módulos a cada cenário. Nenhum destes testes acessa a rede
// (initializeApp/cert só constroem objetos em memória) nem usa credenciais reais.

const FAKE_PEM = crypto.generateKeyPairSync('rsa', {
  modulusLength: 512,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
}).privateKey;
const FAKE_PEM_BASE64 = Buffer.from(FAKE_PEM, 'utf8').toString('base64');

async function freshFirebaseAdmin() {
  const mod = await import('../src/modules/push/firebaseAdmin.js');
  return mod;
}

beforeEach(() => {
  vi.resetModules();
});

afterEach(async () => {
  vi.unstubAllEnvs();
  // O registro de apps do firebase-admin é um singleton real do pacote (não
  // resetado por vi.resetModules) — precisa ser limpo manualmente entre
  // cenários para um teste não "herdar" o app inicializado pelo anterior.
  const { getApps, deleteApp } = await import('firebase-admin/app');
  await Promise.all(getApps().map((app) => deleteApp(app).catch(() => {})));
  vi.resetModules();
});

describe('decodePrivateKeyBase64', () => {
  it('decodifica uma chave PEM válida em Base64', async () => {
    const { decodePrivateKeyBase64 } = await freshFirebaseAdmin();
    const decoded = decodePrivateKeyBase64(FAKE_PEM_BASE64);
    expect(decoded).toContain('-----BEGIN PRIVATE KEY-----');
    expect(decoded).toContain('-----END PRIVATE KEY-----');
  });

  it('rejeita Base64 que não decodifica para PEM', async () => {
    const { decodePrivateKeyBase64 } = await freshFirebaseAdmin();
    const bogus = Buffer.from('isso não é uma chave', 'utf8').toString('base64');
    expect(() => decodePrivateKeyBase64(bogus)).toThrow();
  });
});

describe('getFirebaseApp', () => {
  it('com FIREBASE_ENABLED=false retorna null sem tentar inicializar nada', async () => {
    vi.stubEnv('FIREBASE_ENABLED', 'false');
    const { getFirebaseApp } = await freshFirebaseAdmin();
    expect(getFirebaseApp()).toBeNull();
  });

  it('habilitado mas sem credenciais, fora de produção: loga e retorna null (não derruba o processo)', async () => {
    vi.stubEnv('NODE_ENV', 'test');
    vi.stubEnv('FIREBASE_ENABLED', 'true');
    vi.stubEnv('FIREBASE_PROJECT_ID', '');
    vi.stubEnv('FIREBASE_CLIENT_EMAIL', '');
    vi.stubEnv('FIREBASE_PRIVATE_KEY_BASE64', '');
    const { getFirebaseApp } = await freshFirebaseAdmin();
    expect(getFirebaseApp()).toBeNull();
  });

  it('habilitado com credenciais válidas: inicializa uma única instância (singleton)', async () => {
    vi.stubEnv('NODE_ENV', 'test');
    vi.stubEnv('FIREBASE_ENABLED', 'true');
    vi.stubEnv('FIREBASE_PROJECT_ID', 'test-project');
    vi.stubEnv('FIREBASE_CLIENT_EMAIL', 'test@test-project.iam.gserviceaccount.com');
    vi.stubEnv('FIREBASE_PRIVATE_KEY_BASE64', FAKE_PEM_BASE64);
    const { getFirebaseApp } = await freshFirebaseAdmin();
    const app1 = getFirebaseApp();
    const app2 = getFirebaseApp();
    expect(app1).toBeTruthy();
    expect(app1).toBe(app2); // mesma instância — nunca inicializa duas vezes
  });

  it('em produção, habilitado e mal configurado: falha de forma clara (lança)', async () => {
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('FIREBASE_ENABLED', 'true');
    vi.stubEnv('FIREBASE_PROJECT_ID', '');
    vi.stubEnv('FIREBASE_CLIENT_EMAIL', '');
    vi.stubEnv('FIREBASE_PRIVATE_KEY_BASE64', '');
    const { getFirebaseApp } = await freshFirebaseAdmin();
    expect(() => getFirebaseApp()).toThrow();
  });

  it('em produção com credenciais válidas: inicializa normalmente', async () => {
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('FIREBASE_ENABLED', 'true');
    vi.stubEnv('FIREBASE_PROJECT_ID', 'test-project');
    vi.stubEnv('FIREBASE_CLIENT_EMAIL', 'test@test-project.iam.gserviceaccount.com');
    vi.stubEnv('FIREBASE_PRIVATE_KEY_BASE64', FAKE_PEM_BASE64);
    const { getFirebaseApp } = await freshFirebaseAdmin();
    expect(getFirebaseApp()).toBeTruthy();
  });
});
