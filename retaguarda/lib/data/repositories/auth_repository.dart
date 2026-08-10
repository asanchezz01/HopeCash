import 'dart:convert';

import '../../core/config/app_config.dart';
import '../models/retaguarda_user.dart';
import '../remote/api_client.dart';

/// Autenticação da retaguarda contra o backend compartilhado do HopeCash.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  static const _base = AppConfig.retaguardaPrefix;

  Future<RetaguardaUser?> restoreSession() async {
    if (!await _api.hasSession()) return null;
    final raw = await _api.readUser();
    if (raw == null) return null;
    return RetaguardaUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<RetaguardaUser> login(String email, String password) async {
    try {
      final res = await _api.dio.post('$_base/auth/login', data: {
        'email': email,
        'password': password,
        'device_name': 'Retaguarda Web',
      });
      final data = res.data['data'] as Map<String, dynamic>;
      await _api.saveSession(data);
      final user = RetaguardaUser.fromJson(data['user'] as Map<String, dynamic>);
      await _api.saveUser(jsonEncode(user.toJson()));
      return user;
    } catch (e) {
      throw ApiException.from(e, 'Falha ao entrar. Verifique suas credenciais.');
    }
  }

  /// Troca a senha do próprio usuário logado (invalida a sessão atual).
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String password,
  }) async {
    try {
      await _api.dio.put('$_base/users/me/password', data: {
        'current_password': currentPassword,
        'password': password,
      });
      await _api.clearSession();
    } catch (e) {
      throw ApiException.from(e, 'Falha ao atualizar a senha');
    }
  }

  Future<void> logout() => _api.clearSession();
}
