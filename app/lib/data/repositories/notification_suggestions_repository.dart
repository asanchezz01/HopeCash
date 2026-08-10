import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';

const _uuid = Uuid();

/// Sugestões de lançamento vindas de notificações bancárias.
/// Dados 100% locais: nada aqui entra na fila de sincronização.
class NotificationSuggestionsRepository {
  NotificationSuggestionsRepository(this.db);

  final AppDatabase db;

  Stream<List<LocalNotificationSuggestion>> watchPending() =>
      (db.select(db.localNotificationSuggestions)
            ..where((s) => s.status.equals('pending'))
            ..orderBy([(s) => OrderingTerm.desc(s.receivedAt)]))
          .watch();

  Stream<int> watchPendingCount() {
    final count = db.localNotificationSuggestions.id.count();
    final query = db.selectOnly(db.localNotificationSuggestions)
      ..addColumns([count])
      ..where(db.localNotificationSuggestions.status.equals('pending'));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  Future<bool> hashExists(String notificationHash) async {
    final row =
        await (db.select(db.localNotificationSuggestions)
              ..where((s) => s.notificationHash.equals(notificationHash))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Insere uma sugestão pendente. Ignora silenciosamente se o hash já
  /// existir (notificação repetida).
  Future<void> insertSuggestion({
    required String sourcePackage,
    required String sourceAppName,
    required String notificationHash,
    required String rawTitle,
    required String rawText,
    required String eventType,
    required String transactionType,
    required double amount,
    required String description,
    String? suggestedAccountId,
    String? suggestedCardId,
    String? suggestedCategoryId,
    required double confidence,
    required String receivedAt,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db
        .into(db.localNotificationSuggestions)
        .insert(
          LocalNotificationSuggestionsCompanion.insert(
            id: _uuid.v4(),
            sourcePackage: sourcePackage,
            sourceAppName: Value(sourceAppName),
            notificationHash: notificationHash,
            rawTitle: Value(rawTitle),
            rawText: Value(rawText),
            eventType: eventType,
            transactionType: transactionType,
            amount: amount,
            description: description,
            suggestedAccountId: Value(suggestedAccountId),
            suggestedCardId: Value(suggestedCardId),
            suggestedCategoryId: Value(suggestedCategoryId),
            confidence: Value(confidence),
            receivedAt: receivedAt,
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// pending | approved | ignored | duplicate
  Future<void> setStatus(String id, String status) =>
      (db.update(db.localNotificationSuggestions)
            ..where((s) => s.id.equals(id)))
          .write(LocalNotificationSuggestionsCompanion(status: Value(status)));

  /// Apaga sugestões ignoradas e as não-pendentes mais antigas que [maxAge].
  Future<int> cleanUp({Duration maxAge = const Duration(days: 90)}) async {
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();
    final ignored = await (db.delete(db.localNotificationSuggestions)
          ..where((s) => s.status.equals('ignored')))
        .go();
    final old = await (db.delete(db.localNotificationSuggestions)
          ..where(
            (s) =>
                s.status.equals('pending').not() &
                s.createdAt.isSmallerThanValue(cutoff),
          ))
        .go();
    return ignored + old;
  }
}
