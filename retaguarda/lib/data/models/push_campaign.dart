class DeliveryChannelStats {
  const DeliveryChannelStats({
    this.total = 0,
    this.pending = 0,
    this.sending = 0,
    this.sent = 0,
    this.failed = 0,
  });

  final int total;
  final int pending;
  final int sending;
  final int sent;
  final int failed;

  factory DeliveryChannelStats.fromJson(Map<String, dynamic>? json) =>
      DeliveryChannelStats(
        total: (json?['total'] as num?)?.toInt() ?? 0,
        pending: (json?['pending'] as num?)?.toInt() ?? 0,
        sending: (json?['sending'] as num?)?.toInt() ?? 0,
        sent: (json?['sent'] as num?)?.toInt() ?? 0,
        failed: (json?['failed'] as num?)?.toInt() ?? 0,
      );
}

/// Campanha de notificação push criada pela retaguarda.
class PushCampaign {
  const PushCampaign({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.audience,
    required this.targetUserIds,
    this.deepLink,
    required this.status,
    this.scheduledAt,
    this.scheduledTimezone,
    this.sentAt,
    this.canceledAt,
    required this.recipientsTotal,
    required this.successTotal,
    required this.failureTotal,
    required this.createdAt,
    this.deliveryMode = 'none',
    this.pushDelivery = const DeliveryChannelStats(),
    this.emailDelivery = const DeliveryChannelStats(),
  });

  final String id;
  final String title;
  final String body;
  final String category; // general|tips|insights|maintenance|promo
  final String audience; // all|selected
  final List<String> targetUserIds;
  final String? deepLink;
  // draft|scheduled|processing|sent|partially_sent|canceled|failed
  final String status;
  final String? scheduledAt;
  final String? scheduledTimezone;
  final String? sentAt;
  final String? canceledAt;
  final int recipientsTotal;
  final int successTotal;
  final int failureTotal;
  final String createdAt;
  // none|push|email|both — calculado a partir das entregas realmente criadas.
  final String deliveryMode;
  final DeliveryChannelStats pushDelivery;
  final DeliveryChannelStats emailDelivery;

  bool get isEditable => status == 'draft' || status == 'scheduled';
  bool get isCancelable => status == 'draft' || status == 'scheduled';
  bool get isSendable => status == 'draft' || status == 'scheduled';
  bool get canReprocess =>
      status == 'sent' || status == 'partially_sent' || status == 'failed';
  // Bloqueado só enquanto "processing" — o backend pode estar lendo a linha
  // para montar o conteúdo das entregas em andamento.
  bool get canDelete => status != 'processing';
  // Reenviar faz sentido depois que a campanha já foi (ou tentou ser) enviada
  // ou cancelada; para rascunho/agendada/processando, use enviar/agendar/cancelar.
  bool get canResend =>
      status == 'sent' ||
      status == 'partially_sent' ||
      status == 'failed' ||
      status == 'canceled';

