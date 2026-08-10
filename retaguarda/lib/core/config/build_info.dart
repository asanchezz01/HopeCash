/// Identidade do build da retaguarda, injetada em tempo de compilacao pelo
/// Dockerfile (--dart-define). Serve para confirmar, no rodape do dashboard,
/// qual commit esta efetivamente publicado neste container.
class BuildInfo {
  BuildInfo._();

  static const version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static const ref = String.fromEnvironment('BUILD_REF', defaultValue: 'local');
  static const buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');

  /// Rotulo curto: "v0.1.0 · a1b2c3d".
  static String get label => 'v$version · $ref';
}
