/// Configuração de ambiente do HopeCash.
class AppConfig {
  AppConfig._();

  /// URL base da API.
  /// - Web/desktop/iOS simulator: http://localhost:3000
  /// - Emulador Android: http://10.0.2.2:3000
  /// Sobrescreva em build com: --dart-define=API_BASE_URL=https://api.hopecash.app
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const apiPrefix = '/api/v1';

  /// Intervalo da sincronização periódica em segundo plano.
  static const syncInterval = Duration(seconds: 45);

  // ---------------- Firebase Cloud Messaging (push) ----------------
  // Projeto Firebase "HopeCash" já configurado no Console — estes valores
  // apenas identificam o app público (não são segredo) e são necessários só
  // no Web/PWA, onde não existe um google-services.json/GoogleService-Info.plist
  // nativo. Em Android/iOS o Firebase lê a configuração dos arquivos nativos
  // automaticamente. Preencha no build com --dart-define (veja docs/FLUTTERFIRE.md).
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'hopecash',
  );
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '71481307234',
  );
  static const firebaseWebAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:71481307234:web:c284cb740f37342f9a613b',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'hopecash.firebasestorage.app',
  );
  static const firebaseWebAuthDomain = String.fromEnvironment(
    'FIREBASE_WEB_AUTH_DOMAIN',
    defaultValue: 'hopecash.firebaseapp.com',
  );
  // Sem valor padrão de propósito: são específicos do projeto e precisam vir
  // do Firebase Console (Configurações do projeto → Geral → app Web, e
  // Cloud Messaging → Configuração da Web → Certificados push da Web).
  static const firebaseWebApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  /// Web/PWA precisam de FirebaseOptions explícitas (sem arquivo nativo).
  static bool get firebaseWebConfigured =>
      firebaseWebApiKey.isNotEmpty && firebaseVapidKey.isNotEmpty;
}
