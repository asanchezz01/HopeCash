import '../../core/platform/notification_capture.dart';
import '../../core/utils/bank_notification_parse.dart';
import '../../core/utils/voice_parse.dart' show VoiceOption;
import '../local/database.dart';
import '../repositories/notification_suggestions_repository.dart';

String _eventTypeKey(BankEventType type) => switch (type) {
  BankEventType.accountDebit => 'account_debit',
  BankEventType.accountCredit => 'account_credit',
  BankEventType.cardPurchase => 'card_purchase',
  BankEventType.cardRefund => 'card_refund',
};

/// Busca notificações capturadas pelo serviço nativo, roda o parser local e
/// grava sugestões pendentes. Todo o processamento acontece no dispositivo —
/// o texto bruto nunca vai para o backend.
class NotificationIngestionService {
  NotificationIngestionService(this.db, this.capture, this.suggestions);

  final AppDatabase db;
  final NotificationCapture capture;
  final NotificationSuggestionsRepository suggestions;

  bool _ingesting = false;

  /// Processa a fila nativa. Retorna quantas sugestões novas foram criadas.
  Future<int> ingestPending() async {
    if (!capture.isSupported || _ingesting) return 0;
    _ingesting = true;
    try {
      final events = await capture.fetchPending();
      if (events.isEmpty) return 0;

      final accounts = await (db.select(
        db.localAccounts,
      )..where((a) => a.deletedAt.isNull())).get();
      final cards = await (db.select(
        db.localCreditCards,
      )..where((c) => c.deletedAt.isNull())).get();

      final accountOptions = [
        for (final a in accounts) VoiceOption(id: a.id, name: a.name),
        for (final a in accounts)
          if (a.bankName case final bank? when bank.trim().isNotEmpty)
            VoiceOption(id: a.id, name: bank),
      ];
      final cardOptions = [
        for (final c in cards) VoiceOption(id: c.id, name: c.name),
        for (final c in cards)
          if (c.issuer case final issuer? when issuer.trim().isNotEmpty)
            VoiceOption(id: c.id, name: issuer),
      ];

      var created = 0;
      final consumed = <String>[];
      for (final event in events) {
        consumed.add(event.hash);
        if (await suggestions.hashExists(event.hash)) continue;

        final parsed = parseBankNotification(
          title: event.title,
          text: event.text,
          appName: event.appName,
          accounts: accountOptions,
          cards: cardOptions,
        );
        if (parsed == null || parsed.amount == null) continue;

        await suggestions.insertSuggestion(
          sourcePackage: event.packageName,
          sourceAppName: event.appName,
          notificationHash: event.hash,
          rawTitle: event.title,
          rawText: event.text,
          eventType: _eventTypeKey(parsed.eventType),
          transactionType: parsed.transactionType,
          amount: parsed.amount!,
          description: parsed.description,
          suggestedAccountId: parsed.accountId,
          suggestedCardId: parsed.cardId,
          confidence: parsed.confidence,
          receivedAt: event.postedAt.toIso8601String(),
        );
        created++;
      }

      await capture.markConsumed(consumed);
      return created;
    } finally {
      _ingesting = false;
    }
  }
}
