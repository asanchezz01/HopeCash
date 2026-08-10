import '../../core/config/app_config.dart';
import '../models/push_campaign.dart';
import '../remote/api_client.dart';

/// Campanhas de notificação push da retaguarda (`/retaguarda/notifications`).
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;
  static const _base = '${AppConfig.retaguardaPrefix}/notifications';

  Future<PushCampaignPage> list({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _api.dio.get(
        _base,
        queryParameters: {'status': ?status, 'page': page, 'limit': limit},
      );
      final data = res.data['data'] as List<dynamic>;
      final meta = res.data['meta'] as Map<String, dynamic>? ?? const {};
      return PushCampaignPage(
        campaigns: data
            .map((e) => PushCampaign.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (meta['total'] as num?)?.toInt() ?? data.length,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar campanhas');
    }
  }

  Future<PushCampaign> get(String id) async {
    try {
      final res = await _api.dio.get('$_base/$id');
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar a campanha');
    }
  }

  Future<PushCampaignRecipientPage> recipients(
    String id, {
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final res = await _api.dio.get(
        '$_base/$id/recipients',
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = res.data['data'] as List<dynamic>? ?? const [];
      final meta = res.data['meta'] as Map<String, dynamic>? ?? const {};
      return PushCampaignRecipientPage(
        recipients: data
            .map(
              (item) =>
                  PushCampaignRecipient.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        total: (meta['total'] as num?)?.toInt() ?? data.length,
        source: meta['source'] as String? ?? 'current_eligibility',
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar destinatários');
    }
  }

  Future<PushCampaign> create({
    required String title,
    required String body,
    required String category,
    required String audience,
    List<String>? targetUserIds,
    String? deepLink,
  }) async {
    try {
      final res = await _api.dio.post(
        _base,
        data: {
          'title': title,
          'body': body,
          'category': category,
          'audience': audience,
          if (audience == 'selected') 'target_user_ids': targetUserIds,
          'deep_link': ?deepLink,
        },
      );
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao criar a campanha');
    }
  }

  /// Substitui o conteúdo/configuração da campanha — o chamador envia o
  /// estado completo do formulário (não um patch parcial).
  Future<PushCampaign> update(
    String id, {
    required String title,
    required String body,
    required String category,
    required String audience,
    List<String>? targetUserIds,
    String? deepLink,
  }) async {
    try {
      final res = await _api.dio.put(
        '$_base/$id',
        data: {
          'title': title,
          'body': body,
          'category': category,
          'audience': audience,
          if (audience == 'selected') 'target_user_ids': targetUserIds,
          'deep_link': deepLink,
        },
      );
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao editar a campanha');
    }
  }

  Future<PushCampaignPreview> preview(String id) async {
    try {
      final res = await _api.dio.get('$_base/$id/preview');
      return PushCampaignPreview.fromJson(
        res.data['data'] as Map<String, dynamic>,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao gerar a prévia');
    }
  }

  Future<PushCampaignStats> stats(String id) async {
    try {
      final res = await _api.dio.get('$_base/$id/stats');
      return PushCampaignStats.fromJson(
        res.data['data'] as Map<String, dynamic>,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar estatísticas');
    }
  }

  Future<PushCampaign> sendNow(String id) async {
    try {
      final res = await _api.dio.post('$_base/$id/send');
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao enviar a campanha');
    }
  }

  Future<PushCampaign> schedule(
    String id, {
    required String date,
    required String time,
    required String timezone,
  }) async {
    try {
      final res = await _api.dio.post(
        '$_base/$id/schedule',
        data: {'date': date, 'time': time, 'timezone': timezone},
      );
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao agendar a campanha');
    }
  }

  Future<PushCampaign> cancel(String id) async {
    try {
      final res = await _api.dio.post('$_base/$id/cancel');
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao cancelar a campanha');
    }
  }

  Future<int> reprocess(String id) async {
    try {
      final res = await _api.dio.post('$_base/$id/reprocess');
      final data = res.data['data'] as Map<String, dynamic>;
      return (data['reset'] as num?)?.toInt() ?? 0;
    } catch (e) {
      throw ApiException.from(e, 'Falha ao reprocessar falhas');
    }
  }

  /// Exclui a campanha e seu histórico de entregas — não pode ser desfeito.
  Future<void> delete(String id) async {
    try {
      await _api.dio.delete('$_base/$id');
    } catch (e) {
      throw ApiException.from(e, 'Falha ao excluir a campanha');
    }
  }

  /// Duplica a campanha como um novo rascunho e envia imediatamente,
  /// reavaliando destinatários/preferências atuais.
  Future<PushCampaign> resend(String id, {required String channel}) async {
    try {
      final res = await _api.dio.post(
        '$_base/$id/resend',
        data: {'channel': channel},
      );
      return PushCampaign.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao reenviar a campanha');
    }
  }
}
