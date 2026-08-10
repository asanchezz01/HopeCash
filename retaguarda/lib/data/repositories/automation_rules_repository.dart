import '../../core/config/app_config.dart';
import '../models/automation_rule.dart';
import '../remote/api_client.dart';

class GeneratedTip {
  const GeneratedTip({
    required this.title,
    required this.body,
    required this.personalized,
    this.targetUserId,
  });

  final String title;
  final String body;
  final bool personalized;
  final String? targetUserId;
}

class TipSendResult {
  const TipSendResult({
    required this.campaignId,
    required this.recipientsTotal,
    required this.successTotal,
    required this.failureTotal,
  });

  final String campaignId;
  final int recipientsTotal;
  final int successTotal;
  final int failureTotal;
}

/// Regras de mensagens push automáticas (`/retaguarda/automation-rules`).
class AutomationRulesRepository {
  AutomationRulesRepository(this._api);

  final ApiClient _api;
  static const _base = '${AppConfig.retaguardaPrefix}/automation-rules';

  Future<List<AutomationRule>> list() async {
    try {
      final res = await _api.dio.get(_base);
      return (res.data['data'] as List<dynamic>)
          .map((e) => AutomationRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e, 'Falha ao carregar mensagens automáticas');
    }
  }

  Future<AutomationRule> update(
    String messageType, {
    bool? enabled,
    int? frequencyDays,
    String? title,
    String? body,
    Map<String, dynamic>? config,
  }) async {
    try {
      final res = await _api.dio.put(
        '$_base/$messageType',
        data: {
          'enabled': ?enabled,
          'frequency_days': ?frequencyDays,
          'title': ?title,
          'body': ?body,
          'config': ?config,
        },
      );
      return AutomationRule.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e, 'Falha ao salvar');
    }
  }

  Future<GeneratedTip> generateTip({String? userId}) async {
    try {
      final res = await _api.dio.post(
        '$_base/tip/generate',
        data: {'user_id': ?userId},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      return GeneratedTip(
        title: data['title'] as String,
        body: data['body'] as String,
        personalized: data['personalized'] as bool? ?? false,
        targetUserId: data['target_user_id'] as String?,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao gerar a dica');
    }
  }

  Future<TipSendResult> sendTipNow({
    required String title,
    required String body,
    String? userId,
  }) async {
    try {
      final res = await _api.dio.post(
        '$_base/tip/send',
        data: {'title': title, 'body': body, 'user_id': ?userId},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      return TipSendResult(
        campaignId: data['id'] as String,
        recipientsTotal: (data['recipients_total'] as num?)?.toInt() ?? 0,
        successTotal: (data['success_total'] as num?)?.toInt() ?? 0,
        failureTotal: (data['failure_total'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw ApiException.from(e, 'Falha ao enviar a dica');
    }
  }
}
