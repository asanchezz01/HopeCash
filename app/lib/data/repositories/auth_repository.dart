import 'dart:convert';

import 'package:dio/dio.dart';

import '../remote/api_client.dart';

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Conta de outro usuário à qual eu tenho acesso delegado.
class DelegatedAccount {
  const DelegatedAccount({
    required this.ownerId,
    required this.ownerName,
    required this.ownerEmail,
    required this.permission,
  });

  final String ownerId;
  final String ownerName;
  final String ownerEmail;

  /// read | full
  final String permission;

  bool get readOnly => permission == 'read';

  factory DelegatedAccount.fromJson(Map<String, dynamic> json) =>
      DelegatedAccount(
        ownerId: json['owner_id'] as String,
        ownerName: json['owner_name'] as String? ?? '',
        ownerEmail: json['owner_email'] as String? ?? '',
        permission: json['permission'] as String? ?? 'read',
      );

  Map<String, dynamic> toJson() => {
    'owner_id': ownerId,
    'owner_name': ownerName,
    'owner_email': ownerEmail,
    'permission': permission,
  };
}

/// Acesso que EU concedi a outro usuário (visão do titular).
class GrantedDelegation {
  const GrantedDelegation({
    required this.id,
    required this.delegateName,
    required this.delegateEmail,
    required this.permission,
  });

  final String id;
  final String delegateName;
  final String delegateEmail;

  /// read | full
  final String permission;

  factory GrantedDelegation.fromJson(Map<String, dynamic> json) =>
      GrantedDelegation(
        id: json['id'] as String,
        delegateName: json['delegate_name'] as String? ?? '',
        delegateEmail: json['delegate_email'] as String? ?? '',
        permission: json['permission'] as String? ?? 'read',
      );
}

