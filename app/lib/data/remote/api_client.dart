import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/app_config.dart';

/// Cliente HTTP com JWT automático e renovação transparente do access token.
/// Tokens ficam no armazenamento seguro da plataforma (Keychain/Keystore).
class ApiClient {
  ApiClient({FlutterSecureStorage? storage, Dio? dio})
    : _storage = storage ?? const FlutterSecureStorage(),
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl + AppConfig.apiPrefix,
              headers: const {
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache',
              },
            ),
          ) {
    this.dio.options.connectTimeout = const Duration(seconds: 10);
    this.dio.options.receiveTimeout = const Duration(seconds: 30);
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _kAccess);
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          // 401 em rota autenticada → tenta renovar uma vez e repete a chamada.
          final isAuthRoute = error.requestOptions.path.contains('/auth/');
          if (error.response?.statusCode == 401 && !isAuthRoute) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              try {
                final retried = await this.dio.fetch(error.requestOptions);
                return handler.resolve(retried);
              } catch (_) {}
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _kAccess = 'hopecash_access_token';
  static const _kRefresh = 'hopecash_refresh_token';
  static const _kUser = 'hopecash_user';
  static const _kActing = 'hopecash_acting';
  static const _kLastEmail = 'hopecash_last_email';

  final FlutterSecureStorage _storage;
  final Dio dio;

  Future<void> saveSession(Map<String, dynamic> data) async {
    await _storage.write(key: _kAccess, value: data['access_token'] as String);
    await _storage.write(
      key: _kRefresh,
      value: data['refresh_token'] as String,
    );
  }

  Future<void> saveUser(String userJson) =>
      _storage.write(key: _kUser, value: userJson);
  Future<String?> readUser() => _storage.read(key: _kUser);
  Future<bool> hasSession() async =>
      await _storage.read(key: _kRefresh) != null;

  /// Último e-mail autenticado — sobrevive ao logout para pré-preencher a
  /// tela de login ("salvar o usuário" no aparelho).
  Future<void> saveLastEmail(String email) =>
      _storage.write(key: _kLastEmail, value: email);
  Future<String?> readLastEmail() => _storage.read(key: _kLastEmail);

  // ---------------- Conta delegada ("visualizando como") ----------------

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _kAccess, value: token);
  Future<void> saveActing(String actingJson) =>
      _storage.write(key: _kActing, value: actingJson);
  Future<String?> readActing() => _storage.read(key: _kActing);
  Future<void> clearActing() => _storage.delete(key: _kActing);

  /// Sai da conta delegada: volta a operar com o token da própria conta.
  Future<bool> resetToOwnAccount() async {
    await clearActing();
    return _tryRefresh();
  }

  Future<void> clearSession() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh != null) {
      try {
        await dio.post('/auth/logout', data: {'refresh_token': refresh});
      } catch (_) {
        /* logout local sempre acontece */
      }
    }
    // Mantém apenas o último e-mail, para pré-preencher o próximo login.
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kActing);
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null) return false;
    try {
      // Dio "limpo" para não entrar em loop no interceptor.
      final plain = Dio(
        BaseOptions(baseUrl: AppConfig.apiBaseUrl + AppConfig.apiPrefix),
      );
      final res = await plain.post(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      await saveSession(res.data['data'] as Map<String, dynamic>);
      // Sessão delegada: o refresh devolve o token da própria conta, então
      // troca de novo pelo token de acesso à conta delegada.
      final actingRaw = await _storage.read(key: _kActing);
      if (actingRaw != null) {
        try {
          final acting = jsonDecode(actingRaw) as Map<String, dynamic>;
          final access = await _storage.read(key: _kAccess);
          final actRes = await plain.post(
            '/delegations/act-as',
            data: {'owner_user_id': acting['owner_id']},
            options: Options(headers: {'Authorization': 'Bearer $access'}),
          );
          await _storage.write(
            key: _kAccess,
            value: actRes.data['data']['access_token'] as String,
          );
        } catch (_) {
          // Acesso revogado: segue com a própria conta.
          await _storage.delete(key: _kActing);
        }
      }
      return true;
    } catch (_) {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
      return false;
    }
  }
}
