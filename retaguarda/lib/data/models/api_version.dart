/// Identidade do build do backend (app/API), exposta em GET /api/v1/version.
class ApiVersion {
  const ApiVersion({
    required this.version,
    required this.ref,
    this.builtAt,
  });

  final String version;
  final String ref;
  final String? builtAt;

  /// Rotulo curto: "v0.1.0 · a1b2c3d".
  String get label => 'v$version · $ref';

  factory ApiVersion.fromJson(Map<String, dynamic> json) => ApiVersion(
    version: json['version'] as String? ?? '?',
    ref: json['ref'] as String? ?? 'local',
    builtAt: json['built_at'] as String?,
  );
}