  factory PushCampaign.fromJson(Map<String, dynamic> json) {
    final summary =
        json['delivery_summary'] as Map<String, dynamic>? ?? const {};
    return PushCampaign(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      category: json['category'] as String? ?? 'general',
      audience: json['audience'] as String? ?? 'all',
      targetUserIds: (json['target_user_ids'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      deepLink: json['deep_link'] as String?,
      status: json['status'] as String? ?? 'draft',
      scheduledAt: json['scheduled_at'] as String?,
      scheduledTimezone: json['scheduled_timezone'] as String?,
      sentAt: json['sent_at'] as String?,
      canceledAt: json['canceled_at'] as String?,
      recipientsTotal: (json['recipients_total'] as num?)?.toInt() ?? 0,
      successTotal: (json['success_total'] as num?)?.toInt() ?? 0,
      failureTotal: (json['failure_total'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      deliveryMode: json['delivery_mode'] as String? ?? 'none',
      pushDelivery: DeliveryChannelStats.fromJson(
        summary['push'] as Map<String, dynamic>?,
      ),
      emailDelivery: DeliveryChannelStats.fromJson(
        summary['email'] as Map<String, dynamic>?,
      ),
    );
  }
}

/// Página de resultados de campanhas.
class PushCampaignPage {
  const PushCampaignPage({required this.campaigns, required this.total});

  final List<PushCampaign> campaigns;
  final int total;
}

/// Nome de um usuário destinatário, sem outros dados pessoais.
class PushCampaignRecipient {
  const PushCampaignRecipient({required this.id, required this.name});

  final String id;
  final String name;

  factory PushCampaignRecipient.fromJson(Map<String, dynamic> json) =>
      PushCampaignRecipient(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

/// Página de destinatários. A fonte indica se os nomes vêm do histórico real
/// de entregas ou da elegibilidade calculada antes do envio.
class PushCampaignRecipientPage {
  const PushCampaignRecipientPage({
    required this.recipients,
    required this.total,
    required this.source,
  });

  final List<PushCampaignRecipient> recipients;
  final int total;
  final String source; // delivery_history | current_eligibility
}

/// Prévia de uma campanha — alcance estimado sem enviar nada.
class PushCampaignPreview {
  const PushCampaignPreview({
    required this.title,
    required this.body,
    this.deepLink,
    required this.recipientsTotal,
    required this.devicesTotal,
    required this.byPlatform,
    this.emailTotal = 0,
  });

  final String title;
  final String body;
  final String? deepLink;
  final int recipientsTotal;
  final int devicesTotal;
  final Map<String, int> byPlatform;
  final int emailTotal;

  factory PushCampaignPreview.fromJson(Map<String, dynamic> json) =>
      PushCampaignPreview(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        deepLink: json['deep_link'] as String?,
        recipientsTotal: (json['recipients_total'] as num?)?.toInt() ?? 0,
        devicesTotal: (json['devices_total'] as num?)?.toInt() ?? 0,
        emailTotal:
            (json['email_total'] as num?)?.toInt() ??
            (json['email_fallback_total'] as num?)?.toInt() ??
            0,
        byPlatform: (json['by_platform'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      );
}

/// Uma entrega com falha permanente/esgotada, para a lista de falhas da campanha.
class PushDeliveryFailure {
  const PushDeliveryFailure({
    required this.id,
    required this.userId,
    this.deviceId,
    required this.channel,
    this.error,
    required this.attempts,
    this.processedAt,
  });

  final String id;
  final String userId;
  final String? deviceId;
  final String channel;
  final String? error;
  final int attempts;
  final String? processedAt;

  factory PushDeliveryFailure.fromJson(Map<String, dynamic> json) =>
      PushDeliveryFailure(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        deviceId: json['device_id'] as String?,
        channel: json['channel'] as String? ?? 'push',
        error: json['error'] as String?,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        processedAt: json['processed_at'] as String?,
      );
}

/// Estatísticas completas de uma campanha (contadores + falhas recentes).
class PushCampaignStats {
  const PushCampaignStats({
    required this.campaign,
    required this.pending,
    required this.sending,
    required this.sent,
    required this.failed,
    required this.failures,
  });

  final PushCampaign campaign;
  final int pending;
  final int sending;
  final int sent;
  final int failed;
  final List<PushDeliveryFailure> failures;

  factory PushCampaignStats.fromJson(Map<String, dynamic> json) {
    final counters = json['counters'] as Map<String, dynamic>? ?? const {};
    return PushCampaignStats(
      campaign: PushCampaign.fromJson(json['campaign'] as Map<String, dynamic>),
      pending: (counters['pending'] as num?)?.toInt() ?? 0,
      sending: (counters['sending'] as num?)?.toInt() ?? 0,
      sent: (counters['sent'] as num?)?.toInt() ?? 0,
      failed: (counters['failed'] as num?)?.toInt() ?? 0,
      failures: (json['failures'] as List<dynamic>? ?? const [])
          .map((e) => PushDeliveryFailure.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
