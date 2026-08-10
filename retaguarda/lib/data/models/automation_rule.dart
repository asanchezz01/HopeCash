/// Regra de uma mensagem push automática do sistema (avisos de vencimento,
/// insights financeiros, dicas da Hope) — não confundir com [PushCampaign],
/// que é composta manualmente pela retaguarda.
class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.messageType,
    required this.enabled,
    required this.frequencyDays,
    this.title,
    this.body,
    this.config = const {},
  });

  final String id;
  // due_reminder | financial_insight | tip
  final String messageType;
  final bool enabled;
  // due_reminder: antecedência em dias antes do vencimento.
  // financial_insight/tip: intervalo mínimo (dias) entre envios ao mesmo usuário.
  final int frequencyDays;
  final String? title;
  final String? body;
  final Map<String, dynamic> config;

  static bool _asBool(Object? value) => value == true || value == 1;

  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
    id: json['id'] as String,
    messageType: json['message_type'] as String,
    enabled: _asBool(json['enabled']),
    frequencyDays: (json['frequency_days'] as num?)?.toInt() ?? 0,
    title: json['title'] as String?,
    body: json['body'] as String?,
    config: (json['config'] as Map<String, dynamic>?) ?? const {},
  );
}
