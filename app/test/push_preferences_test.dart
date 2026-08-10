import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/data/models/push_preferences.dart';

void main() {
  group('PushPreferences.fromJson', () {
    test('interpreta booleans reais (MySQL em produção)', () {
      final prefs = PushPreferences.fromJson({
        'push_enabled': true,
        'due_reminders_enabled': false,
        'financial_insights_enabled': true,
        'tips_enabled': true,
        'email_notifications_enabled': true,
        'reminder_advance_days': 3,
        'preferred_hour': 9,
        'timezone': 'America/Sao_Paulo',
      });
      expect(prefs.pushEnabled, isTrue);
      expect(prefs.dueRemindersEnabled, isFalse);
      expect(prefs.emailNotificationsEnabled, isTrue);
      expect(prefs.reminderAdvanceDays, 3);
      expect(prefs.preferredHour, 9);
      expect(prefs.timezone, 'America/Sao_Paulo');
    });

    test('interpreta 0/1 (SQLite em testes de backend)', () {
      final prefs = PushPreferences.fromJson({
        'push_enabled': 1,
        'due_reminders_enabled': 0,
        'financial_insights_enabled': 1,
        'tips_enabled': 0,
        'email_notifications_enabled': 0,
        'reminder_advance_days': 5,
        'preferred_hour': null,
        'timezone': 'America/Manaus',
      });
      expect(prefs.pushEnabled, isTrue);
      expect(prefs.dueRemindersEnabled, isFalse);
      expect(prefs.tipsEnabled, isFalse);
      expect(prefs.emailNotificationsEnabled, isFalse);
      expect(prefs.reminderAdvanceDays, 5);
      expect(prefs.preferredHour, isNull);
      expect(prefs.timezone, 'America/Manaus');
    });

    test('aplica defaults sensatos quando campos estão ausentes', () {
      final prefs = PushPreferences.fromJson(const {});
      expect(prefs.pushEnabled, isFalse);
      expect(prefs.emailNotificationsEnabled, isFalse);
      expect(prefs.reminderAdvanceDays, 3);
      expect(prefs.timezone, 'America/Sao_Paulo');
      expect(prefs.preferredHour, isNull);
    });
  });

  group('PushPreferences.copyWith', () {
    test('substitui só os campos informados', () {
      final base = PushPreferences.fromJson({
        'push_enabled': true,
        'due_reminders_enabled': true,
        'financial_insights_enabled': true,
        'tips_enabled': true,
        'email_notifications_enabled': true,
        'reminder_advance_days': 3,
        'preferred_hour': null,
        'timezone': 'America/Sao_Paulo',
      });
      final updated = base.copyWith(
        dueRemindersEnabled: false,
        emailNotificationsEnabled: false,
      );
      expect(updated.dueRemindersEnabled, isFalse);
      expect(updated.emailNotificationsEnabled, isFalse);
      expect(updated.pushEnabled, isTrue);
      expect(updated.timezone, 'America/Sao_Paulo');
    });
  });
}
