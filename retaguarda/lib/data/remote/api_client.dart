import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import 'token_store.dart';

/// Cliente HTTP da retaguarda com JWT automático e renovação transparente do
/// access token. Usa os endpoints /retaguarda/auth/* e chaves de storage
/// próprias, sem colidir com o app.
class ApiClient {
  ApiClient({TokenStore? storage, Dio? dio})
    : _storage = storage ?? TokenStore(),
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

  static const _kAccess = 'hopecash_rtg_access_token';
  static const _kRefresh = 'hopecash_rtg_refresh_token';
  static const _kUser = 'hopecash_rtg_user';

  static const _refreshPath = '${AppConfig.retaguardaPrefix}/auth/refresh';
  static const _logoutPath = '${AppConfig.retaguardaPrefix}/auth/logout';

  final TokenStore _storage;
  final Dio dio;

  Future<void> saveSession(Map<String, dynamic> data) async {
    await _storage.write(key: _kAccess, value: data['access_token'] as String);
    await _storage.write(key: _kRefresh, value: data['refresh_token'] as String);
  }

  Future<void> saveUser(String userJson) => _storage.write(key: _kUser, value: userJson);
  Future<String?> readUser() => _storage.read(key: _kUser);
  Future<bool> hasSession() async => await _storage.read(key: _kRefresh) != null;

  Future<void> clearSession() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh != null) {
      try {
        await dio.post(_logoutPath, data: {'refresh_token': refresh});
      } catch (_) {
        /* logout local sempre acontece */
      }
    }
    await _storage.deleteAll();
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null) return false;
    try {
      final plain = Dio(
        BaseOptions(baseUrl: AppConfig.apiBaseUrl + AppConfig.apiPrefix),
      );
      final res = await plain.post(_refreshPath, data: {'refresh_token': refresh});
      await saveSession(res.data['data'] as Map<String, dynamic>);
      return true;
    } catch (_) {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
      return false;
    }
  }
}

/// Erro de API com mensagem já legível (extraída de error.message do backend).
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;

  factory ApiException.from(Object error, [String fallback = 'Falha na operação']) {
    if (error is DioException) {
      final message = error.response?.data?['error']?['message'] as String?;
      return ApiException(message ?? fallback);
    }
    return ApiException(fallback);
  }
}
