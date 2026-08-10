import 'package:dio/dio.dart';

import '../models/push_preferences.dart';
import '../remote/api_client.dart';

class PushNotificationsException implements Exception {
  const PushNotificationsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Endpoints de push do app: registro/baixa de dispositivo e preferências.
/// Falhas de rede nunca devem travar o fluxo principal do app — quem chama
/// decide se ignora silenciosamente (registro em background) ou mostra erro
/// (tela de preferências, ação explícita do usuário).
class PushNotificationsRepository {
  PushNotificationsRepository(this._api);

  final ApiClient _api;

  Future<void> registerDevice({
    required String token,
    required String platform,
    String? installId,
    String? appVersion,
    String? locale,
    String? timezone,
  }) async {
    try {
      await _api.dio.post(
        '/push/devices',
        data: {
          'token': token,
          'platform': platform,
          'install_id': ?installId,
          'app_version': ?appVersion,
          'locale': ?locale,
          'timezone': ?timezone,
        },
      );
    } on DioException catch (e) {
      throw PushNotificationsException(
        _errorMessage(e, 'Falha ao registrar o dispositivo para notificações'),
      );
    }
  }

  Future<void> deactivateDevice(String token) async {
    try {
      await _api.dio.post('/push/devices/deactivate', data: {'token': token});
    } on DioException catch (e) {
      throw PushNotificationsException(
        _errorMessage(e, 'Falha ao desativar notificações neste dispositivo'),
      );
    }
  }

  Future<PushPreferences> getPreferences() async {
    try {
      final res = await _api.dio.get('/push/preferences');
      return PushPreferences.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PushNotificationsException(
        _errorMessage(e, 'Falha ao carregar preferências de notificação'),
      );
    }
  }

  Future<PushPreferences> updatePreferences(Map<String, dynamic> patch) async {
    try {
      final res = await _api.dio.put('/push/preferences', data: patch);
      return PushPreferences.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PushNotificationsException(
        _errorMessage(e, 'Falha ao salvar preferências de notificação'),
      );
    }
  }
}

String _errorMessage(DioException error, String fallback) {
  final data = error.response?.data;
  if (data is Map<String, dynamic>) {
    final errorData = data['error'];
    if (errorData is Map<String, dynamic>) {
      final message = errorData['message'];
      if (message is String && message.isNotEmpty) return message;
    }
  }
  return fallback;
}
