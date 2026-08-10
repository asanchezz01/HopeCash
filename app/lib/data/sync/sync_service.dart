import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../local/database.dart';
import '../remote/api_client.dart';

/// Motor de sincronização offline-first.
///
/// push: drena a fila `pending_operations` em lote para POST /sync/push.
/// pull: busca alterações incrementais (GET /sync/pull?since=cursor) e aplica
///       upserts/tombstones no banco local, sem sobrescrever linhas pendentes.
///
/// Disparado por: login, volta de conectividade, timer periódico e após escritas.
class SyncService {
  SyncService(this._db, this._api);

  final AppDatabase _db;
  final ApiClient _api;

  final syncing = ValueNotifier<bool>(false);
  final lastError = ValueNotifier<String?>(null);

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _running = false;

  void start() {
    _timer ??= Timer.periodic(AppConfig.syncInterval, (_) => syncNow());
    _connectivity ??= Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) syncNow();
    });
    syncNow();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _connectivity?.cancel();
    _connectivity = null;
  }

  Future<void> syncNow() async {
    if (_running) return;
    _running = true;
    syncing.value = true;
    try {
      await _push();
      await _pull();
      lastError.value = null;
    } catch (e) {
      // Offline ou servidor indisponível: silencioso, tenta de novo depois.
      lastError.value = e.toString();
    } finally {
      _running = false;
      syncing.value = false;
    }
  }

  Future<String> _deviceId() async {
    var id = await _db.stateValue('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await _db.setStateValue('device_id', id);
    }
    return id;
  }

  // ---------------- PUSH ----------------

  Future<void> _push() async {
    final ops =
        await (_db.select(_db.pendingOperations)
              ..orderBy([(o) => OrderingTerm.asc(o.seq)])
              ..limit(200))
            .get();
    if (ops.isEmpty) return;

    final res = await _api.dio.post(
      '/sync/push',
      data: {
        'device_id': await _deviceId(),
        'operations': [
          for (final op in ops)
            {
              'operation_id': op.operationId,
              'entity': op.entity,
              'entity_id': op.entityId,
              'op': op.op,
              'payload': op.payload == null ? null : jsonDecode(op.payload!),
              'base_version': op.baseVersion,
              'client_updated_at': op.clientUpdatedAt,
            },
        ],
      },
    );

    final results = (res.data['data']['results'] as List)
        .cast<Map<String, dynamic>>();
    final byOperation = {for (final op in ops) op.operationId: op};
    const appliedResults = {'applied', 'duplicate', 'conflict_resolved'};

    await _db.transaction(() async {
      for (final result in results) {
        final op = byOperation[result['operation_id']];
        if (op == null) continue;
        final resultKind = result['result'] as String?;
        if (!appliedResults.contains(resultKind)) {
          await _db.customUpdate(
            'UPDATE pending_operations SET attempts = attempts + 1 WHERE seq = ?',
            variables: [Variable<int>(op.seq)],
            updates: {_db.pendingOperations},
          );
          continue;
        }

        // Aplicada, duplicada ou resolvida: o registro do servidor confirma a
        // versão. Só não sobrescreve se o usuário já fez uma edição local mais
        // nova para o mesmo registro enquanto este push estava em andamento.
        final record = result['record'] as Map<String, dynamic>?;
        if (record != null && !(await _hasNewerPendingOperation(op))) {
          await _applyServerRecord(op.entity, record, overwritePending: true);
        }
        await (_db.delete(
          _db.pendingOperations,
        )..where((o) => o.seq.equals(op.seq))).go();
      }
    });
  }

  Future<bool> _hasNewerPendingOperation(PendingOperation op) async {
    final count = _db.pendingOperations.seq.count();
    final row =
        await (_db.selectOnly(_db.pendingOperations)
              ..addColumns([count])
              ..where(
                _db.pendingOperations.entity.equals(op.entity) &
                    _db.pendingOperations.entityId.equals(op.entityId) &
                    _db.pendingOperations.seq.isBiggerThanValue(op.seq),
              ))
            .getSingle();
    return (row.read(count) ?? 0) > 0;
  }

  // ---------------- PULL ----------------

  static const _entities =
      'bank_accounts,categories,subcategories,transactions,credit_cards,'
      'goals,debts,investments,investment_movements,budgets,budget_items';

  Future<void> _pull() async {
    final cursor = await _db.stateValue('pull_cursor') ?? '0';
    final res = await _api.dio.get(
      '/sync/pull',
      queryParameters: {'since': cursor, 'entities': _entities},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    final entities = data['entities'] as Map<String, dynamic>;

    await _db.transaction(() async {
      for (final entry in entities.entries) {
        for (final record
            in (entry.value as List).cast<Map<String, dynamic>>()) {
          await _applyServerRecord(entry.key, record);
        }
      }
      await _db.setStateValue('pull_cursor', data['cursor'] as String);
    });
  }

  /// Upsert de um registro vindo do servidor. Linhas com alteração local
  /// pendente não são sobrescritas — o push vai resolvê-las primeiro.
  Future<void> _applyServerRecord(
    String entity,
    Map<String, dynamic> r, {
    bool overwritePending = false,
  }) async {
    final id = r['id'] as String;
    double? d(dynamic v) => v == null ? null : (v as num).toDouble();

    switch (entity) {
      case 'bank_accounts':
        final local = await (_db.select(
          _db.localAccounts,
        )..where((a) => a.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localAccounts)
            .insertOnConflictUpdate(
              LocalAccountsCompanion(
                id: Value(id),
                name: Value(r['name'] as String),
                type: Value(r['type'] as String? ?? 'checking'),
                initialBalance: Value(d(r['initial_balance']) ?? 0),
                bankName: Value(r['bank_name'] as String?),
                color: Value(r['color'] as String?),
                icon: Value(r['icon'] as String?),
                isActive: Value(_bool(r['is_active'], true)),
                includeInTotal: Value(_bool(r['include_in_total'], true)),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'categories':
        final local = await (_db.select(
          _db.localCategories,
        )..where((c) => c.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localCategories)
            .insertOnConflictUpdate(
              LocalCategoriesCompanion(
                id: Value(id),
                name: Value(r['name'] as String),
                type: Value(r['type'] as String),
                icon: Value(r['icon'] as String?),
                color: Value(r['color'] as String?),
                isSystem: Value(_bool(r['is_system'], false)),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'subcategories':
        final local = await (_db.select(
          _db.localSubcategories,
        )..where((s) => s.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localSubcategories)
            .insertOnConflictUpdate(
              LocalSubcategoriesCompanion(
                id: Value(id),
                categoryId: Value(r['category_id'] as String? ?? ''),
                name: Value(r['name'] as String? ?? ''),
                icon: Value(r['icon'] as String?),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'transactions':
        final local = await (_db.select(
          _db.localTransactions,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localTransactions)
            .insertOnConflictUpdate(
              LocalTransactionsCompanion(
                id: Value(id),
                type: Value(r['type'] as String),
                description: Value(r['description'] as String? ?? ''),
                amount: Value(d(r['amount'])),
                amountPlanned: Value(d(r['amount_planned'])),
                competenceDate: Value(
                  r['competence_date']?.toString().substring(0, 10) ?? '',
                ),
                dueDate: Value(_date(r['due_date'])),
                paymentDate: Value(_date(r['payment_date'])),
                status: Value(r['status'] as String? ?? 'planned'),
                accountId: Value(r['account_id'] as String?),
                cardId: Value(r['card_id'] as String?),
                categoryId: Value(r['category_id'] as String?),
                subcategoryId: Value(r['subcategory_id'] as String?),
                categorySplits: Value(
                  r['category_splits'] == null
                      ? null
                      : jsonEncode(r['category_splits']),
                ),
                notes: Value(r['notes'] as String?),
                installmentNumber: Value(r['installment_number'] as int?),
                installmentTotal: Value(r['installment_total'] as int?),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'credit_cards':
        final local = await (_db.select(
          _db.localCreditCards,
        )..where((c) => c.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localCreditCards)
            .insertOnConflictUpdate(
              LocalCreditCardsCompanion(
                id: Value(id),
                name: Value(r['name'] as String),
                issuer: Value(r['issuer'] as String?),
                limitAmount: Value(d(r['limit_amount']) ?? 0),
                closingDay: Value(r['closing_day'] as int? ?? 1),
                dueDay: Value(r['due_day'] as int? ?? 10),
                color: Value(r['color'] as String?),
                icon: Value(r['icon'] as String?),
                isActive: Value(_bool(r['is_active'], true)),
                defaultAccountId: Value(r['default_account_id'] as String?),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'goals':
        final local = await (_db.select(
          _db.localGoals,
        )..where((g) => g.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localGoals)
            .insertOnConflictUpdate(
              LocalGoalsCompanion(
                id: Value(id),
                name: Value(r['name'] as String),
                targetAmount: Value(d(r['target_amount']) ?? 0),
                targetDate: Value(_date(r['target_date'])),
                accumulatedAmount: Value(d(r['accumulated_amount']) ?? 0),
                linkedAccountId: Value(r['linked_account_id'] as String?),
                icon: Value(r['icon'] as String?),
                color: Value(r['color'] as String?),
                status: Value(r['status'] as String? ?? 'active'),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'debts':
        final local = await (_db.select(
          _db.localDebts,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localDebts)
            .insertOnConflictUpdate(
              LocalDebtsCompanion(
                id: Value(id),
                name: Value(r['name'] as String),
                type: Value(r['type'] as String? ?? 'loan'),
                institution: Value(r['institution'] as String?),
                originalAmount: Value(d(r['original_amount']) ?? 0),
                outstandingBalance: Value(d(r['outstanding_balance']) ?? 0),
                interestRateMonthly: Value(d(r['interest_rate_monthly']) ?? 0),
                totalInstallments: Value(r['total_installments'] as int? ?? 1),
                paidInstallments: Value(r['paid_installments'] as int? ?? 0),
                installmentAmount: Value(d(r['installment_amount']) ?? 0),
                firstDueDate: Value(_date(r['first_due_date'])),
                dueDay: Value(r['due_day'] as int?),
                accountId: Value(r['account_id'] as String?),
                categoryId: Value(r['category_id'] as String?),
                subcategoryId: Value(r['subcategory_id'] as String?),
                budgetItemId: Value(r['budget_item_id'] as String?),
                status: Value(r['status'] as String? ?? 'active'),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'investments':
        final local = await (_db.select(
          _db.localInvestments,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localInvestments)
            .insertOnConflictUpdate(
              LocalInvestmentsCompanion(
                id: Value(id),
                name: Value(r['name'] as String),
                type: Value(r['type'] as String? ?? 'fixed_income'),
                institution: Value(r['institution'] as String?),
                appliedAmount: Value(d(r['applied_amount']) ?? 0),
                currentAmount: Value(d(r['current_amount']) ?? 0),
                lastQuoteDate: Value(_date(r['last_quote_date'])),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'investment_movements':
        final local = await (_db.select(
          _db.localInvestmentMovements,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localInvestmentMovements)
            .insertOnConflictUpdate(
              LocalInvestmentMovementsCompanion(
                id: Value(id),
                investmentId: Value(r['investment_id'] as String? ?? ''),
                type: Value(r['type'] as String? ?? 'deposit'),
                amount: Value(d(r['amount']) ?? 0),
                movementDate: Value(_date(r['movement_date']) ?? ''),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'budgets':
        final local = await (_db.select(
          _db.localBudgets,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localBudgets)
            .insertOnConflictUpdate(
              LocalBudgetsCompanion(
                id: Value(id),
                referenceMonth: Value(_date(r['reference_month']) ?? ''),
                scope: Value(r['scope'] as String? ?? 'personal'),
                notes: Value(r['notes'] as String?),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
      case 'budget_items':
        final local = await (_db.select(
          _db.localBudgetItems,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (!overwritePending &&
            local != null &&
            local.syncStatus == 'pending') {
          return;
        }
        await _db
            .into(_db.localBudgetItems)
            .insertOnConflictUpdate(
              LocalBudgetItemsCompanion(
                id: Value(id),
                budgetId: Value(r['budget_id'] as String? ?? ''),
                categoryId: Value(r['category_id'] as String? ?? ''),
                subcategoryId: Value(r['subcategory_id'] as String?),
                plannedAmount: Value(d(r['planned_amount']) ?? 0),
                isFixed: Value(_bool(r['is_fixed'], false)),
                dueDay: Value((r['due_day'] as num?)?.toInt()),
                accountId: Value(r['account_id'] as String?),
                cardId: Value(r['card_id'] as String?),
                version: Value(r['version'] as int? ?? 1),
                updatedAt: Value(r['updated_at']?.toString() ?? ''),
                deletedAt: Value(r['deleted_at']?.toString()),
                syncStatus: const Value('synced'),
              ),
            );
    }
  }

  static bool _bool(dynamic v, bool fallback) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    return fallback;
  }

  static String? _date(dynamic v) {
    final s = v?.toString();
    if (s == null || s.length < 10) return null;
    return s.substring(0, 10);
  }
}