/// Login/cadastro exigem conexão; depois disso o app opera 100% offline.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthUser?> restoreSession() async {
    if (!await _api.hasSession()) return null;
    final raw = await _api.readUser();
    if (raw == null) return null;
    return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<AuthUser> login(String email, String password) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  Future<AuthUser> register(String name, String email, String password) =>
      _authenticate('/auth/register', {
        'name': name,
        'email': email,
        'password': password,
      });

  Future<String> requestPasswordReset(String email) async {
    try {
      final res = await _api.dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      return data['message'] as String? ??
          'Se o e-mail existir, enviaremos instruções de recuperação.';
    } on DioException catch (e) {
      throw AuthException(
        _authErrorMessage(e, 'Falha ao solicitar recuperação de senha'),
      );
    }
  }

  Future<String> resetPassword({
    required String token,
    required String password,
  }) async {
    try {
      final res = await _api.dio.post(
        '/auth/reset-password',
        data: {'token': token, 'password': password},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      return data['message'] as String? ?? 'Senha redefinida com sucesso.';
    } on DioException catch (e) {
      throw AuthException(_authErrorMessage(e, 'Falha ao redefinir senha'));
    }
  }

  Future<AuthUser> updateLoginData({
    required String name,
    required String email,
    required String currentPassword,
  }) async {
    try {
      final res = await _api.dio.put(
        '/users/me/login',
        data: {
          'name': name,
          'email': email,
          'current_password': currentPassword,
        },
      );
      final user = AuthUser.fromJson(res.data['data'] as Map<String, dynamic>);
      await _api.saveUser(jsonEncode(user.toJson()));
      await _api.saveLastEmail(user.email);
      return user;
    } on DioException catch (e) {
      throw AuthException(
        _authErrorMessage(e, 'Falha ao atualizar dados de login'),
      );
    }
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String password,
  }) async {
    try {
      await _api.dio.put(
        '/users/me/password',
        data: {'current_password': currentPassword, 'password': password},
      );
      await _api.clearSession();
    } on DioException catch (e) {
      throw AuthException(_authErrorMessage(e, 'Falha ao atualizar senha'));
    }
  }

  Future<AuthUser> _authenticate(String path, Map<String, dynamic> body) async {
    try {
      final res = await _api.dio.post(path, data: body);
      final data = res.data['data'] as Map<String, dynamic>;
      await _api.saveSession(data);
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      await _api.saveUser(jsonEncode(user.toJson()));
      await _api.saveLastEmail(user.email);
      return user;
    } on DioException catch (e) {
      throw AuthException(
        _authErrorMessage(e, 'Falha de conexão com o servidor'),
      );
    }
  }

  Future<void> logout() => _api.clearSession();

  // ---------------- Tutorial de boas-vindas ----------------

  /// O usuário já viu o tutorial? A fonte da verdade é o servidor, para a
  /// marca valer em qualquer aparelho. null = não foi possível consultar
  /// (offline) — o chamador decide pelo cache local.
  Future<bool?> fetchOnboardingSeen() async {
    try {
      final res = await _api.dio.get('/users/me');
      final data = res.data['data'] as Map<String, dynamic>;
      return data['onboarding_completed_at'] != null;
    } on DioException {
      return null;
    }
  }

  /// Grava no servidor que o tutorial foi visto (concluído ou pulado).
  /// Melhor esforço: sem conexão, o cache local evita reabrir neste aparelho.
  Future<void> markOnboardingSeen() async {
    try {
      await _api.dio.put('/users/me/onboarding');
    } on DioException {
      // silencioso — gravação é conveniência entre aparelhos
    }
  }

  // ---------------- Delegação de acesso ----------------

  /// Contas que outros usuários compartilharam comigo.
  /// Falha de rede → lista vazia (login continua normal, offline-first).
  Future<List<DelegatedAccount>> listReceivedDelegations() async {
    try {
      final res = await _api.dio.get('/delegations/received');
      return [
        for (final item in (res.data['data'] as List))
          DelegatedAccount.fromJson(item as Map<String, dynamic>),
      ];
    } on DioException {
      return const [];
    }
  }

  /// Acessos que eu concedi (para gerenciar/revogar no perfil).
  Future<List<GrantedDelegation>> listGrantedDelegations() async {
    try {
      final res = await _api.dio.get('/delegations');
      return [
        for (final item in (res.data['data'] as List))
          GrantedDelegation.fromJson(item as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw AuthException(
        _authErrorMessage(e, 'Não foi possível carregar os acessos'),
      );
    }
  }

  /// Concede acesso da minha conta a outro usuário do HopeCash.
  /// Retorna a delegação criada e se o e-mail de aviso saiu de fato.
  Future<(GrantedDelegation, bool)> grantDelegation({
    required String email,
    required String permission,
  }) async {
    try {
      final res = await _api.dio.post(
        '/delegations',
        data: {'email': email, 'permission': permission},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      return (
        GrantedDelegation.fromJson(data),
        data['email_sent'] as bool? ?? false,
      );
    } on DioException catch (e) {
      throw AuthException(_authErrorMessage(e, 'Falha ao conceder acesso'));
    }
  }

  Future<void> revokeDelegation(String id) async {
    try {
      await _api.dio.delete('/delegations/$id');
    } on DioException catch (e) {
      throw AuthException(_authErrorMessage(e, 'Falha ao revogar acesso'));
    }
  }

  /// Passa a visualizar a conta de [account] (token delegado + estado salvo
  /// para sobreviver a refresh de token e reaberturas do app).
  Future<DelegatedAccount> actAs(DelegatedAccount account) async {
    try {
      final res = await _api.dio.post(
        '/delegations/act-as',
        data: {'owner_user_id': account.ownerId},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      final owner = data['owner'] as Map<String, dynamic>;
      final acting = DelegatedAccount(
        ownerId: owner['id'] as String,
        ownerName: owner['name'] as String? ?? account.ownerName,
        ownerEmail: owner['email'] as String? ?? account.ownerEmail,
        permission: data['permission'] as String? ?? account.permission,
      );
      await _api.saveAccessToken(data['access_token'] as String);
      await _api.saveActing(jsonEncode(acting.toJson()));
      return acting;
    } on DioException catch (e) {
      throw AuthException(
        _authErrorMessage(e, 'Falha ao acessar a conta compartilhada'),
      );
    }
  }

  /// Volta para a minha própria conta.
  Future<void> actAsSelf() => _api.resetToOwnAccount();

  /// Conta delegada ativa salva no dispositivo (para restaurar no boot).
  Future<DelegatedAccount?> restoreActing() async {
    final raw = await _api.readActing();
    if (raw == null) return null;
    try {
      return DelegatedAccount.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

String _authErrorMessage(DioException error, String fallback) {
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
    case DioExceptionType.badCertificate:
      return 'Certificado HTTPS do servidor não foi aceito pelo Android.';
    default:
      break;
  }
  return fallback;
}
