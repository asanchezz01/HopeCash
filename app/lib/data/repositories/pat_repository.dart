import 'package:dio/dio.dart';

import '../remote/api_client.dart';

class PatException implements Exception {
  const PatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Personal Access Token — usado para conectar hosts MCP (Claude Code, Claude
/// Desktop, etc.) aos dados do usuário. `mcp_read` só consulta; `mcp_write`
/// também propõe lançamentos (que ainda exigem confirmação em duas fases).
class PersonalAccessToken {
  const PersonalAccessToken({
    required this.id,
    required this.name,
    required this.kind,
    required this.scopes,
    required this.last4,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// mcp_read | mcp_write | push_transactions
  final String kind;
  final List<String> scopes;
  final String last4;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime createdAt;

  bool get isMcp => kind == 'mcp_read' || kind == 'mcp_write';
  bool get canWrite => scopes.contains('write');

  /// Tokens emitidos pelo fluxo OAuth nascem com o nome `OAuth: <host>` (ver
  /// `oauth.service.js`) — é o que separa "app que se conectou sozinho" de
  /// "token que eu gerei e colei em algum lugar".
  static const _oauthPrefix = 'OAuth: ';
  bool get isOAuth => name.startsWith(_oauthPrefix);
  String get displayName =>
      isOAuth ? name.substring(_oauthPrefix.length) : name;

  factory PersonalAccessToken.fromJson(Map<String, dynamic> json) =>
      PersonalAccessToken(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String? ?? 'push_transactions',
        scopes: (json['scopes'] as List? ?? const [])
            .map((s) => s as String)
            .toList(),
        last4: json['last4'] as String? ?? '',
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        lastUsedAt: json['last_used_at'] != null
            ? DateTime.parse(json['last_used_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Devolvido apenas na criação — é a única vez que o token em texto claro
/// fica disponível; depois disso o backend guarda só o hash.
class CreatedPersonalAccessToken {
  const CreatedPersonalAccessToken({
    required this.id,
    required this.name,
    required this.kind,
    required this.token,
  });

  final String id;
  final String name;
  final String kind;
  final String token;

  factory CreatedPersonalAccessToken.fromJson(Map<String, dynamic> json) =>
      CreatedPersonalAccessToken(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        token: json['token'] as String,
      );
}

class PatRepository {
  PatRepository(this._api);

  final ApiClient _api;

  Future<List<PersonalAccessToken>> list() async {
    try {
      final res = await _api.dio.get('/pat');
      return [
        for (final item in (res.data['data'] as List))
          PersonalAccessToken.fromJson(item as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw PatException(_patErrorMessage(e, 'Não foi possível carregar seus tokens'));
    }
  }

  Future<CreatedPersonalAccessToken> create({
    required String name,
    required String kind,
    int? expiresInDays,
  }) async {
    try {
      final res = await _api.dio.post('/pat', data: {
        'name': name,
        'kind': kind,
        'expires_in_days': ?expiresInDays,
      });
      return CreatedPersonalAccessToken.fromJson(
        res.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw PatException(_patErrorMessage(e, 'Falha ao gerar o token'));
    }
  }

  Future<void> revoke(String id) async {
    try {
      await _api.dio.delete('/pat/$id');
    } on DioException catch (e) {
      throw PatException(_patErrorMessage(e, 'Falha ao revogar o token'));
    }
  }
}

String _patErrorMessage(DioException error, String fallback) {
  final data = error.response?.data;
  if (data is Map<String, dynamic>) {
    final errorData = data['error'];
    if (errorData is Map<String, dynamic>) {
      final message = errorData['message'];
      if (message is String && message.isNotEmpty) return message;
    }
  }
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
      return 'Servidor não respondeu a tempo. Verifique sua conexão e tente novamente.';
    case DioExceptionType.receiveTimeout:
      return 'O servidor demorou para responder. Tente novamente.';
    case DioExceptionType.connectionError:
      return 'Não foi possível conectar à API (${error.requestOptions.uri.host}). Verifique a internet do aparelho.';
    default:
      return fallback;
  }
}
