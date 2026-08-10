import '../../core/config/app_config.dart';
import '../models/retaguarda_user.dart';
import '../remote/api_client.dart';

/// Gestão dos usuários da própria retaguarda.
class RetaguardaUsersRepository {
  RetaguardaUsersRepository(this._api);

  final ApiClient _api;
  static const _base = '${AppConfig.retaguardaPrefix}/users';

  Future<List<RetaguardaUser>> list() async {
    try {
      final res = await _api.dio.get(_base);
      final data = res.data['data'] as List<dynamic>;
      return data.map((e) => RetaguardaUser.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar usuários da retaguarda');
    }
  }

  Future<RetaguardaUser> create({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final res = await _api.dio.post(_base, data: {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      });
      return RetaguardaUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao criar usuário');
    }
  }

  Future<RetaguardaUser> update(
    String id, {
    String? name,
    String? role,
    String? status,
    String? password,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (role != null) body['role'] = role;
      if (status != null) body['status'] = status;
      if (password != null && password.isNotEmpty) body['password'] = password;
      final res = await _api.dio.put('$_base/$id', data: body);
      return RetaguardaUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao atualizar usuário');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _api.dio.delete('$_base/$id');
    } catch (e) {
      throw ApiException.from(e, 'Falha ao excluir usuário');
    }
  }
}
