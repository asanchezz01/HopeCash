/// Estado do servidor de IA (Ollama), consultado em GET /retaguarda/ai/health.
class AiHealth {
  const AiHealth({
    required this.ok,
    required this.url,
    this.version,
    this.error,
    this.configuredModels = const {},
    this.installedModels = const [],
  });

  final bool ok;
  final String url;
  final String? version;
  final String? error;

  /// Modelos configurados no backend por tarefa (default | chat | fast).
  final Map<String, String> configuredModels;
  final List<AiModel> installedModels;

  factory AiHealth.fromJson(Map<String, dynamic> json) => AiHealth(
    ok: json['ok'] as bool? ?? false,
    url: json['url'] as String? ?? '',
    version: json['version'] as String?,
    error: json['error'] as String?,
    configuredModels: (json['configured_models'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String)),
    installedModels: (json['installed_models'] as List<dynamic>? ?? [])
        .map((m) => AiModel.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  /// Um modelo configurado está instalado? Tolera a ausência da tag
  /// (ex.: configurado "phi4:14b" ou "phi4" casam com "phi4:14b").
  bool isInstalled(String configured) => installedModels.any(
    (m) => m.name == configured || m.name.startsWith('$configured:'),
  );

  /// Modelos configurados que não existem no servidor (erro de configuração).
  List<String> get missingModels =>
      configuredModels.values.toSet().where((m) => !isInstalled(m)).toList();
}

class AiModel {
  const AiModel({required this.name, this.parameterSize});

  final String name;
  final String? parameterSize;

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
    name: json['name'] as String? ?? '',
    parameterSize: json['parameter_size'] as String?,
  );

  String get label =>
      parameterSize == null ? name : '$name ($parameterSize)';
}
