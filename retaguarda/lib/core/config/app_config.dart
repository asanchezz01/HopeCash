/// Configuração de ambiente da Retaguarda HopeCash.
class AppConfig {
  AppConfig._();

  /// URL base da API — o mesmo backend do app.
  /// Sobrescreva no build com: --dart-define=API_BASE_URL=https://api.hopecash.app
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const apiPrefix = '/api/v1';

  /// Prefixo das rotas exclusivas da retaguarda.
  static const retaguardaPrefix = '/retaguarda';
}
