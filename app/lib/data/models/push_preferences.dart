/// Preferências de notificação push do usuário autenticado.
class PushPreferences {
  const PushPreferences({
    required this.pushEnabled,
    required this.dueRemindersEnabled,
    required this.financialInsightsEnabled,
    required this.tipsEnabled,
    required this.emailNotificationsEnabled,
    required this.reminderAdvanceDays,
    required this.preferredHour,
    required this.timezone,
  });

  final bool pushEnabled;
  final bool dueRemindersEnabled;
  final bool financialInsightsEnabled;
  final bool tipsEnabled;
  // Autoriza o canal de e-mail junto com o push para as categorias habilitadas.
  final bool emailNotificationsEnabled;
  final int reminderAdvanceDays;
  final int? preferredHour;
  final String timezone;

  static bool _asBool(Object? value) => value == true || value == 1;

  factory PushPreferences.fromJson(Map<String, dynamic> json) =>
      PushPreferences(
        pushEnabled: _asBool(json['push_enabled']),
        dueRemindersEnabled: _asBool(json['due_reminders_enabled']),
        financialInsightsEnabled: _asBool(json['financial_insights_enabled']),
        tipsEnabled: _asBool(json['tips_enabled']),
        emailNotificationsEnabled: _asBool(json['email_notifications_enabled']),
        reminderAdvanceDays:
            (json['reminder_advance_days'] as num?)?.toInt() ?? 3,
        preferredHour: (json['preferred_hour'] as num?)?.toInt(),
        timezone: json['timezone'] as String? ?? 'America/Sao_Paulo',
      );

  PushPreferences copyWith({
    bool? pushEnabled,
    bool? dueRemindersEnabled,
    bool? financialInsightsEnabled,
    bool? tipsEnabled,
    bool? emailNotificationsEnabled,
    int? reminderAdvanceDays,
    int? preferredHour,
    String? timezone,
  }) => PushPreferences(
    pushEnabled: pushEnabled ?? this.pushEnabled,
    dueRemindersEnabled: dueRemindersEnabled ?? this.dueRemindersEnabled,
    financialInsightsEnabled:
        financialInsightsEnabled ?? this.financialInsightsEnabled,
    tipsEnabled: tipsEnabled ?? this.tipsEnabled,
    emailNotificationsEnabled:
        emailNotificationsEnabled ?? this.emailNotificationsEnabled,
    reminderAdvanceDays: reminderAdvanceDays ?? this.reminderAdvanceDays,
    preferredHour: preferredHour ?? this.preferredHour,
    timezone: timezone ?? this.timezone,
  );
}
