import '../../core/config/app_config.dart';
import '../models/app_user.dart';
import '../remote/api_client.dart';

/// Resultado do reset de senha de um usuário do app.
class PasswordResetResult {
  const PasswordResetResult({
    required this.message,
    required this.email,
    required this.emailSent,
    this.code,
  });

  final String message;
  final String email;
  final bool emailSent;

  /// Código provisório — presente apenas quando o envio de e-mail está
  /// desabilitado no backend (MAIL_ENABLED=false).
  final String? code;
}

/// Gestão dos usuários do APP (tabela `users`) a partir da retaguarda.
class AppUsersRepository {
  AppUsersRepository(this._api);

  final ApiClient _api;
  static const _base = '${AppConfig.retaguardaPrefix}/app-users';

  Future<RetaguardaStats> stats({String? userId}) async {
    try {
      final res = await _api.dio.get(
        '${AppConfig.retaguardaPrefix}/stats',
        queryParameters: {'user_id': ?userId},
      );
      return RetaguardaStats.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar indicadores');
    }
  }

  /// Todos os usuários disponíveis no filtro do dashboard. A API limita cada
  /// página a 200 registros, então percorremos as páginas até completar a lista.
  Future<List<AppUser>> listAll() async {
    const limit = 200;
    var offset = 0;
    final users = <AppUser>[];
    while (true) {
      final page = await list(limit: limit, offset: offset);
      users.addAll(page.users);
      offset += page.users.length;
      if (page.users.isEmpty || users.length >= page.total) return users;
    }
  }

  Future<AppUserPage> list({
    String? search,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _api.dio.get(
        _base,
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'status': ?status,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = res.data['data'] as List<dynamic>;
      final meta = res.data['meta'] as Map<String, dynamic>? ?? const {};
      return AppUserPage(
        users: data
            .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (meta['total'] as num?)?.toInt() ?? data.length,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar usuários do app');
    }
  }

  Future<AppUser> setStatus(String id, String status) async {
    try {
      final res = await _api.dio.patch(
        '$_base/$id/status',
        data: {'status': status},
      );
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao alterar o status do usuário');
    }
  }

  Future<PasswordResetResult> resetPassword(String id) async {
    try {
      final res = await _api.dio.post('$_base/$id/reset-password');
      final data = res.data['data'] as Map<String, dynamic>;
      return PasswordResetResult(
        message: data['message'] as String? ?? 'Senha redefinida.',
        email: data['email'] as String? ?? '',
        emailSent: data['email_sent'] as bool? ?? false,
        code: data['code'] as String?,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao redefinir a senha');
    }
  }
}
