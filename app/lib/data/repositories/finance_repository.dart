import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/finance_calc.dart';
import '../local/database.dart';

const _uuid = Uuid();
const _debtPaymentNotePrefix = 'hopecash:debt_payment:';
const _goalMovementNotePrefix = 'hopecash:goal_movement:';
const _budgetVarianceNotePrefix = 'hopecash:budget_variance:';

String _now() => DateTime.now()
    .toUtc()
    .toIso8601String()
    .substring(0, 23)
    .replaceFirst('T', ' ');

double _roundMoney(num value) => (value * 100).roundToDouble() / 100;

/// Uma parcela de categoria de um lançamento. O lançamento financeiro continua
/// sendo único; estas parcelas servem exclusivamente para classificação.
class TransactionSplit {
  const TransactionSplit({
    required this.categoryId,
    required this.amount,
    this.subcategoryId,
  });

  final String categoryId;
  final String? subcategoryId;
  final double amount;

  Map<String, dynamic> toJson() => {
    'category_id': categoryId,
    'subcategory_id': subcategoryId,
    'amount': _roundMoney(amount),
  };

  static List<TransactionSplit> fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final values = jsonDecode(raw);
      if (values is! List) return const [];
      return values
          .whereType<Map>()
          .map((value) {
            final data = Map<String, dynamic>.from(value);
            return TransactionSplit(
              categoryId: data['category_id'] as String? ?? '',
              subcategoryId: data['subcategory_id'] as String?,
              amount: (data['amount'] as num?)?.toDouble() ?? 0,
            );
          })
          .where((split) => split.categoryId.isNotEmpty && split.amount > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

String? encodeTransactionSplits(List<TransactionSplit>? splits, double total) {
  if (splits == null || splits.isEmpty) return null;
  final cents = (total * 100).round();
  final splitCents = splits.fold<int>(
    0,
    (sum, split) => sum + (split.amount * 100).round(),
  );
  if (splits.length < 2 ||
      cents != splitCents ||
      splits.any((split) => split.categoryId.isEmpty || split.amount <= 0)) {
    throw ArgumentError(
      'As partes do rateio devem somar exatamente o valor total',
    );
  }
  return jsonEncode(splits.map((split) => split.toJson()).toList());
}

List<TransactionSplit> transactionSplits(LocalTransaction tx) {
  final splits = TransactionSplit.fromJson(tx.categorySplits);
  if (splits.isNotEmpty) return splits;
  final value = (tx.status == 'paid' ? tx.amount : tx.amountPlanned) ?? 0;
  return tx.categoryId == null
      ? const []
      : [
          TransactionSplit(
            categoryId: tx.categoryId!,
            subcategoryId: tx.subcategoryId,
            amount: value,
          ),
        ];
}

Map<String, dynamic> _decodePayload(String? raw) {
  if (raw == null || raw.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Payloads antigos ou corrompidos não devem quebrar a fila offline.
  }
  return <String, dynamic>{};
}

String _debtPaymentNote({
  required String debtId,
  required String dueDate,
  required int installmentNumber,
  required int installmentsAdvanced,
}) {
  final payload = {
    'debt_id': debtId,
    'due_date': dueDate,
    'installment_number': installmentNumber,
    'installments_advanced': installmentsAdvanced,
  };
  return '$_debtPaymentNotePrefix${jsonEncode(payload)}';
}

DebtPaymentLink? _debtPaymentInfo(LocalTransaction tx) {
  final notes = tx.notes;
  if (notes == null || !notes.startsWith(_debtPaymentNotePrefix)) return null;
  try {
    final raw = notes.substring(_debtPaymentNotePrefix.length);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final debtId = data['debt_id'] as String?;
    final dueDate = data['due_date'] as String?;
    final installmentNumber = (data['installment_number'] as num?)?.toInt();
    final installmentsAdvanced =
        (data['installments_advanced'] as num?)?.toInt() ?? 1;
    if (debtId == null || dueDate == null || installmentNumber == null) {
      return null;
    }
    return DebtPaymentLink(
      debtId: debtId,
      dueDate: dueDate,
      installmentNumber: installmentNumber,
      installmentsAdvanced: installmentsAdvanced,
    );
  } catch (_) {
    return null;
  }
}

String _goalMovementNote({
  required String goalId,
  required String movementType,
}) {
  final payload = {'goal_id': goalId, 'movement_type': movementType};
  return '$_goalMovementNotePrefix${jsonEncode(payload)}';
}

GoalMovementLink? _goalMovementInfo(LocalTransaction tx) {
  final notes = tx.notes;
  if (notes == null || !notes.startsWith(_goalMovementNotePrefix)) {
    return null;
  }
  try {
    final raw = notes.substring(_goalMovementNotePrefix.length);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final goalId = data['goal_id'] as String?;
    final movementType = data['movement_type'] as String?;
    if (goalId == null || movementType == null) return null;
    return GoalMovementLink(goalId: goalId, movementType: movementType);
  } catch (_) {
    return null;
  }
}

String _budgetVarianceNote({
  required double amount,
  String? accountId,
  String? cardId,
  String? categoryId,
  String? subcategoryId,
}) {
  final payload = {
    'amount': _roundMoney(amount),
    'account_id': accountId,
    'card_id': cardId,
    'category_id': categoryId,
    'subcategory_id': subcategoryId,
  };
  return '$_budgetVarianceNotePrefix${jsonEncode(payload)}';
}

bool _isBudgetVarianceSettlement(LocalTransaction tx) =>
    tx.notes?.startsWith(_budgetVarianceNotePrefix) ?? false;

Map<String, dynamic>? _budgetVarianceData(LocalTransaction tx) {
  final notes = tx.notes;
  if (notes == null || !notes.startsWith(_budgetVarianceNotePrefix)) {
    return null;
  }
  try {
    final raw = notes.substring(_budgetVarianceNotePrefix.length);
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

double _budgetVarianceAmount(LocalTransaction tx) {
  if (!_isBudgetVarianceSettlement(tx)) return 0;
  final data = _budgetVarianceData(tx);
  final amount = (data?['amount'] as num?)?.toDouble();
  if (amount != null) {
    return _roundMoney(amount);
  }
  // Mantém compatibilidade com registros que só tenham amountPlanned.
  return _roundMoney(tx.amountPlanned ?? 0);
}

class DebtPaymentLink {
  const DebtPaymentLink({
    required this.debtId,
    required this.dueDate,
    required this.installmentNumber,
    required this.installmentsAdvanced,
  });

  final String debtId;
  final String dueDate;
  final int installmentNumber;
  final int installmentsAdvanced;
}

class DebtInstallmentPreview {
  const DebtInstallmentPreview({
    required this.dueDate,
    required this.installmentNumber,
    required this.amount,
  });

  final String dueDate;
  final int installmentNumber;
  final double amount;
}

class GoalMovementLink {
  const GoalMovementLink({required this.goalId, required this.movementType});

  final String goalId;

  /// contribution | withdrawal
  final String movementType;
}

/// Repositório local-first de contas, categorias e transações.
/// Toda escrita grava no Drift E enfileira a operação para o SyncService.
class FinanceRepository {
  FinanceRepository(this.db);

  final AppDatabase db;

  // ---------------- Fila offline ----------------

  Future<void> _enqueue({
    required String entity,
    required String entityId,
    required String op,
    Map<String, dynamic>? payload,
    int? baseVersion,
  }) async {
    final now = _now();
    final existing =
        await (db.select(db.pendingOperations)
              ..where(
                (o) => o.entity.equals(entity) & o.entityId.equals(entityId),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.seq)]))
            .get();

    Future<void> insertNew() => db
        .into(db.pendingOperations)
        .insert(
          PendingOperationsCompanion.insert(
            operationId: _uuid.v4(),
            entity: entity,
            entityId: entityId,
            op: op,
            payload: Value(payload == null ? null : jsonEncode(payload)),
            baseVersion: Value(baseVersion),
            clientUpdatedAt: now,
          ),
        );

    if (existing.isEmpty) {
      await insertNew();
      return;
    }

    final first = existing.first;
    final rest = existing.skip(1).map((operation) => operation.seq).toList();

    Map<String, dynamic> mergedExistingPayload() {
      final merged = <String, dynamic>{};
      for (final operation in existing) {
        merged.addAll(_decodePayload(operation.payload));
      }
      return merged;
    }

    Future<void> deleteRest() async {
      if (rest.isEmpty) return;
      await (db.delete(
        db.pendingOperations,
      )..where((o) => o.seq.isIn(rest))).go();
    }

    if (first.op == 'create') {
      if (op == 'delete') {
        await (db.delete(db.pendingOperations)..where(
              (o) => o.entity.equals(entity) & o.entityId.equals(entityId),
            ))
            .go();
        return;
      }
      final merged = {...mergedExistingPayload(), ...?payload};
      await (db.update(
        db.pendingOperations,
      )..where((o) => o.seq.equals(first.seq))).write(
        PendingOperationsCompanion(
          payload: Value(merged.isEmpty ? null : jsonEncode(merged)),
          clientUpdatedAt: Value(now),
        ),
      );
      await deleteRest();
      return;
    }

    if (first.op == 'delete') {
      await deleteRest();
      return;
    }

    if (op == 'delete') {
      await (db.update(
        db.pendingOperations,
      )..where((o) => o.seq.equals(first.seq))).write(
        PendingOperationsCompanion(
          op: const Value('delete'),
          payload: const Value(null),
          baseVersion: Value(first.baseVersion ?? baseVersion),
          clientUpdatedAt: Value(now),
        ),
      );
      await deleteRest();
      return;
    }

    final merged = {...mergedExistingPayload(), ...?payload};
    await (db.update(
      db.pendingOperations,
    )..where((o) => o.seq.equals(first.seq))).write(
      PendingOperationsCompanion(
        payload: Value(merged.isEmpty ? null : jsonEncode(merged)),
        baseVersion: Value(first.baseVersion ?? baseVersion),
        clientUpdatedAt: Value(now),
      ),
    );
    await deleteRest();
  }

  Stream<int> watchPendingCount() {
    final count = db.pendingOperations.seq.count();
    return (db.selectOnly(
      db.pendingOperations,
    )..addColumns([count])).map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Garante que o banco local persistente do PWA pertence ao usuário logado.
  ///
  /// O Drift usa o mesmo IndexedDB entre sessões. Sem essa guarda, trocar de
  /// usuário no mesmo navegador poderia misturar dados locais e reaproveitar o
  /// cursor de pull de outra conta.
  Future<void> prepareLocalStoreForUser(String userId) async {
    final current = await db.stateValue('active_user_id');
    if (current == userId) return;

    await db.transaction(() async {
      if (current != null && current != userId) {
        await _clearBusinessTables();
      }
      await db.setStateValue('active_user_id', userId);
      await db.setStateValue('pull_cursor', '0');
    });
  }

  Future<void> _clearBusinessTables() async {
    await db.delete(db.pendingOperations).go();
    await db.delete(db.localTransactions).go();
    await db.delete(db.localBudgetItems).go();
    await db.delete(db.localBudgets).go();
    await db.delete(db.localDebts).go();
    await db.delete(db.localGoals).go();
    await db.delete(db.localInvestmentMovements).go();
    await db.delete(db.localInvestments).go();
    await db.delete(db.localSubcategories).go();
    await db.delete(db.localCategories).go();
    await db.delete(db.localCreditCards).go();
    await db.delete(db.localAccounts).go();
    // Preserva o id do dispositivo e as marcas de tutorial visto (que são
    // por usuário e devem sobreviver à troca de conta no mesmo aparelho).
    await (db.delete(db.syncState)..where(
          (s) =>
              s.key.isNotValue('device_id') &
              s.key.like('onboarding_completed_%').not(),
        ))
        .go();
  }

  // ---------------- Contas ----------------

  Stream<List<LocalAccount>> watchAccounts() =>
      (db.select(db.localAccounts)
            ..where((a) => a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm.asc(a.name)]))
          .watch();

  Future<void> upsertAccount({
    String? id,
    required String name,
    required String type,
    required double initialBalance,
    String? bankName,
    String? color,
    String? icon,
    bool includeInTotal = true,
    bool isActive = true,
    int? currentVersion,
  }) async {
    final accountId = id ?? _uuid.v4();
    final payload = {
      'name': name,
      'type': type,
      'initial_balance': initialBalance,
      'bank_name': bankName,
      'color': color,
      'icon': icon,
      'include_in_total': includeInTotal,
      'is_active': isActive,
    };
    await db
        .into(db.localAccounts)
        .insertOnConflictUpdate(
          LocalAccountsCompanion(
            id: Value(accountId),
            name: Value(name),
            type: Value(type),
            initialBalance: Value(initialBalance),
            bankName: Value(bankName),
            color: Value(color),
            icon: Value(icon),
            includeInTotal: Value(includeInTotal),
            isActive: Value(isActive),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'bank_accounts',
      entityId: accountId,
      op: id == null ? 'create' : 'update',
      payload: payload,
      baseVersion: currentVersion,
    );
  }

  /// Saldo atual = saldo inicial + receitas pagas − despesas pagas.
  Future<double> accountBalance(LocalAccount account) async {
    final rows =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.accountId.equals(account.id) &
                  t.status.equals('paid') &
                  t.deletedAt.isNull(),
            ))
            .get();
    var balance = account.initialBalance;
    for (final t in rows) {
      final v = t.amount ?? 0;
      balance += t.type == 'income' ? v : -v;
    }
    return (balance * 100).roundToDouble() / 100;
  }

  /// Número de transações (não excluídas) vinculadas à conta [accountId].
  /// Usado para avisar o usuário antes de excluir a conta.
  Future<int> accountTransactionCount(String accountId) async {
    final rows =
        await (db.select(db.localTransactions)..where(
              (t) => t.accountId.equals(accountId) & t.deletedAt.isNull(),
            ))
            .get();
    return rows.length;
  }

  /// Exclui (soft delete) a conta e enfileira a operação para o servidor. As
  /// transações vinculadas são preservadas — apenas perdem o vínculo com a
  /// conta na exibição.
  Future<void> deleteAccount(LocalAccount account) => _softDeleteAndEnqueue(
    'bank_accounts',
    account.id,
    account.version,
    (id) => (db.update(db.localAccounts)..where((a) => a.id.equals(id))).write(
      LocalAccountsCompanion(
        deletedAt: Value(_now()),
        updatedAt: Value(_now()),
        syncStatus: const Value('pending'),
      ),
    ),
  );

  // ---------------- Categorias ----------------

  Stream<List<LocalCategory>> watchCategories({String? type}) {
    final q = db.select(db.localCategories)..where((c) => c.deletedAt.isNull());
    if (type != null) q.where((c) => c.type.equals(type));
    q.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return q.watch();
  }

  Stream<List<LocalSubcategory>> watchSubcategories({String? categoryId}) {
    final q = db.select(db.localSubcategories)
      ..where((s) => s.deletedAt.isNull());
    if (categoryId != null) q.where((s) => s.categoryId.equals(categoryId));
    q.orderBy([(s) => OrderingTerm.asc(s.name)]);
    return q.watch();
  }

  /// Retorna o id da categoria criada/atualizada, permitindo seleção
  /// imediata em fluxos de criação rápida.
  Future<String> upsertCategory({
    String? id,
    required String name,
    required String type,
    String? icon,
    String? color,
    bool isSystem = false,
    int? currentVersion,
  }) async {
    final categoryId = id ?? _uuid.v4();
    await db
        .into(db.localCategories)
        .insertOnConflictUpdate(
          LocalCategoriesCompanion(
            id: Value(categoryId),
            name: Value(name),
            type: Value(type),
            icon: Value(icon),
            color: Value(color),
            isSystem: Value(isSystem),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'categories',
      entityId: categoryId,
      op: id == null ? 'create' : 'update',
      payload: {'name': name, 'type': type, 'icon': icon, 'color': color},
      baseVersion: currentVersion,
    );
    return categoryId;
  }

  /// Uma categoria só pode ser excluída se não tiver lançamentos nem
  /// orçamentos vinculados (a ela ou às suas subcategorias já é coberto,
  /// pois lançamentos e itens de orçamento sempre carregam category_id).
  Future<bool> categoryHasReferences(String categoryId) async {
    final tx =
        await (db.select(db.localTransactions)
              ..where(
                (t) => t.deletedAt.isNull() & t.categoryId.equals(categoryId),
              )
              ..limit(1))
            .get();
    if (tx.isNotEmpty) return true;
    final items =
        await (db.select(db.localBudgetItems)
              ..where(
                (i) => i.deletedAt.isNull() & i.categoryId.equals(categoryId),
              )
              ..limit(1))
            .get();
    return items.isNotEmpty;
  }

  Future<void> deleteCategory(LocalCategory category) async {
    if (await categoryHasReferences(category.id)) {
      throw StateError(
        'Categoria possui lançamentos ou orçamentos e não pode ser excluída.',
      );
    }
    final now = _now();
    await db.transaction(() async {
      await _clearCategoryReferences(category.id, now);
      final children =
          await (db.select(db.localSubcategories)..where(
                (s) => s.categoryId.equals(category.id) & s.deletedAt.isNull(),
              ))
              .get();
      for (final child in children) {
        await _softDeleteSubcategory(child, now);
      }
      await (db.update(
        db.localCategories,
      )..where((c) => c.id.equals(category.id))).write(
        LocalCategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'categories',
        entityId: category.id,
        op: 'delete',
        baseVersion: category.version,
      );
    });
  }

  /// Retorna o id da subcategoria criada/atualizada.
  Future<String> upsertSubcategory({
    String? id,
    required String categoryId,
    required String name,
    String? icon,
    int? currentVersion,
  }) async {
    final subcategoryId = id ?? _uuid.v4();
    await db
        .into(db.localSubcategories)
        .insertOnConflictUpdate(
          LocalSubcategoriesCompanion(
            id: Value(subcategoryId),
            categoryId: Value(categoryId),
            name: Value(name),
            icon: Value(icon),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'subcategories',
      entityId: subcategoryId,
      op: id == null ? 'create' : 'update',
      payload: {'category_id': categoryId, 'name': name, 'icon': icon},
      baseVersion: currentVersion,
    );
    return subcategoryId;
  }

  Future<void> deleteSubcategory(LocalSubcategory subcategory) async {
    final now = _now();
    await db.transaction(() async {
      await _clearSubcategoryReferences(subcategory, now);
      await _softDeleteSubcategory(subcategory, now);
    });
  }

  Future<void> _softDeleteSubcategory(
    LocalSubcategory subcategory,
    String now,
  ) async {
    await (db.update(
      db.localSubcategories,
    )..where((s) => s.id.equals(subcategory.id))).write(
      LocalSubcategoriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'subcategories',
      entityId: subcategory.id,
      op: 'delete',
      baseVersion: subcategory.version,
    );
  }

  /// Lançamentos e orçamentos bloqueiam a exclusão (ver
  /// [categoryHasReferences]); dívidas apenas perdem o vínculo.
  Future<void> _clearCategoryReferences(String categoryId, String now) async {
    final debts =
        await (db.select(db.localDebts)..where(
              (d) => d.deletedAt.isNull() & d.categoryId.equals(categoryId),
            ))
            .get();
    for (final debt in debts) {
      await (db.update(
        db.localDebts,
      )..where((d) => d.id.equals(debt.id))).write(
        LocalDebtsCompanion(
          categoryId: const Value(null),
          subcategoryId: const Value(null),
          budgetItemId: const Value(null),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'debts',
        entityId: debt.id,
        op: 'update',
        payload: {
          'category_id': null,
          'subcategory_id': null,
          'budget_item_id': null,
        },
        baseVersion: debt.version,
      );
    }
  }

  Future<void> _clearSubcategoryReferences(
    LocalSubcategory subcategory,
    String now,
  ) async {
    final transactions =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() & t.subcategoryId.equals(subcategory.id),
            ))
            .get();
    for (final tx in transactions) {
      await (db.update(
        db.localTransactions,
      )..where((t) => t.id.equals(tx.id))).write(
        LocalTransactionsCompanion(
          subcategoryId: const Value(null),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'transactions',
        entityId: tx.id,
        op: 'update',
        payload: {'subcategory_id': null},
        baseVersion: tx.version,
      );
    }

    final budgetItems =
        await (db.select(db.localBudgetItems)..where(
              (i) =>
                  i.deletedAt.isNull() & i.subcategoryId.equals(subcategory.id),
            ))
            .get();
    for (final item in budgetItems) {
      await _deleteBudgetItemLocal(item, now);
    }

    final debts =
        await (db.select(db.localDebts)..where(
              (d) =>
                  d.deletedAt.isNull() & d.subcategoryId.equals(subcategory.id),
            ))
            .get();
    for (final debt in debts) {
      await (db.update(
        db.localDebts,
      )..where((d) => d.id.equals(debt.id))).write(
        LocalDebtsCompanion(
          subcategoryId: const Value(null),
          budgetItemId: const Value(null),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'debts',
        entityId: debt.id,
        op: 'update',
        payload: {'subcategory_id': null, 'budget_item_id': null},
        baseVersion: debt.version,
      );
    }
  }

  // ---------------- Transações ----------------

  Stream<List<LocalTransaction>> watchTransactions({
    String? type,
    String? status,
  }) {
    final q = db.select(db.localTransactions)
      ..where((t) => t.deletedAt.isNull());
    if (type != null) q.where((t) => t.type.equals(type));
    if (status != null) q.where((t) => t.status.equals(status));
    q.orderBy([
      (t) => OrderingTerm.desc(t.competenceDate),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    q.limit(300);
    return q.watch();
  }

  Future<void> addTransaction({
    required String type,
    required String description,
    required double amount,
    required String date,
    required bool isPaid,
    String? accountId,
    String? cardId,
    String? categoryId,
    String? subcategoryId,
    String? notes,
    List<TransactionSplit>? categorySplits,
  }) async {
    final id = _uuid.v4();
    final dueDate = isPaid ? null : date;
    final paymentDate = isPaid ? date : null;
    final splitsJson = encodeTransactionSplits(categorySplits, amount);
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: id,
            type: type,
            description: description,
            amount: Value(isPaid ? amount : null),
            amountPlanned: Value(amount),
            competenceDate: date,
            dueDate: Value(dueDate),
            paymentDate: Value(paymentDate),
            status: Value(isPaid ? 'paid' : 'planned'),
            accountId: Value(accountId),
            cardId: Value(cardId),
            categoryId: Value(categoryId),
            subcategoryId: Value(subcategoryId),
            categorySplits: Value(splitsJson),
            notes: Value(notes),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'transactions',
      entityId: id,
      op: 'create',
      payload: {
        'type': type,
        'description': description,
        'amount': isPaid ? amount : null,
        'amount_planned': amount,
        'competence_date': date,
        'due_date': dueDate,
        'payment_date': paymentDate,
        'status': isPaid ? 'paid' : 'planned',
        'account_id': accountId,
        'card_id': cardId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'category_splits': splitsJson == null ? null : jsonDecode(splitsJson),
        'notes': notes,
      },
    );
  }

  /// Converte uma lacuna do orçamento exibida na agenda em um lançamento real.
  ///
  /// Despesas de conta entram como pagas, pois a baixa afeta o saldo da conta.
  /// Despesas vinculadas a cartão viram uma compra prevista na fatura indicada
  /// pela própria previsão, preservando o controle de limite/fatura.
  /// O valor pode ser maior que o previsto — previsões orçamentárias são
  /// estimadas e a despesa real pode superá-las.
  Future<void> launchBudgetAgendaExpense(
    FinancialAgendaEntry entry, {
    double? amount,
    String? paymentDate,
  }) async {
    if (!entry.isBudget || entry.type != 'expense') {
      throw ArgumentError.value(
        entry.description,
        'entry',
        'A baixa direta só se aplica a despesas de orçamento',
      );
    }
    final value = _roundMoney(amount ?? entry.amount);
    if (value <= 0) {
      throw ArgumentError.value(value, 'amount', 'Valor deve ser positivo');
    }
    final date =
        paymentDate ??
        entry.dueDate ??
        DateTime.now().toIso8601String().substring(0, 10);
    final isCard = entry.cardId != null && entry.cardId!.isNotEmpty;
    if (isCard) {
      final id = _uuid.v4();
      final dueDate = entry.dueDate ?? date;
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: id,
              type: 'expense',
              description: entry.description,
              amountPlanned: Value(value),
              competenceDate: date,
              dueDate: Value(dueDate),
              status: const Value('planned'),
              cardId: Value(entry.cardId),
              categoryId: Value(entry.categoryId),
              subcategoryId: Value(entry.subcategoryId),
              updatedAt: Value(_now()),
              syncStatus: const Value('pending'),
            ),
          );
      await _enqueue(
        entity: 'transactions',
        entityId: id,
        op: 'create',
        payload: {
          'type': 'expense',
          'description': entry.description,
          'amount': null,
          'amount_planned': value,
          'competence_date': date,
          'due_date': dueDate,
          'payment_date': null,
          'status': 'planned',
          'account_id': null,
          'card_id': entry.cardId,
          'category_id': entry.categoryId,
          'subcategory_id': entry.subcategoryId,
          'notes': null,
        },
      );
      return;
    }
    await addTransaction(
      type: 'expense',
      description: entry.description,
      amount: value,
      date: date,
      isPaid: true,
      accountId: entry.accountId,
      cardId: null,
      categoryId: entry.categoryId,
      subcategoryId: entry.subcategoryId,
    );
  }

  /// Fecha uma diferença de orçamento sem criar despesa realizada e sem mexer
  /// em saldo de conta/cartão. Ex.: orçamento de R$ 500, fatura real R$ 400.
  Future<void> settleBudgetAgendaDifference(
    FinancialAgendaEntry entry, {
    double? amount,
    String? paymentDate,
  }) async {
    if (!entry.isBudget || entry.type != 'expense') {
      throw ArgumentError.value(
        entry.description,
        'entry',
        'A baixa de diferença só se aplica a despesas de orçamento',
      );
    }
    final value = _roundMoney(amount ?? entry.amount);
    if (value <= 0) {
      throw ArgumentError.value(value, 'amount', 'Valor deve ser positivo');
    }
    if (value > _roundMoney(entry.amount)) {
      throw ArgumentError.value(value, 'amount', 'Valor maior que o pendente');
    }

    final id = _uuid.v4();
    final date =
        paymentDate ??
        entry.dueDate ??
        DateTime.now().toIso8601String().substring(0, 10);
    final notes = _budgetVarianceNote(
      amount: value,
      accountId: entry.accountId,
      cardId: entry.cardId,
      categoryId: entry.categoryId,
      subcategoryId: entry.subcategoryId,
    );
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: id,
            type: 'expense',
            description: 'Baixa diferença ${entry.description}',
            amount: const Value(null),
            amountPlanned: Value(value),
            competenceDate: date,
            dueDate: Value(entry.dueDate),
            paymentDate: Value(date),
            status: const Value('paid'),
            accountId: const Value(null),
            cardId: const Value(null),
            categoryId: Value(entry.categoryId),
            subcategoryId: Value(entry.subcategoryId),
            notes: Value(notes),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'transactions',
      entityId: id,
      op: 'create',
      payload: {
        'type': 'expense',
        'description': 'Baixa diferença ${entry.description}',
        'amount': null,
        'amount_planned': value,
        'competence_date': date,
        'due_date': entry.dueDate,
        'payment_date': date,
        'status': 'paid',
        'account_id': null,
        'card_id': null,
        'category_id': entry.categoryId,
        'subcategory_id': entry.subcategoryId,
        'notes': notes,
      },
    );
  }

  /// Fecha como diferença um lançamento previsto que ficou na agenda após
  /// estorno de uma baixa. O lançamento previsto é reduzido/removido e a parte
  /// fechada vira ajuste neutro de orçamento, sem movimentar conta/cartão.
  Future<void> settleAgendaTransactionDifference(
    LocalTransaction tx, {
    required double amount,
    String? paymentDate,
  }) async {
    if (tx.type != 'expense' ||
        (tx.status != 'planned' && tx.status != 'overdue')) {
      throw ArgumentError.value(
        tx.id,
        'transaction',
        'A baixa de diferença só se aplica a despesas previstas',
      );
    }
    if (_debtPaymentInfo(tx) != null || _goalMovementInfo(tx) != null) {
      throw ArgumentError.value(
        tx.id,
        'transaction',
        'Este lançamento possui vínculo próprio e não pode ser fechado como diferença',
      );
    }
    final plannedAmount = _roundMoney(tx.amountPlanned ?? tx.amount ?? 0);
    final settledAmount = _roundMoney(amount);
    if (settledAmount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Valor deve ser positivo');
    }
    if (settledAmount > plannedAmount) {
      throw ArgumentError.value(amount, 'amount', 'Valor maior que o previsto');
    }

    final adjustmentId = _uuid.v4();
    final now = _now();
    final date = paymentDate ?? tx.dueDate ?? tx.competenceDate;
    final notes = _budgetVarianceNote(
      amount: settledAmount,
      accountId: tx.accountId,
      cardId: tx.cardId,
      categoryId: tx.categoryId,
      subcategoryId: tx.subcategoryId,
    );
    final remaining = _roundMoney(plannedAmount - settledAmount);

    await db.transaction(() async {
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: adjustmentId,
              type: 'expense',
              description: 'Baixa diferença ${tx.description}',
              amount: const Value(null),
              amountPlanned: Value(settledAmount),
              competenceDate: date,
              dueDate: Value(tx.dueDate),
              paymentDate: Value(date),
              status: const Value('paid'),
              accountId: const Value(null),
              cardId: const Value(null),
              categoryId: Value(tx.categoryId),
              subcategoryId: Value(tx.subcategoryId),
              notes: Value(notes),
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );
      await _enqueue(
        entity: 'transactions',
        entityId: adjustmentId,
        op: 'create',
        payload: {
          'type': 'expense',
          'description': 'Baixa diferença ${tx.description}',
          'amount': null,
          'amount_planned': settledAmount,
          'competence_date': date,
          'due_date': tx.dueDate,
          'payment_date': date,
          'status': 'paid',
          'account_id': null,
          'card_id': null,
          'category_id': tx.categoryId,
          'subcategory_id': tx.subcategoryId,
          'notes': notes,
        },
      );

      if (remaining <= 0.009) {
        await (db.update(
          db.localTransactions,
        )..where((t) => t.id.equals(tx.id))).write(
          LocalTransactionsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
        await _enqueue(
          entity: 'transactions',
          entityId: tx.id,
          op: 'delete',
          baseVersion: tx.version,
        );
      } else {
        await (db.update(
          db.localTransactions,
        )..where((t) => t.id.equals(tx.id))).write(
          LocalTransactionsCompanion(
            amount: const Value(null),
            amountPlanned: Value(remaining),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
        await _enqueue(
          entity: 'transactions',
          entityId: tx.id,
          op: 'update',
          payload: {'amount': null, 'amount_planned': remaining},
          baseVersion: tx.version,
        );
      }
    });
  }

  /// Despesa no cartão de crédito, com parcelamento opcional.
  ///
  /// A compra entra como prevista (vira gasto real no pagamento da fatura),
  /// com vencimento calculado pelo fechamento/vencimento do cartão. No
  /// parcelamento, o valor é dividido igualmente e a sobra de centavos vai
  /// para a primeira parcela; cada parcela vence um mês após a anterior.
  Future<void> addCardExpense({
    required LocalCreditCard card,
    required String description,
    required double totalAmount,
    required String purchaseDate,
    int installments = 1,
    String? categoryId,
    String? subcategoryId,
    String? notes,
    List<TransactionSplit>? categorySplits,
  }) async {
    final groupId = installments > 1 ? _uuid.v4() : null;
    final cents = (totalAmount * 100).round();
    final perInstallment = cents ~/ installments;
    final remainder = cents - perInstallment * installments;
    final splitsJson = installments == 1
        ? encodeTransactionSplits(categorySplits, totalAmount)
        : null;
    if (installments > 1 && categorySplits?.isNotEmpty == true) {
      throw ArgumentError('Rateio não está disponível para compras parceladas');
    }
    final firstDueDate = cardDueDate(
      purchaseDate: purchaseDate,
      closingDay: card.closingDay,
      dueDay: card.dueDay,
    );

    for (var i = 0; i < installments; i++) {
      final amount = (perInstallment + (i == 0 ? remainder : 0)) / 100;
      final competence = i == 0 ? purchaseDate : addMonthsIso(purchaseDate, i);
      final dueDate = i == 0 ? firstDueDate : addMonthsIso(firstDueDate, i);
      final label = installments > 1
          ? '$description (${i + 1}/$installments)'
          : description;
      final id = _uuid.v4();

      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: id,
              type: 'expense',
              description: label,
              amountPlanned: Value(amount),
              competenceDate: competence,
              dueDate: Value(dueDate),
              status: const Value('planned'),
              cardId: Value(card.id),
              categoryId: Value(categoryId),
              subcategoryId: Value(subcategoryId),
              categorySplits: Value(splitsJson),
              notes: Value(notes),
              installmentNumber: Value(installments > 1 ? i + 1 : null),
              installmentTotal: Value(installments > 1 ? installments : null),
              updatedAt: Value(_now()),
              syncStatus: const Value('pending'),
            ),
          );
      await _enqueue(
        entity: 'transactions',
        entityId: id,
        op: 'create',
        payload: {
          'type': 'expense',
          'description': label,
          'amount_planned': amount,
          'competence_date': competence,
          'due_date': dueDate,
          'status': 'planned',
          'card_id': card.id,
          'category_id': categoryId,
          'subcategory_id': subcategoryId,
          'category_splits': splitsJson == null ? null : jsonDecode(splitsJson),
          'notes': notes,
          'installment_group_id': ?groupId,
          if (installments > 1) 'installment_number': i + 1,
          if (installments > 1) 'installment_total': installments,
        },
      );
    }
  }

  /// Crédito no cartão de crédito — ex.: estorno de contestação de valor.
  ///
  /// Entra como receita prevista na fatura (mesmo vencimento de uma compra na
  /// mesma data), reduzindo o valor a pagar e o limite usado. Não é parcelado.
  Future<void> addCardCredit({
    required LocalCreditCard card,
    required String description,
    required double amount,
    required String date,
    String? categoryId,
    String? subcategoryId,
    String? notes,
  }) async {
    final dueDate = cardDueDate(
      purchaseDate: date,
      closingDay: card.closingDay,
      dueDay: card.dueDay,
    );
    final id = _uuid.v4();
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: id,
            type: 'income',
            description: description,
            amountPlanned: Value(amount),
            competenceDate: date,
            dueDate: Value(dueDate),
            status: const Value('planned'),
            cardId: Value(card.id),
            categoryId: Value(categoryId),
            subcategoryId: Value(subcategoryId),
            notes: Value(notes),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'transactions',
      entityId: id,
      op: 'create',
      payload: {
        'type': 'income',
        'description': description,
        'amount_planned': amount,
        'competence_date': date,
        'due_date': dueDate,
        'status': 'planned',
        'card_id': card.id,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'notes': notes,
      },
    );
  }

  /// Despesas de um cartão (a fatura é o agrupamento pelo mês do vencimento).
  Stream<List<LocalTransaction>> watchCardTransactions(String cardId) =>
      (db.select(db.localTransactions)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.cardId.equals(cardId) &
                  t.status.isNotValue('canceled'),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.dueDate),
              (t) => OrderingTerm.desc(t.competenceDate),
            ]))
          .watch();

  /// Total ainda não pago no cartão (compromete o limite).
  Future<double> cardOpenAmount(String cardId) async {
    final rows =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.cardId.equals(cardId) &
                  t.status.isIn(['planned', 'overdue']),
            ))
            .get();
    // Receita no cartão (estorno/contestação) é crédito: abate o valor devido.
    final total = rows.fold<double>(0, (s, t) {
      final v = t.amountPlanned ?? t.amount ?? 0;
      return s + (t.type == 'income' ? -v : v);
    });
    return (total * 100).roundToDouble() / 100;
  }

  /// Pagamento de fatura: marca as despesas do cartão como pagas e cria a
  /// liquidação — um débito único na conta escolhida. A liquidação carrega
  /// account_id E card_id ao mesmo tempo, convenção que a exclui das
  /// estatísticas de gastos (o gasto real já foi contado em cada compra).
  Future<double> payCardInvoice({
    required LocalCreditCard card,
    required List<LocalTransaction> transactions,
    required String accountId,
    required String paymentDate,
  }) async {
    var total = 0.0;
    for (final tx in transactions) {
      if (tx.status != 'planned' && tx.status != 'overdue') continue;
      // Estornos (receita) abatem o valor líquido a pagar da fatura.
      final v = tx.amountPlanned ?? tx.amount ?? 0;
      total += tx.type == 'income' ? -v : v;
      await markPaid(tx);
    }
    total = (total * 100).roundToDouble() / 100;
    if (total <= 0) return 0;

    final id = _uuid.v4();
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: id,
            type: 'expense',
            description: 'Pagamento fatura ${card.name}',
            amount: Value(total),
            amountPlanned: Value(total),
            competenceDate: paymentDate,
            paymentDate: Value(paymentDate),
            status: const Value('paid'),
            accountId: Value(accountId),
            cardId: Value(card.id),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'transactions',
      entityId: id,
      op: 'create',
      payload: {
        'type': 'expense',
        'description': 'Pagamento fatura ${card.name}',
        'amount': total,
        'amount_planned': total,
        'competence_date': paymentDate,
        'payment_date': paymentDate,
        'status': 'paid',
        'account_id': accountId,
        'card_id': card.id,
      },
    );
    return total;
  }

  /// Liquidação de fatura: débito em conta vinculado a um cartão.
  static bool isInvoiceSettlement(LocalTransaction t) =>
      t.accountId != null && t.cardId != null;

  /// Pagamento gerado a partir de uma previsão de dívida/financiamento.
  static bool isDebtPayment(LocalTransaction t) => _debtPaymentInfo(t) != null;

  static DebtPaymentLink? debtPaymentLink(LocalTransaction t) =>
      _debtPaymentInfo(t);

  Stream<List<LocalTransaction>> watchDebtPayments(String debtId) {
    final q = db.select(db.localTransactions)
      ..where(
        (t) => t.deletedAt.isNull() & t.notes.like('$_debtPaymentNotePrefix%'),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.paymentDate),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    return q.watch().map(
      (rows) =>
          rows.where((tx) => _debtPaymentInfo(tx)?.debtId == debtId).toList(),
    );
  }

  /// Marca um lançamento como pago. [amount] permite registrar um realizado
  /// diferente do previsto (ex.: despesa estimada que veio maior); quando
  /// omitido, usa o valor previsto.
  Future<void> markPaid(
    LocalTransaction tx, {
    String? paymentDate,
    double? amount,
  }) async {
    final date = paymentDate ?? tx.dueDate ?? tx.competenceDate;
    final competenceDate = paymentDate ?? tx.competenceDate;
    final value = amount ?? tx.amountPlanned ?? tx.amount ?? 0;
    await (db.update(
      db.localTransactions,
    )..where((t) => t.id.equals(tx.id))).write(
      LocalTransactionsCompanion(
        status: const Value('paid'),
        amount: Value(value),
        competenceDate: Value(competenceDate),
        paymentDate: Value(date),
        updatedAt: Value(_now()),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'transactions',
      entityId: tx.id,
      op: 'update',
      payload: {
        'status': 'paid',
        'amount': value,
        'competence_date': competenceDate,
        'payment_date': date,
      },
      baseVersion: tx.version,
    );
  }

  /// Baixa um lançamento que já existe na agenda.
  ///
  /// Quando o valor informado é menor que o previsto, cria um lançamento pago
  /// com o valor baixado e mantém o lançamento original em aberto com o saldo.
  /// Quando é maior ou igual, o lançamento é pago com o valor informado — o
  /// previsto é mantido para o comparativo previsto × realizado.
  Future<void> settleAgendaTransaction(
    LocalTransaction tx, {
    required double amount,
    String? paymentDate,
  }) async {
    final plannedAmount = _roundMoney(tx.amountPlanned ?? tx.amount ?? 0);
    final paidAmount = _roundMoney(amount);
    if (paidAmount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Valor deve ser positivo');
    }
    if (plannedAmount - paidAmount <= 0.009) {
      await markPaid(tx, paymentDate: paymentDate, amount: paidAmount);
      return;
    }

    final remaining = _roundMoney(plannedAmount - paidAmount);
    final paymentId = _uuid.v4();
    final now = _now();
    final settledDate = paymentDate ?? tx.dueDate ?? tx.competenceDate;
    final competenceDate = paymentDate ?? tx.competenceDate;
    await db.transaction(() async {
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: paymentId,
              type: tx.type,
              description: tx.description,
              amount: Value(paidAmount),
              amountPlanned: Value(paidAmount),
              competenceDate: competenceDate,
              dueDate: Value(tx.dueDate),
              paymentDate: Value(settledDate),
              status: const Value('paid'),
              accountId: Value(tx.accountId),
              cardId: Value(tx.cardId),
              categoryId: Value(tx.categoryId),
              subcategoryId: Value(tx.subcategoryId),
              notes: Value(tx.notes),
              installmentNumber: Value(tx.installmentNumber),
              installmentTotal: Value(tx.installmentTotal),
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );
      await (db.update(
        db.localTransactions,
      )..where((t) => t.id.equals(tx.id))).write(
        LocalTransactionsCompanion(
          amount: const Value(null),
          amountPlanned: Value(remaining),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'transactions',
        entityId: paymentId,
        op: 'create',
        payload: {
          'type': tx.type,
          'description': tx.description,
          'amount': paidAmount,
          'amount_planned': paidAmount,
          'competence_date': competenceDate,
          'due_date': tx.dueDate,
          'payment_date': settledDate,
          'status': 'paid',
          'account_id': tx.accountId,
          'card_id': tx.cardId,
          'category_id': tx.categoryId,
          'subcategory_id': tx.subcategoryId,
          'notes': tx.notes,
          'installment_number': tx.installmentNumber,
          'installment_total': tx.installmentTotal,
        },
      );
      await _enqueue(
        entity: 'transactions',
        entityId: tx.id,
        op: 'update',
        payload: {'amount': null, 'amount_planned': remaining},
        baseVersion: tx.version,
      );
    });
  }

  /// Estorna um lançamento pago de volta para previsto: zera o realizado
  /// (`amount`/`paymentDate`) e mantém o valor previsto e o vencimento — para
  /// cartões, preserva o vencimento da fatura, evitando trocar a fatura.
  Future<void> markPlanned(LocalTransaction tx) async {
    final due = tx.dueDate ?? tx.competenceDate;
    final planned = tx.amountPlanned ?? tx.amount;
    await (db.update(
      db.localTransactions,
    )..where((t) => t.id.equals(tx.id))).write(
      LocalTransactionsCompanion(
        status: const Value('planned'),
        amount: const Value(null),
        amountPlanned: Value(planned),
        dueDate: Value(due),
        paymentDate: const Value(null),
        updatedAt: Value(_now()),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'transactions',
      entityId: tx.id,
      op: 'update',
      payload: {
        'status': 'planned',
        'amount': null,
        'amount_planned': planned,
        'due_date': due,
        'payment_date': null,
      },
      baseVersion: tx.version,
    );
  }

  /// Edita um lançamento avulso (conta ou cartão). Mantém a coerência entre
  /// status/valor/datas como em [addTransaction]: previsto guarda só
  /// `amountPlanned`; pago guarda também `amount` e a data de pagamento. Para
  /// itens que já eram agendados, preserva o vencimento ao marcar como pago.
  Future<void> updateTransaction({
    required LocalTransaction original,
    required String type,
    required String description,
    required double amount,
    required String date,
    required bool isPaid,
    String? accountId,
    String? cardId,
    String? categoryId,
    String? subcategoryId,
    List<TransactionSplit>? categorySplits,
  }) async {
    // Cartão: o vencimento é o da fatura — preserva-o em vez de recalcular pela
    // competência. Conta: previsto agenda para a data informada.
    final isCard = cardId != null && cardId.isNotEmpty;
    final dueDate = isPaid
        ? original.dueDate
        : (isCard ? (original.dueDate ?? date) : date);
    final paymentDate = isPaid ? (original.paymentDate ?? date) : null;
    final splitsJson = encodeTransactionSplits(categorySplits, amount);
    await (db.update(
      db.localTransactions,
    )..where((t) => t.id.equals(original.id))).write(
      LocalTransactionsCompanion(
        type: Value(type),
        description: Value(description),
        amount: Value(isPaid ? amount : null),
        amountPlanned: Value(amount),
        competenceDate: Value(date),
        dueDate: Value(dueDate),
        paymentDate: Value(paymentDate),
        status: Value(isPaid ? 'paid' : 'planned'),
        accountId: Value(accountId),
        cardId: Value(cardId),
        categoryId: Value(categoryId),
        subcategoryId: Value(subcategoryId),
        categorySplits: Value(splitsJson),
        updatedAt: Value(_now()),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'transactions',
      entityId: original.id,
      op: 'update',
      payload: {
        'type': type,
        'description': description,
        'amount': isPaid ? amount : null,
        'amount_planned': amount,
        'competence_date': date,
        'due_date': dueDate,
        'payment_date': paymentDate,
        'status': isPaid ? 'paid' : 'planned',
        'account_id': accountId,
        'card_id': cardId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'category_splits': splitsJson == null ? null : jsonDecode(splitsJson),
      },
      baseVersion: original.version,
    );
  }

  Future<void> updateDebtPaymentCategory({
    required LocalTransaction transaction,
    required String categoryId,
    String? subcategoryId,
  }) async {
    if (!isDebtPayment(transaction)) {
      throw ArgumentError.value(
        transaction.id,
        'transaction',
        'Lançamento não é uma baixa de dívida',
      );
    }
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(
        categoryId,
        'categoryId',
        'Categoria é obrigatória',
      );
    }
    final now = _now();
    await (db.update(
      db.localTransactions,
    )..where((t) => t.id.equals(transaction.id))).write(
      LocalTransactionsCompanion(
        categoryId: Value(categoryId),
        subcategoryId: Value(subcategoryId),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'transactions',
      entityId: transaction.id,
      op: 'update',
      payload: {
        'type': transaction.type,
        'description': transaction.description,
        'amount': transaction.amount,
        'amount_planned': transaction.amountPlanned,
        'competence_date': transaction.competenceDate,
        'due_date': transaction.dueDate,
        'payment_date': transaction.paymentDate,
        'status': transaction.status,
        'account_id': transaction.accountId,
        'card_id': transaction.cardId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'notes': transaction.notes,
        'installment_number': transaction.installmentNumber,
        'installment_total': transaction.installmentTotal,
      },
      baseVersion: transaction.version,
    );
  }

  Future<void> updateDebtPayment({
    required LocalTransaction transaction,
    required double amount,
    required String paymentDate,
    required String categoryId,
    String? subcategoryId,
  }) async {
    final info = _debtPaymentInfo(transaction);
    if (info == null || transaction.status != 'paid') {
      throw ArgumentError.value(
        transaction.id,
        'transaction',
        'Lançamento não é uma baixa de dívida',
      );
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Valor deve ser positivo');
    }
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(
        categoryId,
        'categoryId',
        'Categoria é obrigatória',
      );
    }
    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals(info.debtId))).getSingleOrNull();
    if (debt == null) return;
    final oldAmount = _roundMoney(
      transaction.amount ?? transaction.amountPlanned ?? 0,
    );
    final newAmount = _roundMoney(amount);
    final adjustedOutstanding = _roundMoney(
      (debt.outstandingBalance + oldAmount - newAmount).clamp(
        0,
        double.infinity,
      ),
    );
    final status = adjustedOutstanding <= 0 ? 'paid_off' : 'active';
    final now = _now();
    await db.transaction(() async {
      await (db.update(
        db.localTransactions,
      )..where((t) => t.id.equals(transaction.id))).write(
        LocalTransactionsCompanion(
          amount: Value(newAmount),
          amountPlanned: Value(newAmount),
          competenceDate: Value(paymentDate),
          paymentDate: Value(paymentDate),
          categoryId: Value(categoryId),
          subcategoryId: Value(subcategoryId),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await (db.update(
        db.localDebts,
      )..where((d) => d.id.equals(debt.id))).write(
        LocalDebtsCompanion(
          outstandingBalance: Value(adjustedOutstanding),
          status: Value(status),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'transactions',
        entityId: transaction.id,
        op: 'update',
        payload: {
          'type': transaction.type,
          'description': transaction.description,
          'amount': newAmount,
          'amount_planned': newAmount,
          'competence_date': paymentDate,
          'due_date': transaction.dueDate,
          'payment_date': paymentDate,
          'status': transaction.status,
          'account_id': transaction.accountId,
          'card_id': transaction.cardId,
          'category_id': categoryId,
          'subcategory_id': subcategoryId,
          'notes': transaction.notes,
          'installment_number': transaction.installmentNumber,
          'installment_total': transaction.installmentTotal,
        },
        baseVersion: transaction.version,
      );
      await _enqueue(
        entity: 'debts',
        entityId: debt.id,
        op: 'update',
        payload: _debtPayload(
          debt,
          outstandingBalance: adjustedOutstanding,
          status: status,
        ),
        baseVersion: debt.version,
      );
    });
  }

  Future<void> deleteTransaction(LocalTransaction tx) async {
    await db.transaction(() async {
      await _restoreDebtPayment(tx);
      await _restoreGoalMovement(tx);
      final now = _now();
      await (db.update(
        db.localTransactions,
      )..where((t) => t.id.equals(tx.id))).write(
        LocalTransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'transactions',
        entityId: tx.id,
        op: 'delete',
        baseVersion: tx.version,
      );
    });
  }

  // ---------------- Cartões de crédito ----------------

  Stream<List<LocalCreditCard>> watchCreditCards() =>
      (db.select(db.localCreditCards)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Future<void> upsertCreditCard({
    String? id,
    required String name,
    String? issuer,
    required double limitAmount,
    required int closingDay,
    required int dueDay,
    String? color,
    String? icon,
    bool isActive = true,
    String? defaultAccountId,
    int? currentVersion,
  }) async {
    final cardId = id ?? _uuid.v4();
    final payload = {
      'name': name,
      'issuer': issuer,
      'limit_amount': limitAmount,
      'closing_day': closingDay,
      'due_day': dueDay,
      'color': color,
      'icon': icon,
      'is_active': isActive,
      'default_account_id': defaultAccountId,
    };
    await db
        .into(db.localCreditCards)
        .insertOnConflictUpdate(
          LocalCreditCardsCompanion(
            id: Value(cardId),
            name: Value(name),
            issuer: Value(issuer),
            limitAmount: Value(limitAmount),
            closingDay: Value(closingDay),
            dueDay: Value(dueDay),
            color: Value(color),
            icon: Value(icon),
            isActive: Value(isActive),
            defaultAccountId: Value(defaultAccountId),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'credit_cards',
      entityId: cardId,
      op: id == null ? 'create' : 'update',
      payload: payload,
      baseVersion: currentVersion,
    );
  }

  Future<void> deleteCreditCard(LocalCreditCard card) async {
    await (db.update(
      db.localCreditCards,
    )..where((c) => c.id.equals(card.id))).write(
      LocalCreditCardsCompanion(
        deletedAt: Value(_now()),
        updatedAt: Value(_now()),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'credit_cards',
      entityId: card.id,
      op: 'delete',
      baseVersion: card.version,
    );
  }

  // ---------------- Metas ----------------

  Stream<List<LocalGoal>> watchGoals() =>
      (db.select(db.localGoals)
            ..where((g) => g.deletedAt.isNull())
            ..orderBy([(g) => OrderingTerm.asc(g.targetDate)]))
          .watch();

  Future<void> upsertGoal({
    String? id,
    required String name,
    required double targetAmount,
    String? targetDate,
    double accumulatedAmount = 0,
    String? linkedAccountId,
    String? color,
    String status = 'active',
    int? currentVersion,
  }) async {
    final goalId = id ?? _uuid.v4();
    await db
        .into(db.localGoals)
        .insertOnConflictUpdate(
          LocalGoalsCompanion(
            id: Value(goalId),
            name: Value(name),
            targetAmount: Value(targetAmount),
            targetDate: Value(targetDate),
            accumulatedAmount: Value(accumulatedAmount),
            linkedAccountId: Value(linkedAccountId),
            color: Value(color),
            status: Value(status),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'goals',
      entityId: goalId,
      op: id == null ? 'create' : 'update',
      payload: {
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate,
        'accumulated_amount': accumulatedAmount,
        'linked_account_id': linkedAccountId,
        'color': color,
        'status': status,
      },
      baseVersion: currentVersion,
    );
  }

  Future<void> deleteGoal(LocalGoal goal) => _softDeleteAndEnqueue(
    'goals',
    goal.id,
    goal.version,
    (id) => (db.update(db.localGoals)..where((g) => g.id.equals(id))).write(
      LocalGoalsCompanion(
        deletedAt: Value(_now()),
        updatedAt: Value(_now()),
        syncStatus: const Value('pending'),
      ),
    ),
  );

  static GoalMovementLink? goalMovementLink(LocalTransaction t) =>
      _goalMovementInfo(t);

  Stream<List<LocalTransaction>> watchGoalMovements(String goalId) {
    final q = db.select(db.localTransactions)
      ..where(
        (t) => t.deletedAt.isNull() & t.notes.like('$_goalMovementNotePrefix%'),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.paymentDate),
        (t) => OrderingTerm.desc(t.competenceDate),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    return q.watch().map(
      (rows) =>
          rows.where((tx) => _goalMovementInfo(tx)?.goalId == goalId).toList(),
    );
  }

  Future<void> upsertGoalMovement({
    required LocalGoal goal,
    LocalTransaction? transaction,
    required String movementType,
    required double amount,
    required String date,
    String? accountId,
    LocalCreditCard? card,
  }) async {
    if (movementType != 'contribution' && movementType != 'withdrawal') {
      throw ArgumentError.value(
        movementType,
        'movementType',
        'Tipo de movimentação inválido',
      );
    }
    final value = _roundMoney(amount);
    if (value <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Valor deve ser positivo');
    }
    if ((accountId == null || accountId.isEmpty) && card == null) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'Informe uma conta ou cartão',
      );
    }

    final oldInfo = transaction == null ? null : _goalMovementInfo(transaction);
    if (transaction != null && oldInfo == null) {
      throw ArgumentError.value(
        transaction.id,
        'transaction',
        'Lançamento não é uma movimentação de meta',
      );
    }
    final oldDelta = transaction == null
        ? 0.0
        : _goalMovementSignedAmount(transaction);
    final newDelta = movementType == 'withdrawal' ? -value : value;
    final txId = transaction?.id ?? _uuid.v4();
    final isCard = card != null;
    final txType = movementType == 'withdrawal' ? 'income' : 'expense';
    final description = movementType == 'withdrawal'
        ? 'Saque/transferência ${goal.name}'
        : 'Aporte ${goal.name}';
    final dueDate = isCard
        ? cardDueDate(
            purchaseDate: date,
            closingDay: card.closingDay,
            dueDay: card.dueDay,
          )
        : null;
    final status = isCard ? 'planned' : 'paid';
    final paidAmount = isCard ? null : value;
    final paymentDate = isCard ? null : date;
    final notes = _goalMovementNote(
      goalId: goal.id,
      movementType: movementType,
    );
    final now = _now();

    await db.transaction(() async {
      final currentGoal = await (db.select(
        db.localGoals,
      )..where((g) => g.id.equals(goal.id))).getSingle();
      final availableAfterRevertingOld = _roundMoney(
        currentGoal.accumulatedAmount - oldDelta,
      );
      if (movementType == 'withdrawal' &&
          availableAfterRevertingOld - value < -0.009) {
        throw ArgumentError.value(
          amount,
          'amount',
          'Valor maior que o acumulado da meta',
        );
      }
      final updatedAccumulated = _roundMoney(
        (availableAfterRevertingOld + newDelta).clamp(0, double.infinity),
      );
      final goalStatus = updatedAccumulated >= currentGoal.targetAmount
          ? 'done'
          : 'active';

      await db
          .into(db.localTransactions)
          .insertOnConflictUpdate(
            LocalTransactionsCompanion(
              id: Value(txId),
              type: Value(txType),
              description: Value(description),
              amount: Value(paidAmount),
              amountPlanned: Value(value),
              competenceDate: Value(date),
              dueDate: Value(dueDate),
              paymentDate: Value(paymentDate),
              status: Value(status),
              accountId: Value(isCard ? null : accountId),
              cardId: Value(card?.id),
              categoryId: const Value(null),
              subcategoryId: const Value(null),
              notes: Value(notes),
              version: Value(transaction?.version ?? 1),
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );
      await (db.update(
        db.localGoals,
      )..where((g) => g.id.equals(currentGoal.id))).write(
        LocalGoalsCompanion(
          accumulatedAmount: Value(updatedAccumulated),
          status: Value(goalStatus),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'transactions',
        entityId: txId,
        op: transaction == null ? 'create' : 'update',
        payload: {
          'type': txType,
          'description': description,
          'amount': paidAmount,
          'amount_planned': value,
          'competence_date': date,
          'due_date': dueDate,
          'payment_date': paymentDate,
          'status': status,
          'account_id': isCard ? null : accountId,
          'card_id': card?.id,
          'category_id': null,
          'subcategory_id': null,
          'notes': notes,
          'installment_number': null,
          'installment_total': null,
        },
        baseVersion: transaction?.version,
      );
      await _enqueue(
        entity: 'goals',
        entityId: currentGoal.id,
        op: 'update',
        payload: _goalPayload(
          currentGoal,
          accumulatedAmount: updatedAccumulated,
          status: goalStatus,
        ),
        baseVersion: currentGoal.version,
      );
    });
  }

  Future<void> deleteGoalMovement(LocalTransaction transaction) async {
    final info = _goalMovementInfo(transaction);
    if (info == null) {
      throw ArgumentError.value(
        transaction.id,
        'transaction',
        'Lançamento não é uma movimentação de meta',
      );
    }
    await db.transaction(() async {
      await _restoreGoalMovement(transaction);
      final now = _now();
      await (db.update(
        db.localTransactions,
      )..where((t) => t.id.equals(transaction.id))).write(
        LocalTransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'transactions',
        entityId: transaction.id,
        op: 'delete',
        baseVersion: transaction.version,
      );
    });
  }

  double _goalMovementSignedAmount(LocalTransaction transaction) {
    final info = _goalMovementInfo(transaction);
    if (info == null) return 0;
    final value = _roundMoney(
      transaction.amount ?? transaction.amountPlanned ?? 0,
    );
    return info.movementType == 'withdrawal' ? -value : value;
  }

  Future<void> _restoreGoalMovement(LocalTransaction transaction) async {
    final info = _goalMovementInfo(transaction);
    if (info == null) return;
    final goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals(info.goalId))).getSingleOrNull();
    if (goal == null) return;
    final restoredAccumulated = _roundMoney(
      (goal.accumulatedAmount - _goalMovementSignedAmount(transaction)).clamp(
        0,
        double.infinity,
      ),
    );
    final status = restoredAccumulated >= goal.targetAmount ? 'done' : 'active';
    final now = _now();
    await (db.update(db.localGoals)..where((g) => g.id.equals(goal.id))).write(
      LocalGoalsCompanion(
        accumulatedAmount: Value(restoredAccumulated),
        status: Value(status),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'goals',
      entityId: goal.id,
      op: 'update',
      payload: _goalPayload(
        goal,
        accumulatedAmount: restoredAccumulated,
        status: status,
      ),
      baseVersion: goal.version,
    );
  }

  Map<String, dynamic> _goalPayload(
    LocalGoal goal, {
    double? accumulatedAmount,
    String? status,
  }) {
    return {
      'name': goal.name,
      'target_amount': goal.targetAmount,
      'target_date': goal.targetDate,
      'accumulated_amount': accumulatedAmount ?? goal.accumulatedAmount,
      'linked_account_id': goal.linkedAccountId,
      'color': goal.color,
      'status': status ?? goal.status,
    };
  }

  // ---------------- Dívidas ----------------

  Stream<List<LocalDebt>> watchDebts() =>
      (db.select(db.localDebts)
            ..where((d) => d.deletedAt.isNull())
            ..orderBy([(d) => OrderingTerm.asc(d.name)]))
          .watch();

  Future<void> upsertDebt({
    String? id,
    required String name,
    required String type,
    String? institution,
    required double originalAmount,
    required double outstandingBalance,
    double interestRateMonthly = 0,
    int totalInstallments = 1,
    int paidInstallments = 0,
    double installmentAmount = 0,
    String? firstDueDate,
    int? dueDay,
    String? accountId,
    String? categoryId,
    String? subcategoryId,
    String? budgetItemId,
    String? budgetReferenceMonth,
    bool unlinkBudget = false,
    String status = 'active',
    int? currentVersion,
  }) async {
    final debtId = id ?? _uuid.v4();
    var linkedBudgetItemId = budgetItemId;
    if (unlinkBudget && budgetItemId != null) {
      await _deleteLinkedBudgetItem(budgetItemId);
      linkedBudgetItemId = null;
    } else if (budgetReferenceMonth != null &&
        categoryId != null &&
        categoryId.isNotEmpty) {
      linkedBudgetItemId = await _upsertDebtBudgetItem(
        id: budgetItemId,
        referenceMonth: budgetReferenceMonth,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        plannedAmount: _debtBudgetAmount(
          outstandingBalance: outstandingBalance,
          installmentAmount: installmentAmount,
          totalInstallments: totalInstallments,
          paidInstallments: paidInstallments,
        ),
        dueDay: _debtBudgetDueDay(firstDueDate, dueDay),
        accountId: accountId,
      );
    }
    await db
        .into(db.localDebts)
        .insertOnConflictUpdate(
          LocalDebtsCompanion(
            id: Value(debtId),
            name: Value(name),
            type: Value(type),
            institution: Value(institution),
            originalAmount: Value(originalAmount),
            outstandingBalance: Value(outstandingBalance),
            interestRateMonthly: Value(interestRateMonthly),
            totalInstallments: Value(totalInstallments),
            paidInstallments: Value(paidInstallments),
            installmentAmount: Value(installmentAmount),
            firstDueDate: Value(firstDueDate),
            dueDay: Value(dueDay),
            accountId: Value(accountId),
            categoryId: Value(categoryId),
            subcategoryId: Value(subcategoryId),
            budgetItemId: Value(linkedBudgetItemId),
            status: Value(status),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'debts',
      entityId: debtId,
      op: id == null ? 'create' : 'update',
      payload: {
        'name': name,
        'type': type,
        'institution': institution,
        'original_amount': originalAmount,
        'outstanding_balance': outstandingBalance,
        'interest_rate_monthly': interestRateMonthly,
        'total_installments': totalInstallments,
        'paid_installments': paidInstallments,
        'installment_amount': installmentAmount,
        'first_due_date': firstDueDate,
        'due_day': dueDay,
        'account_id': accountId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'budget_item_id': linkedBudgetItemId,
        'status': status,
      },
      baseVersion: currentVersion,
    );
  }

  Future<void> deleteDebt(LocalDebt debt) async {
    final now = _now();
    await db.transaction(() async {
      await (db.update(
        db.localDebts,
      )..where((d) => d.id.equals(debt.id))).write(
        LocalDebtsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'debts',
        entityId: debt.id,
        op: 'delete',
        baseVersion: debt.version,
      );
      final itemId = debt.budgetItemId;
      if (itemId != null && itemId.isNotEmpty) {
        final item = await (db.select(
          db.localBudgetItems,
        )..where((i) => i.id.equals(itemId))).getSingleOrNull();
        if (item != null && item.deletedAt == null) {
          await (db.update(
            db.localBudgetItems,
          )..where((i) => i.id.equals(itemId))).write(
            LocalBudgetItemsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );
          await _enqueue(
            entity: 'budget_items',
            entityId: itemId,
            op: 'delete',
            baseVersion: item.version,
          );
        }
      }
    });
  }

  double _debtBudgetAmount({
    required double outstandingBalance,
    required double installmentAmount,
    required int totalInstallments,
    required int paidInstallments,
  }) {
    if (installmentAmount > 0) return _roundMoney(installmentAmount);
    final remaining = (totalInstallments - paidInstallments).clamp(1, 600);
    return _roundMoney(outstandingBalance / remaining);
  }

  int? _debtBudgetDueDay(String? firstDueDate, int? dueDay) {
    if (dueDay != null) return dueDay;
    if (firstDueDate != null && firstDueDate.length >= 10) {
      return int.tryParse(firstDueDate.substring(8, 10));
    }
    return null;
  }

  Future<String> _upsertDebtBudgetItem({
    String? id,
    required String referenceMonth,
    required String categoryId,
    String? subcategoryId,
    required double plannedAmount,
    int? dueDay,
    String? accountId,
  }) async {
    final budget =
        await (db.select(db.localBudgets)
              ..where(
                (b) =>
                    b.deletedAt.isNull() &
                    b.referenceMonth.equals(referenceMonth),
              )
              ..limit(1))
            .getSingleOrNull();
    final budgetId =
        budget?.id ?? await createBudget(referenceMonth: referenceMonth);
    int? currentVersion;
    if (id != null) {
      final existing = await (db.select(
        db.localBudgetItems,
      )..where((i) => i.id.equals(id))).getSingleOrNull();
      currentVersion = existing?.version;
    }
    return upsertBudgetItem(
      id: id,
      budgetId: budgetId,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      plannedAmount: plannedAmount,
      isFixed: true,
      dueDay: dueDay,
      accountId: accountId,
      currentVersion: currentVersion,
    );
  }

  Future<void> _deleteLinkedBudgetItem(String itemId) async {
    final item = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.id.equals(itemId))).getSingleOrNull();
    if (item == null || item.deletedAt != null) return;
    await deleteBudgetItem(item);
  }

  Map<String, dynamic> _debtPayload(
    LocalDebt debt, {
    double? outstandingBalance,
    int? paidInstallments,
    String? status,
  }) => {
    'name': debt.name,
    'type': debt.type,
    'institution': debt.institution,
    'original_amount': debt.originalAmount,
    'outstanding_balance': outstandingBalance ?? debt.outstandingBalance,
    'interest_rate_monthly': debt.interestRateMonthly,
    'total_installments': debt.totalInstallments,
    'paid_installments': paidInstallments ?? debt.paidInstallments,
    'installment_amount': debt.installmentAmount,
    'first_due_date': debt.firstDueDate,
    'due_day': debt.dueDay,
    'account_id': debt.accountId,
    'category_id': debt.categoryId,
    'subcategory_id': debt.subcategoryId,
    'budget_item_id': debt.budgetItemId,
    'status': status ?? debt.status,
  };

  /// Paga uma parcela de dívida. [interestAmount] é a parte do valor pago
  /// referente a juros/multa (ex.: parcela em atraso): ela não amortiza o
  /// saldo devedor e vira um lançamento pago separado na categoria
  /// "Juros e Multas" (criada automaticamente se não existir).
  Future<void> payDebtInstallment({
    required LocalDebt debt,
    required double plannedAmount,
    required double amount,
    required String dueDate,
    required String paymentDate,
    required int installmentNumber,
    double interestAmount = 0,
    String? categoryId,
    String? subcategoryId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Valor deve ser positivo');
    }
    final interest = _roundMoney(interestAmount);
    if (interest < 0) {
      throw ArgumentError.value(
        interestAmount,
        'interestAmount',
        'Juros/multa não pode ser negativo',
      );
    }
    if (interest - amount >= -0.005) {
      throw ArgumentError.value(
        interestAmount,
        'interestAmount',
        'Juros/multa deve ser menor que o valor pago',
      );
    }
    final effectiveCategoryId = categoryId ?? debt.categoryId;
    final effectiveSubcategoryId = subcategoryId ?? debt.subcategoryId;
    if (effectiveCategoryId == null || effectiveCategoryId.isEmpty) {
      throw ArgumentError.value(
        categoryId,
        'categoryId',
        'Categoria da dívida é obrigatória para registrar a baixa',
      );
    }
    final paidAmount = _roundMoney(amount - interest);
    if (paidAmount - debt.outstandingBalance > 0.005) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Amortização maior que o saldo devedor',
      );
    }
    final interestCategoryId = interest > 0.005
        ? await _ensureInterestCategoryId()
        : null;
    final transactionId = _uuid.v4();
    final planned = _roundMoney(plannedAmount);
    final outstanding = _roundMoney(
      (debt.outstandingBalance - paidAmount).clamp(0, double.infinity),
    );
    final status = outstanding <= 0 ? 'paid_off' : 'active';
    final paidInstallments = status == 'paid_off'
        ? debt.totalInstallments
        : (debt.paidInstallments + 1).clamp(0, debt.totalInstallments).toInt();
    final installmentsAdvanced = paidInstallments - debt.paidInstallments;
    final now = _now();
    final description = debt.totalInstallments > 1
        ? 'Pagamento ${debt.name} ($installmentNumber/${debt.totalInstallments})'
        : 'Pagamento ${debt.name}';
    final notes = _debtPaymentNote(
      debtId: debt.id,
      dueDate: dueDate,
      installmentNumber: installmentNumber,
      installmentsAdvanced: installmentsAdvanced,
    );

    await db.transaction(() async {
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: transactionId,
              type: 'expense',
              description: description,
              amount: Value(paidAmount),
              amountPlanned: Value(planned),
              competenceDate: paymentDate,
              dueDate: Value(dueDate),
              paymentDate: Value(paymentDate),
              status: const Value('paid'),
              accountId: Value(debt.accountId),
              categoryId: Value(effectiveCategoryId),
              subcategoryId: Value(effectiveSubcategoryId),
              notes: Value(notes),
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );

      await (db.update(
        db.localDebts,
      )..where((d) => d.id.equals(debt.id))).write(
        LocalDebtsCompanion(
          outstandingBalance: Value(outstanding),
          paidInstallments: Value(paidInstallments),
          status: Value(status),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );

      await _enqueue(
        entity: 'transactions',
        entityId: transactionId,
        op: 'create',
        payload: {
          'type': 'expense',
          'description': description,
          'amount': paidAmount,
          'amount_planned': planned,
          'competence_date': paymentDate,
          'due_date': dueDate,
          'payment_date': paymentDate,
          'status': 'paid',
          'account_id': debt.accountId,
          'category_id': effectiveCategoryId,
          'subcategory_id': effectiveSubcategoryId,
          'notes': notes,
        },
      );
      await _enqueue(
        entity: 'debts',
        entityId: debt.id,
        op: 'update',
        payload: _debtPayload(
          debt,
          outstandingBalance: outstanding,
          paidInstallments: paidInstallments,
          status: status,
        ),
        baseVersion: debt.version,
      );

      if (interestCategoryId != null) {
        final interestTxId = _uuid.v4();
        final interestDescription = debt.totalInstallments > 1
            ? 'Juros/multa ${debt.name} ($installmentNumber/${debt.totalInstallments})'
            : 'Juros/multa ${debt.name}';
        await db
            .into(db.localTransactions)
            .insert(
              LocalTransactionsCompanion.insert(
                id: interestTxId,
                type: 'expense',
                description: interestDescription,
                amount: Value(interest),
                amountPlanned: Value(interest),
                competenceDate: paymentDate,
                paymentDate: Value(paymentDate),
                status: const Value('paid'),
                accountId: Value(debt.accountId),
                categoryId: Value(interestCategoryId),
                updatedAt: Value(now),
                syncStatus: const Value('pending'),
              ),
            );
        await _enqueue(
          entity: 'transactions',
          entityId: interestTxId,
          op: 'create',
          payload: {
            'type': 'expense',
            'description': interestDescription,
            'amount': interest,
            'amount_planned': interest,
            'competence_date': paymentDate,
            'due_date': null,
            'payment_date': paymentDate,
            'status': 'paid',
            'account_id': debt.accountId,
            'category_id': interestCategoryId,
            'subcategory_id': null,
            'notes': null,
          },
        );
      }
    });
  }

  /// Nome da categoria de despesa usada para juros/multa de dívidas em atraso.
  static const interestCategoryName = 'Juros e Multas';

  /// Localiza a categoria de despesa "Juros e Multas" (ignorando maiúsculas)
  /// ou cria uma, para separar os acréscimos por atraso da categoria da
  /// própria dívida.
  Future<String> _ensureInterestCategoryId() async {
    final categories = await (db.select(
      db.localCategories,
    )..where((c) => c.deletedAt.isNull() & c.type.equals('expense'))).get();
    for (final category in categories) {
      if (category.name.trim().toLowerCase() ==
          interestCategoryName.toLowerCase()) {
        return category.id;
      }
    }
    final id = _uuid.v4();
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: id,
            name: interestCategoryName,
            type: 'expense',
            icon: const Value('taxes'),
            color: const Value('#C44A4A'),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'categories',
      entityId: id,
      op: 'create',
      payload: {
        'name': interestCategoryName,
        'type': 'expense',
        'icon': 'taxes',
        'color': '#C44A4A',
      },
    );
    return id;
  }

  Future<void> _restoreDebtPayment(LocalTransaction tx) async {
    final info = _debtPaymentInfo(tx);
    if (info == null || tx.status != 'paid') return;
    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals(info.debtId))).getSingleOrNull();
    if (debt == null) return;

    final amount = _roundMoney(tx.amount ?? tx.amountPlanned ?? 0);
    final outstanding = _roundMoney(debt.outstandingBalance + amount);
    final paidInstallments = (debt.paidInstallments - info.installmentsAdvanced)
        .clamp(0, debt.totalInstallments)
        .toInt();
    final status = outstanding > 0 ? 'active' : debt.status;
    final now = _now();

    await (db.update(db.localDebts)..where((d) => d.id.equals(debt.id))).write(
      LocalDebtsCompanion(
        outstandingBalance: Value(outstanding),
        paidInstallments: Value(paidInstallments),
        status: Value(status),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'debts',
      entityId: debt.id,
      op: 'update',
      payload: _debtPayload(
        debt,
        outstandingBalance: outstanding,
        paidInstallments: paidInstallments,
        status: status,
      ),
      baseVersion: debt.version,
    );
  }

  // ---------------- Investimentos ----------------

  Stream<List<LocalInvestment>> watchInvestments() =>
      (db.select(db.localInvestments)
            ..where((i) => i.deletedAt.isNull())
            ..orderBy([(i) => OrderingTerm.asc(i.name)]))
          .watch();

  Stream<List<LocalInvestmentMovement>> watchInvestmentMovements(
    String investmentId,
  ) =>
      (db.select(db.localInvestmentMovements)
            ..where(
              (movement) =>
                  movement.deletedAt.isNull() &
                  movement.investmentId.equals(investmentId),
            )
            ..orderBy([
              (movement) => OrderingTerm.desc(movement.movementDate),
              (movement) => OrderingTerm.desc(movement.updatedAt),
            ]))
          .watch();

  /// Todas as movimentações de investimentos (todas as carteiras) — usado
  /// para reconstruir a evolução do patrimônio no gráfico da tela de
  /// investimentos.
  Stream<List<LocalInvestmentMovement>> watchAllInvestmentMovements() =>
      (db.select(db.localInvestmentMovements)
            ..where((movement) => movement.deletedAt.isNull())
            ..orderBy([(movement) => OrderingTerm.asc(movement.movementDate)]))
          .watch();

  Future<void> upsertInvestment({
    String? id,
    required String name,
    required String type,
    String? institution,
    double appliedAmount = 0,
    double currentAmount = 0,
    String? lastQuoteDate,
    int? currentVersion,
  }) async {
    final investmentId = id ?? _uuid.v4();
    await db
        .into(db.localInvestments)
        .insertOnConflictUpdate(
          LocalInvestmentsCompanion(
            id: Value(investmentId),
            name: Value(name),
            type: Value(type),
            institution: Value(institution),
            appliedAmount: Value(appliedAmount),
            currentAmount: Value(currentAmount),
            lastQuoteDate: Value(lastQuoteDate),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'investments',
      entityId: investmentId,
      op: id == null ? 'create' : 'update',
      payload: {
        'name': name,
        'type': type,
        'institution': institution,
        'applied_amount': appliedAmount,
        'current_amount': currentAmount,
        'last_quote_date': lastQuoteDate,
      },
      baseVersion: currentVersion,
    );
  }

  /// Registra uma alteração rápida na posição do investimento.
  ///
  /// deposit aumenta capital aplicado e saldo atual; withdrawal reduz apenas
  /// o saldo atual; yield representa rendimento e aumenta somente o saldo
  /// atual, sem distorcer o valor efetivamente aplicado.
  Future<void> registerInvestmentMovement({
    required LocalInvestment investment,
    required String movementType,
    required double amount,
    String? movementDate,
  }) async {
    if (!{'deposit', 'withdrawal', 'yield'}.contains(movementType)) {
      throw ArgumentError.value(
        movementType,
        'movementType',
        'Tipo de movimentação de investimento inválido',
      );
    }
    final value = _roundMoney(amount);
    if ((movementType == 'yield' && value == 0) ||
        (movementType != 'yield' && value <= 0)) {
      throw ArgumentError.value(
        amount,
        'amount',
        movementType == 'yield'
            ? 'Rendimento deve ser diferente de zero'
            : 'Valor deve ser positivo',
      );
    }

    final appliedAmount = _roundMoney(
      investment.appliedAmount + (movementType == 'deposit' ? value : 0),
    );
    final date =
        movementDate ?? DateTime.now().toIso8601String().substring(0, 10);
    final movementId = _uuid.v4();
    final now = _now();
    await db.transaction(() async {
      final existingMovements =
          await (db.select(db.localInvestmentMovements)..where(
                (movement) =>
                    movement.deletedAt.isNull() &
                    movement.investmentId.equals(investment.id),
              ))
              .get();
      final openingAdjustment = _roundMoney(
        investment.currentAmount - investment.appliedAmount,
      );
      if (existingMovements.isEmpty && openingAdjustment.abs() >= 0.005) {
        await _insertInvestmentMovement(
          investmentId: investment.id,
          movementType: 'yield',
          amount: openingAdjustment,
          movementDate: investment.lastQuoteDate ?? date,
          now: now,
        );
      }
      await db
          .into(db.localInvestmentMovements)
          .insert(
            LocalInvestmentMovementsCompanion.insert(
              id: movementId,
              investmentId: investment.id,
              type: movementType,
              amount: value,
              movementDate: date,
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );
      await _enqueue(
        entity: 'investment_movements',
        entityId: movementId,
        op: 'create',
        payload: {
          'investment_id': investment.id,
          'type': movementType,
          'amount': value,
          'movement_date': date,
        },
      );
      final currentAmount = await _calculatedInvestmentCurrentAmount(
        investment.id,
        appliedAmount,
      );
      await upsertInvestment(
        id: investment.id,
        name: investment.name,
        type: investment.type,
        institution: investment.institution,
        appliedAmount: appliedAmount,
        currentAmount: currentAmount,
        lastQuoteDate: date,
        currentVersion: investment.version,
      );
    });
  }

  Future<void> _insertInvestmentMovement({
    required String investmentId,
    required String movementType,
    required double amount,
    required String movementDate,
    required String now,
  }) async {
    final movementId = _uuid.v4();
    await db
        .into(db.localInvestmentMovements)
        .insert(
          LocalInvestmentMovementsCompanion.insert(
            id: movementId,
            investmentId: investmentId,
            type: movementType,
            amount: amount,
            movementDate: movementDate,
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'investment_movements',
      entityId: movementId,
      op: 'create',
      payload: {
        'investment_id': investmentId,
        'type': movementType,
        'amount': amount,
        'movement_date': movementDate,
      },
    );
  }

  Future<double> _calculatedInvestmentCurrentAmount(
    String investmentId,
    double appliedAmount,
  ) async {
    final movements =
        await (db.select(db.localInvestmentMovements)..where(
              (movement) =>
                  movement.deletedAt.isNull() &
                  movement.investmentId.equals(investmentId),
            ))
            .get();
    var current = appliedAmount;
    for (final movement in movements) {
      if (movement.type == 'withdrawal') {
        current -= movement.amount;
      } else if (movement.type == 'yield') {
        current += movement.amount;
      }
      // Aportes já compõem appliedAmount e aparecem no extrato para auditoria.
    }
    return _roundMoney(current);
  }

  Future<void> deleteInvestmentMovement({
    required LocalInvestment investment,
    required LocalInvestmentMovement movement,
  }) async {
    final now = _now();
    await db.transaction(() async {
      await (db.update(
        db.localInvestmentMovements,
      )..where((item) => item.id.equals(movement.id))).write(
        LocalInvestmentMovementsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
      await _enqueue(
        entity: 'investment_movements',
        entityId: movement.id,
        op: 'delete',
        baseVersion: movement.version,
      );
      final appliedAmount = _roundMoney(
        investment.appliedAmount -
            (movement.type == 'deposit' ? movement.amount : 0),
      );
      final currentAmount = await _calculatedInvestmentCurrentAmount(
        investment.id,
        appliedAmount,
      );
      await upsertInvestment(
        id: investment.id,
        name: investment.name,
        type: investment.type,
        institution: investment.institution,
        appliedAmount: appliedAmount,
        currentAmount: currentAmount,
        lastQuoteDate: DateTime.now().toIso8601String().substring(0, 10),
        currentVersion: investment.version,
      );
    });
  }

  Future<void> deleteInvestment(LocalInvestment investment) =>
      _softDeleteAndEnqueue(
        'investments',
        investment.id,
        investment.version,
        (id) => (db.update(db.localInvestments)..where((i) => i.id.equals(id)))
            .write(
              LocalInvestmentsCompanion(
                deletedAt: Value(_now()),
                updatedAt: Value(_now()),
                syncStatus: const Value('pending'),
              ),
            ),
      );

  // ---------------- Orçamento mensal ----------------

  /// Orçamento do mês (referenceMonth = YYYY-MM-01), se existir.
  Stream<LocalBudget?> watchBudgetForMonth(String referenceMonth) =>
      (db.select(db.localBudgets)
            ..where(
              (b) =>
                  b.deletedAt.isNull() &
                  b.referenceMonth.equals(referenceMonth),
            )
            ..limit(1))
          .watchSingleOrNull();

  Stream<List<LocalBudgetItem>> watchBudgetItems(String budgetId) => (db.select(
    db.localBudgetItems,
  )..where((i) => i.deletedAt.isNull() & i.budgetId.equals(budgetId))).watch();

  /// Todos os itens de orçamento (qualquer mês). Usado para reagir a mudanças
  /// nas previsões que compõem o saldo futuro das contas no dashboard.
  Stream<List<LocalBudgetItem>> watchAllBudgetItems() => (db.select(
    db.localBudgetItems,
  )..where((i) => i.deletedAt.isNull())).watch();

  Future<String> createBudget({required String referenceMonth}) async {
    final id = _uuid.v4();
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: id,
            referenceMonth: referenceMonth,
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'budgets',
      entityId: id,
      op: 'create',
      payload: {'reference_month': referenceMonth, 'scope': 'personal'},
    );
    return id;
  }

  /// Copia os itens do orçamento de outro mês para um novo orçamento.
  Future<String?> copyBudget({
    required String fromMonth,
    required String toMonth,
  }) async {
    final source =
        await (db.select(db.localBudgets)
              ..where(
                (b) =>
                    b.deletedAt.isNull() & b.referenceMonth.equals(fromMonth),
              )
              ..limit(1))
            .getSingleOrNull();
    if (source == null) return null;
    final items = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull() & i.budgetId.equals(source.id))).get();
    final newId = await createBudget(referenceMonth: toMonth);
    for (final item in items) {
      await upsertBudgetItem(
        budgetId: newId,
        categoryId: item.categoryId,
        subcategoryId: item.subcategoryId,
        plannedAmount: item.plannedAmount,
        isFixed: item.isFixed,
        dueDay: item.dueDay,
        accountId: item.accountId,
        cardId: item.cardId,
      );
    }
    return newId;
  }

  Future<String> upsertBudgetItem({
    String? id,
    required String budgetId,
    required String categoryId,
    String? subcategoryId,
    required double plannedAmount,
    bool isFixed = false,
    int? dueDay,
    String? accountId,
    String? cardId,
    int? currentVersion,
  }) async {
    final itemId = id ?? _uuid.v4();
    await db
        .into(db.localBudgetItems)
        .insertOnConflictUpdate(
          LocalBudgetItemsCompanion(
            id: Value(itemId),
            budgetId: Value(budgetId),
            categoryId: Value(categoryId),
            subcategoryId: Value(subcategoryId),
            plannedAmount: Value(plannedAmount),
            isFixed: Value(isFixed),
            dueDay: Value(dueDay),
            accountId: Value(accountId),
            cardId: Value(cardId),
            version: Value(currentVersion ?? 1),
            updatedAt: Value(_now()),
            syncStatus: const Value('pending'),
          ),
        );
    await _enqueue(
      entity: 'budget_items',
      entityId: itemId,
      op: id == null ? 'create' : 'update',
      payload: {
        'budget_id': budgetId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'planned_amount': plannedAmount,
        'is_fixed': isFixed,
        'due_day': dueDay,
        'account_id': accountId,
        'card_id': cardId,
      },
      baseVersion: currentVersion,
    );
    return itemId;
  }

  Future<void> deleteBudgetItem(LocalBudgetItem item) async {
    await db.transaction(() async {
      await _deleteBudgetItemLocal(item, _now());
    });
  }

  Future<void> _deleteBudgetItemLocal(LocalBudgetItem item, String now) async {
    await (db.update(
      db.localBudgetItems,
    )..where((i) => i.id.equals(item.id))).write(
      LocalBudgetItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
    await _enqueue(
      entity: 'budget_items',
      entityId: item.id,
      op: 'delete',
      baseVersion: item.version,
    );
  }

  /// Realizado por categoria e subcategoria em um mês (YYYY-MM), cobrindo
  /// despesas e receitas. Chaves: categoryId e 'categoryId|subcategoryId'.
  Future<Map<String, double>> realizedByCategoryForMonth(String month) async {
    final txs =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.type.isIn(['income', 'expense']) &
                  t.status.isNotValue('canceled') &
                  t.competenceDate.like('$month%'),
            ))
            .get();
    final result = <String, double>{};
    for (final t in txs) {
      if (isInvoiceSettlement(t)) continue;
      final v = (t.status == 'paid' ? t.amount : t.amountPlanned) ?? 0;
      final categoryId = t.categoryId;
      if (categoryId == null) continue;
      result[categoryId] = (result[categoryId] ?? 0) + v;
      if (t.subcategoryId != null) {
        final key = '$categoryId|${t.subcategoryId}';
        result[key] = (result[key] ?? 0) + v;
      }
    }
    return result;
  }

  /// Realizado do mês distribuído por item do orçamento.
  ///
  /// Cada lançamento é atribuído a no máximo um item. Itens com subcategoria
  /// e conta/cartão explícitos têm prioridade sobre itens genéricos, evitando
  /// que orçamentos repetidos para a mesma categoria dupliquem o realizado.
  Future<Map<String, double>> realizedByBudgetItemForMonth(
    String month,
    String budgetId,
  ) async {
    final items =
        await (db.select(db.localBudgetItems)..where(
              (item) =>
                  item.deletedAt.isNull() & item.budgetId.equals(budgetId),
            ))
            .get();
    final sortedItems = [...items]
      ..sort((a, b) {
        final specificity = _budgetItemSpecificity(
          b,
        ).compareTo(_budgetItemSpecificity(a));
        return specificity != 0 ? specificity : a.id.compareTo(b.id);
      });
    final result = {for (final item in items) item.id: 0.0};
    if (items.isEmpty) return result;

    final txs =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.type.isIn(['income', 'expense']) &
                  t.status.isNotValue('canceled') &
                  t.competenceDate.like('$month%'),
            ))
            .get();
    for (final tx in txs) {
      if (isInvoiceSettlement(tx)) continue;
      LocalBudgetItem? matched;
      for (final item in sortedItems) {
        if (_transactionMatchesBudgetItem(tx, item)) {
          matched = item;
          break;
        }
      }
      if (matched == null) continue;
      final value = _isBudgetVarianceSettlement(tx)
          ? _budgetVarianceAmount(tx)
          : (tx.status == 'paid' ? tx.amount : tx.amountPlanned) ?? 0;
      result[matched.id] = (result[matched.id] ?? 0) + value;
    }
    return result;
  }

  int _budgetItemSpecificity(LocalBudgetItem item) =>
      (item.subcategoryId == null ? 0 : 2) +
      ((item.accountId?.isNotEmpty ?? false) ||
              (item.cardId?.isNotEmpty ?? false)
          ? 1
          : 0);

  /// Gastos realizados/previstos por categoria em um mês (YYYY-MM).
  Future<Map<String, double>> spentByCategoryForMonth(String month) async {
    final txs =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.type.equals('expense') &
                  t.status.isNotValue('canceled') &
                  t.competenceDate.like('$month%'),
            ))
            .get();
    final result = <String, double>{};
    for (final t in txs) {
      if (isInvoiceSettlement(t)) continue;
      for (final split in transactionSplits(t)) {
        result[split.categoryId] =
            (result[split.categoryId] ?? 0) + split.amount;
      }
    }
    return result;
  }

  /// Receitas e despesas realizadas, agrupadas por mês, para o gráfico anual
  /// de fluxo de caixa do dashboard.
  Future<List<CashFlowMonthPoint>> cashFlowForYear(int year) async {
    final prefix = '$year-';
    final txs =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.equals('paid') &
                  t.competenceDate.like('$prefix%'),
            ))
            .get();
    final income = List<double>.filled(12, 0);
    final expense = List<double>.filled(12, 0);

    for (final transaction in txs) {
      if (isInvoiceSettlement(transaction)) continue;
      if (transaction.competenceDate.length < 7) continue;
      final month = int.tryParse(transaction.competenceDate.substring(5, 7));
      if (month == null || month < 1 || month > 12) continue;
      final value = transaction.amount ?? 0;
      if (transaction.type == 'income') {
        income[month - 1] += value;
      } else if (transaction.type == 'expense') {
        expense[month - 1] += value;
      }
    }

    return [
      for (var month = 1; month <= 12; month++)
        CashFlowMonthPoint(
          month: month,
          income: (income[month - 1] * 100).roundToDouble() / 100,
          expense: (expense[month - 1] * 100).roundToDouble() / 100,
        ),
    ];
  }

  /// Receitas e despesas realizadas em uma janela móvel terminada em
  /// [endMonth]. A série pode atravessar anos e sempre é devolvida em ordem
  /// cronológica.
  Future<List<CashFlowMonthPoint>> cashFlowForWindow(
    DateTime endMonth, {
    int months = 6,
  }) async {
    if (months < 1) return const [];

    final normalizedEnd = DateTime(endMonth.year, endMonth.month);
    final start = DateTime(
      normalizedEnd.year,
      normalizedEnd.month - months + 1,
    );
    final seriesByYear = <int, List<CashFlowMonthPoint>>{};
    for (var year = start.year; year <= normalizedEnd.year; year++) {
      seriesByYear[year] = await cashFlowForYear(year);
    }

    final result = <CashFlowMonthPoint>[];
    for (var index = 0; index < months; index++) {
      final month = DateTime(start.year, start.month + index);
      result.add(seriesByYear[month.year]![month.month - 1]);
    }
    return result;
  }

  /// Soft delete padrão: aplica a atualização local e enfileira a operação.
  Future<void> _softDeleteAndEnqueue(
    String entity,
    String id,
    int version,
    Future<int> Function(String id) applyLocal,
  ) async {
    await applyLocal(id);
    await _enqueue(
      entity: entity,
      entityId: id,
      op: 'delete',
      baseVersion: version,
    );
  }

  // ---------------- Indicadores do dashboard ----------------

  /// Indicadores do dashboard para o mês [forMonth] (padrão: mês atual).
  ///
  /// O período selecionado governa os agregados mensais — receitas, despesas e
  /// gastos por categoria — e também a agenda financeira: ela lista os
  /// compromissos em aberto de meses anteriores (não baixados) e os do mês
  /// selecionado; meses futuros só aparecem ao mudar o filtro de mês.
  /// Lançamentos de cartão são exceção: vencem na data da fatura (em geral no
  /// mês seguinte) e permanecem visíveis até o fim do mês seguinte ao
  /// selecionado. Saldos (consolidado e por conta) são sempre "do agora".
  Future<DashboardSummary> dashboardSummary({DateTime? forMonth}) async {
    final selected = forMonth ?? DateTime.now();
    final month =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}';
    final monthStart = '$month-01';
    final accounts = await (db.select(
      db.localAccounts,
    )..where((a) => a.deletedAt.isNull() & a.isActive.equals(true))).get();
    var totalBalance = 0.0;
    final accountBalances = <String, double>{};
    for (final acc in accounts) {
      final balance = await accountBalance(acc);
      accountBalances[acc.id] = balance;
      if (acc.includeInTotal) totalBalance += balance;
    }

    final txs =
        await (db.select(db.localTransactions)..where(
              (t) => t.deletedAt.isNull() & t.status.isNotValue('canceled'),
            ))
            .get();

    // O saldo de abertura é a posição real das contas no primeiro dia do mês:
    // saldo cadastrado + todos os lançamentos pagos anteriores. Assim a
    // "Economia do mês" não parece negativa apenas porque a renda do período
    // foi menor que uma despesa que pôde ser paga com saldo já existente.
    final accountsById = {for (final account in accounts) account.id: account};
    var monthOpeningBalance = accounts
        .where((account) => account.includeInTotal)
        .fold<double>(0, (sum, account) => sum + account.initialBalance);
    for (final tx in txs) {
      if (tx.status != 'paid' || tx.accountId == null) continue;
      final account = accountsById[tx.accountId];
      if (account == null || !account.includeInTotal) continue;
      final date = tx.paymentDate ?? tx.competenceDate;
      if (date.compareTo(monthStart) >= 0) continue;
      final value = tx.amount ?? 0;
      monthOpeningBalance += tx.type == 'income' ? value : -value;
    }
    monthOpeningBalance = _roundMoney(monthOpeningBalance);

    var income = 0.0;
    var expense = 0.0;
    final byCategory = <String, double>{};
    final bySubcategory = <String, double>{};
    final monthExpenseTransactions = <LocalTransaction>[];
    final upcoming = <LocalTransaction>[];
    final agendaEntries = <FinancialAgendaEntry>[];
    // Total em aberto por cartão (todas as faturas, inclusive parcelas de
    // faturas futuras) — o limite usado do cartão.
    final cardOpenByCard = <String, double>{};
    final today = DateTime.now().toIso8601String().substring(0, 10);
    // Janela da agenda: até o fim do mês selecionado. Inclui compromissos em
    // aberto de meses anteriores; o mês seguinte só entra mudando o filtro.
    final monthEnd = _monthEndDate(month);
    // Exceção: lançamentos de cartão vencem na data da fatura (em geral no mês
    // seguinte à compra) e precisam continuar visíveis — a janela deles vai até
    // o fim do mês seguinte ao selecionado. Parcelas de faturas mais distantes
    // continuam fora, para não poluir a agenda.
    final cardMonth = DateTime(selected.year, selected.month + 1);
    final cardWindowEnd = _monthEndDate(
      '${cardMonth.year.toString().padLeft(4, '0')}-'
      '${cardMonth.month.toString().padLeft(2, '0')}',
    );

    for (final t in txs) {
      // Liquidações de fatura não são gasto novo — as compras já contaram.
      if (isInvoiceSettlement(t)) continue;
      final inMonth = t.competenceDate.startsWith(month);
      if (inMonth && t.status == 'paid') {
        if (t.type == 'income') income += t.amount ?? 0;
        if (t.type == 'expense') expense += t.amount ?? 0;
      }
      if (inMonth && t.type == 'expense') {
        monthExpenseTransactions.add(t);
        for (final split in transactionSplits(t)) {
          byCategory[split.categoryId] =
              (byCategory[split.categoryId] ?? 0) + split.amount;
          if (split.subcategoryId != null) {
            final key = '${split.categoryId}|${split.subcategoryId}';
            bySubcategory[key] = (bySubcategory[key] ?? 0) + split.amount;
          }
        }
      }
      final isOpen = t.status == 'planned' || t.status == 'overdue';
      if (isOpen && t.cardId != null && t.cardId!.isNotEmpty) {
        // Receita (estorno) é crédito: reduz o limite usado do cartão.
        final v = t.amountPlanned ?? t.amount ?? 0;
        cardOpenByCard[t.cardId!] =
            (cardOpenByCard[t.cardId!] ?? 0) + (t.type == 'income' ? -v : v);
      }
      final agendaWindowEnd = (t.cardId != null && t.cardId!.isNotEmpty)
          ? cardWindowEnd
          : monthEnd;
      if (isOpen &&
          t.dueDate != null &&
          t.dueDate!.compareTo(agendaWindowEnd) <= 0) {
        upcoming.add(t);
        agendaEntries.add(FinancialAgendaEntry.fromTransaction(t));
      }
    }
    upcoming.sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
    for (final id in cardOpenByCard.keys.toList()) {
      cardOpenByCard[id] = (cardOpenByCard[id]! * 100).roundToDouble() / 100;
    }

    // Previsões de orçamento e dívidas acompanham o mês selecionado.
    final budgetAgendaEntries = await _budgetAgendaEntriesForMonth(
      month,
      txs,
      monthEnd,
      cardWindowEnd,
    );
    final debtAgendaEntries = await _debtAgendaEntriesForMonth(
      month,
      txs,
      monthEnd,
    );
    agendaEntries.addAll(budgetAgendaEntries);
    agendaEntries.addAll(debtAgendaEntries);
    agendaEntries.sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));

    final monthPlannedExpense = agendaEntries
        .where(
          (entry) =>
              entry.type == 'expense' &&
              (entry.dueDate ?? '').startsWith(month),
        )
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final budgetPlannedByCategory =
        await _budgetPlannedExpenseByCategoryForMonth(month);

    final budgetIncomeByAccount = <String, double>{};
    final budgetExpenseByAccount = <String, double>{};
    for (final entry in budgetAgendaEntries) {
      final accountId = entry.accountId;
      if (accountId == null || accountId.isEmpty) continue;
      final target = entry.type == 'income'
          ? budgetIncomeByAccount
          : budgetExpenseByAccount;
      target[accountId] = (target[accountId] ?? 0) + entry.amount;
    }

    return DashboardSummary(
      totalBalance: (totalBalance * 100).roundToDouble() / 100,
      monthOpeningBalance: monthOpeningBalance,
      monthIncome: income,
      monthExpense: expense,
      monthPlannedExpense: (monthPlannedExpense * 100).roundToDouble() / 100,
      spentByCategory: byCategory,
      spentBySubcategory: bySubcategory,
      expenseTransactions: monthExpenseTransactions,
      budgetPlannedByCategory: budgetPlannedByCategory,
      upcomingBills: upcoming,
      financialAgendaEntries: agendaEntries,
      accountBalances: accountBalances,
      cardOpenByCard: cardOpenByCard,
      budgetIncomeByAccount: budgetIncomeByAccount,
      budgetExpenseByAccount: budgetExpenseByAccount,
      overdueCount: agendaEntries
          .where((entry) => (entry.dueDate ?? '').compareTo(today) < 0)
          .length,
    );
  }

  Future<Map<String, double>> _budgetPlannedExpenseByCategoryForMonth(
    String month,
  ) async {
    final budget =
        await (db.select(db.localBudgets)
              ..where(
                (b) =>
                    b.deletedAt.isNull() & b.referenceMonth.equals('$month-01'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (budget == null) return const <String, double>{};

    final items = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull() & i.budgetId.equals(budget.id))).get();
    if (items.isEmpty) return const <String, double>{};

    final categories = await (db.select(
      db.localCategories,
    )..where((c) => c.deletedAt.isNull())).get();
    final categoryTypeById = {for (final c in categories) c.id: c.type};
    final result = <String, double>{};
    for (final item in items) {
      if (categoryTypeById[item.categoryId] != 'expense') continue;
      result[item.categoryId] =
          (result[item.categoryId] ?? 0) + item.plannedAmount;
    }
    return {
      for (final entry in result.entries)
        entry.key: (entry.value * 100).roundToDouble() / 100,
    };
  }

  /// Entradas de orçamento do mês [month] (YYYY-MM) para a agenda financeira.
  ///
  /// Para cada item, projeta a parte ainda **não concretizada**:
  /// `previsto − recebido/pago − previstos já na agenda`, onde
  /// - *recebido/pago* são transações liquidadas da mesma conta/categoria no
  ///   mês (já refletidas no saldo atual), e
  /// - *previstos já na agenda* são lançamentos `planned` da mesma conta/
  ///   categoria com vencimento na janela da agenda (subtraídos para não
  ///   contar em dobro com os lançamentos a vencer).
  ///
  /// Assim uma despesa apenas orçada entra na previsão, e uma já paga não entra
  /// de novo. Lançamentos de cartão seguem a janela estendida da fatura, para
  /// que uma compra do mês atual com vencimento no mês seguinte abata o
  /// orçamento vinculado ao cartão. Quando há item para subcategoria e para a
  /// categoria inteira, cada transação é abatida do item mais específico para
  /// evitar dupla contagem.
  Future<List<FinancialAgendaEntry>> _budgetAgendaEntriesForMonth(
    String month,
    List<LocalTransaction> txs,
    String windowEnd,
    String cardWindowEnd,
  ) async {
    final referenceMonth = '$month-01';
    final budget =
        await (db.select(db.localBudgets)
              ..where(
                (b) =>
                    b.deletedAt.isNull() &
                    b.referenceMonth.equals(referenceMonth),
              )
              ..limit(1))
            .getSingleOrNull();
    if (budget == null) return const <FinancialAgendaEntry>[];

    final items = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull() & i.budgetId.equals(budget.id))).get();
    if (items.isEmpty) return const <FinancialAgendaEntry>[];
    final linkedDebtBudgetItems = await _linkedDebtBudgetItemIds();

    final categories = await (db.select(
      db.localCategories,
    )..where((c) => c.deletedAt.isNull())).get();
    final categoryById = {for (final c in categories) c.id: c};
    final subcategoryById = {
      for (final s in await (db.select(
        db.localSubcategories,
      )..where((s) => s.deletedAt.isNull())).get())
        s.id: s,
    };

    final sortedItems =
        items.where((item) => !linkedDebtBudgetItems.contains(item.id)).toList()
          ..sort((a, b) {
            final aSpecific = a.subcategoryId == null ? 0 : 1;
            final bSpecific = b.subcategoryId == null ? 0 : 1;
            return bSpecific.compareTo(aSpecific);
          });
    final settledByItemId = {for (final item in sortedItems) item.id: 0.0};
    for (final tx in txs) {
      if (isInvoiceSettlement(tx)) continue;
      if (tx.status == 'canceled') continue;
      if (tx.type != 'income' && tx.type != 'expense') continue;
      if (!tx.competenceDate.startsWith(month)) continue;
      final isSettled = tx.status == 'paid';
      LocalBudgetItem? item;
      for (final candidate in sortedItems) {
        if (_transactionMatchesBudgetItem(tx, candidate)) {
          item = candidate;
          break;
        }
      }
      if (item == null) continue;
      final scheduleWindowEnd = tx.cardId != null && tx.cardId!.isNotEmpty
          ? cardWindowEnd
          : windowEnd;
      final isScheduled =
          (tx.status == 'planned' || tx.status == 'overdue') &&
          tx.dueDate != null &&
          tx.dueDate!.compareTo(scheduleWindowEnd) <= 0;
      if (!isSettled && !isScheduled) continue;
      final value = _isBudgetVarianceSettlement(tx)
          ? _budgetVarianceAmount(tx)
          : tx.status == 'paid'
          ? tx.amount ?? 0
          : tx.amountPlanned ?? tx.amount ?? 0;
      settledByItemId[item.id] = (settledByItemId[item.id] ?? 0) + value;
    }

    final entries = <FinancialAgendaEntry>[];
    for (final item in sortedItems) {
      final settled = settledByItemId[item.id] ?? 0;
      final gap = item.plannedAmount - settled;
      if (gap <= 0) continue;
      final category = categoryById[item.categoryId];
      final subcategory = item.subcategoryId == null
          ? null
          : subcategoryById[item.subcategoryId];
      final type = category?.type == 'income' ? 'income' : 'expense';
      entries.add(
        FinancialAgendaEntry(
          type: type,
          description: [
            category?.name ?? 'Sem categoria',
            if (subcategory != null) subcategory.name,
          ].join(' · '),
          amount: (gap * 100).roundToDouble() / 100,
          accountId: item.accountId,
          cardId: item.cardId,
          categoryId: item.categoryId,
          subcategoryId: item.subcategoryId,
          dueDate: _budgetDueDate(month, item.dueDay),
          isBudget: true,
        ),
      );
    }
    return entries;
  }

  bool _transactionMatchesBudgetItem(
    LocalTransaction tx,
    LocalBudgetItem item,
  ) {
    if (_isBudgetVarianceSettlement(tx)) {
      return _budgetVarianceMatchesBudgetItem(tx, item);
    }
    if (tx.categoryId != item.categoryId) return false;
    if (item.subcategoryId != null && tx.subcategoryId != item.subcategoryId) {
      return false;
    }
    if (item.accountId != null &&
        item.accountId!.isNotEmpty &&
        tx.accountId != item.accountId) {
      return false;
    }
    if (item.cardId != null &&
        item.cardId!.isNotEmpty &&
        tx.cardId != item.cardId) {
      return false;
    }
    return true;
  }

  bool _budgetVarianceMatchesBudgetItem(
    LocalTransaction tx,
    LocalBudgetItem item,
  ) {
    final data = _budgetVarianceData(tx);
    final categoryId = data?['category_id'] as String? ?? tx.categoryId;
    final subcategoryId =
        data?['subcategory_id'] as String? ?? tx.subcategoryId;
    final accountId = data?['account_id'] as String?;
    final cardId = data?['card_id'] as String?;
    if (categoryId != item.categoryId) return false;
    if (item.subcategoryId != null && subcategoryId != item.subcategoryId) {
      return false;
    }
    if (item.accountId != null &&
        item.accountId!.isNotEmpty &&
        accountId != item.accountId) {
      return false;
    }
    if (item.cardId != null &&
        item.cardId!.isNotEmpty &&
        cardId != item.cardId) {
      return false;
    }
    return true;
  }

  String _budgetDueDate(String month, int? dueDay) {
    final year = int.parse(month.substring(0, 4));
    final monthNumber = int.parse(month.substring(5, 7));
    final lastDay = DateTime(year, monthNumber + 1, 0).day;
    final day = (dueDay ?? lastDay).clamp(1, lastDay);
    return '$month-${day.toString().padLeft(2, '0')}';
  }

  String _monthEndDate(String month) {
    final year = int.parse(month.substring(0, 4));
    final monthNumber = int.parse(month.substring(5, 7));
    final lastDay = DateTime(year, monthNumber + 1, 0).day;
    return '$month-${lastDay.toString().padLeft(2, '0')}';
  }

  Future<Set<String>> _linkedDebtBudgetItemIds() async {
    final debts = await (db.select(
      db.localDebts,
    )..where((d) => d.deletedAt.isNull() & d.budgetItemId.isNotNull())).get();
    return {
      for (final debt in debts)
        if (debt.budgetItemId != null && debt.budgetItemId!.isNotEmpty)
          debt.budgetItemId!,
    };
  }

  Future<List<FinancialAgendaEntry>> _debtAgendaEntriesForMonth(
    String currentMonth,
    List<LocalTransaction> txs,
    String windowEnd,
  ) async {
    final debts =
        await (db.select(db.localDebts)..where(
              (d) =>
                  d.deletedAt.isNull() &
                  d.status.equals('active') &
                  d.outstandingBalance.isBiggerThanValue(0),
            ))
            .get();
    if (debts.isEmpty) return const <FinancialAgendaEntry>[];

    final paidMonthsByDebt = _paidDebtMonths(txs);
    final entries = <FinancialAgendaEntry>[];
    for (final debt in debts) {
      final remainingInstallments =
          (debt.totalInstallments - debt.paidInstallments).clamp(0, 600);
      if (remainingInstallments <= 0) continue;
      final defaultAmount = debt.installmentAmount > 0
          ? debt.installmentAmount
          : debt.outstandingBalance / remainingInstallments;
      var remainingBalance = debt.outstandingBalance;
      final paidMonths = paidMonthsByDebt[debt.id] ?? const <String>{};
      var monthShift = 0;
      for (var i = 0; i < remainingInstallments; i++) {
        final installmentNumber = debt.paidInstallments + i + 1;
        var dueDate = _debtDueDate(debt, currentMonth, i + monthShift);
        // Compromisso já liquidado não volta para a agenda: se a parcela do
        // mês foi baixada, o cronograma segue a partir do próximo mês aberto.
        while (paidMonths.contains(dueDate.substring(0, 7))) {
          monthShift++;
          dueDate = _debtDueDate(debt, currentMonth, i + monthShift);
        }
        if (dueDate.compareTo(windowEnd) > 0) break;
        final amount = defaultAmount > remainingBalance
            ? remainingBalance
            : defaultAmount;
        if (amount <= 0) break;
        remainingBalance -= amount;
        if (_hasMatchingOpenDebtTransaction(txs, debt, dueDate, amount)) {
          continue;
        }
        entries.add(
          FinancialAgendaEntry(
            type: 'expense',
            description:
                '${debt.name} · parcela $installmentNumber/${debt.totalInstallments}',
            amount: (amount * 100).roundToDouble() / 100,
            accountId: debt.accountId,
            categoryId: debt.categoryId,
            subcategoryId: debt.subcategoryId,
            dueDate: dueDate,
            isDebt: true,
            debt: debt,
            debtInstallmentNumber: installmentNumber,
          ),
        );
      }
    }
    return entries;
  }

  /// Meses (YYYY-MM) já cobertos por um pagamento liquidado de cada dívida,
  /// identificado pela nota estruturada gravada em [payDebtInstallment].
  Map<String, Set<String>> _paidDebtMonths(List<LocalTransaction> txs) {
    final result = <String, Set<String>>{};
    for (final tx in txs) {
      if (tx.status != 'paid') continue;
      final info = _debtPaymentInfo(tx);
      if (info == null) continue;
      final date = info.dueDate.length >= 7
          ? info.dueDate
          : (tx.paymentDate ?? tx.competenceDate);
      if (date.length < 7) continue;
      result
          .putIfAbsent(info.debtId, () => <String>{})
          .add(date.substring(0, 7));
    }
    return result;
  }

  String _debtDueDate(LocalDebt debt, String currentMonth, int offset) {
    if (debt.firstDueDate != null && debt.firstDueDate!.isNotEmpty) {
      return addMonthsIso(debt.firstDueDate!, debt.paidInstallments + offset);
    }
    final base = _budgetDueDate(
      currentMonth,
      debt.dueDay ?? DateTime.now().day,
    );
    return addMonthsIso(base, offset);
  }

  /// Próxima parcela em aberto de uma dívida ativa, pulando meses já
  /// baixados (identificados pela nota estruturada gravada em
  /// [payDebtInstallment]). Sem esse filtro, dívidas sem `first_due_date`
  /// mostrariam sempre o dia de vencimento do mês corrente, mesmo já pagas.
  DebtInstallmentPreview? nextOpenDebtInstallment(
    LocalDebt debt,
    List<LocalTransaction> txs,
  ) {
    if (debt.status != 'active' || debt.outstandingBalance <= 0) return null;
    final remaining = (debt.totalInstallments - debt.paidInstallments).clamp(
      0,
      600,
    );
    if (remaining <= 0) return null;
    final defaultAmount = debt.installmentAmount > 0
        ? debt.installmentAmount
        : debt.outstandingBalance / remaining;
    final now = DateTime.now();
    final currentMonth =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final paidMonths = _paidDebtMonths(txs)[debt.id] ?? const <String>{};
    var monthShift = 0;
    var dueDate = _debtDueDate(debt, currentMonth, monthShift);
    while (paidMonths.contains(dueDate.substring(0, 7)) &&
        monthShift < remaining) {
      monthShift++;
      dueDate = _debtDueDate(debt, currentMonth, monthShift);
    }
    final amount = defaultAmount > debt.outstandingBalance
        ? debt.outstandingBalance
        : defaultAmount;
    return DebtInstallmentPreview(
      dueDate: dueDate,
      installmentNumber: debt.paidInstallments + monthShift + 1,
      amount: (amount * 100).roundToDouble() / 100,
    );
  }

  bool _hasMatchingOpenDebtTransaction(
    List<LocalTransaction> txs,
    LocalDebt debt,
    String dueDate,
    double amount,
  ) {
    final roundedAmount = (amount * 100).round();
    for (final tx in txs) {
      if (isInvoiceSettlement(tx)) continue;
      if (tx.type != 'expense') continue;
      if (tx.status != 'planned' && tx.status != 'overdue') continue;
      if (tx.dueDate != dueDate) continue;
      if (debt.accountId != null &&
          debt.accountId!.isNotEmpty &&
          tx.accountId != debt.accountId) {
        continue;
      }
      final txAmount = (((tx.amountPlanned ?? tx.amount ?? 0) * 100).round());
      if (txAmount != roundedAmount) continue;
      final text = tx.description.toLowerCase();
      final debtName = debt.name.toLowerCase();
      final institution = debt.institution?.toLowerCase();
      if (text.contains(debtName) ||
          (institution != null &&
              institution.isNotEmpty &&
              text.contains(institution))) {
        return true;
      }
    }
    return false;
  }

  Future<List<PlannedEntry>> _debtPlannedEntriesForMonth(
    String month,
    List<LocalTransaction> txs,
  ) async {
    final debts =
        await (db.select(db.localDebts)..where(
              (d) =>
                  d.deletedAt.isNull() &
                  d.status.equals('active') &
                  d.outstandingBalance.isBiggerThanValue(0),
            ))
            .get();
    if (debts.isEmpty) return const <PlannedEntry>[];

    final monthEnd = _monthEndDate(month);
    final paidMonthsByDebt = _paidDebtMonths(txs);
    final entries = <PlannedEntry>[];
    for (final debt in debts) {
      final remainingInstallments =
          (debt.totalInstallments - debt.paidInstallments).clamp(0, 600);
      if (remainingInstallments <= 0) continue;
      final defaultAmount = debt.installmentAmount > 0
          ? debt.installmentAmount
          : debt.outstandingBalance / remainingInstallments;
      var remainingBalance = debt.outstandingBalance;
      final paidMonths = paidMonthsByDebt[debt.id] ?? const <String>{};
      var monthShift = 0;
      for (var i = 0; i < remainingInstallments; i++) {
        final installmentNumber = debt.paidInstallments + i + 1;
        var dueDate = _debtDueDate(debt, month, i + monthShift);
        // Parcela do mês já baixada: reprograma para o próximo mês aberto.
        while (paidMonths.contains(dueDate.substring(0, 7))) {
          monthShift++;
          dueDate = _debtDueDate(debt, month, i + monthShift);
        }
        if (dueDate.compareTo(monthEnd) > 0) break;
        final amount = defaultAmount > remainingBalance
            ? remainingBalance
            : defaultAmount;
        if (amount <= 0) break;
        remainingBalance -= amount;
        if (!dueDate.startsWith(month)) continue;
        if (_hasMatchingOpenDebtTransaction(txs, debt, dueDate, amount)) {
          continue;
        }
        entries.add(
          PlannedEntry(
            type: 'expense',
            description:
                '${debt.name} · parcela $installmentNumber/${debt.totalInstallments}',
            planned: _roundMoney(amount),
            realized: 0,
            categoryId: debt.categoryId,
            accountId: debt.accountId,
            subcategoryId: debt.subcategoryId,
            dueDate: dueDate,
            isDebt: true,
            debt: debt,
            debtInstallmentNumber: installmentNumber,
          ),
        );
      }
    }
    return entries;
  }

  /// Entradas do filtro "previstos" (receitas/despesas) do mês [month] (YYYY-MM).
  ///
  /// Combina, em uma visão única:
  /// - **Itens de orçamento** do mês: cada item vira uma linha prevista com
  ///   `planejado = plannedAmount` e `realizado = ` soma das transações pagas
  ///   que casam (mesma categoria, subcategoria quando definida e conta quando
  ///   definida). As transações que casam com um item de orçamento **não**
  ///   aparecem separadas — ficam representadas pela linha do orçamento.
  /// - **Transações previstas avulsas** (com vencimento) que não pertencem a
  ///   nenhum item de orçamento — como compras futuras de cartão de crédito,
  ///   que continuam listadas individualmente.
  /// - **Parcelas previstas de dívidas/financiamentos**, que podem virar uma
  ///   despesa realizada e amortizar o saldo da dívida.
  Future<List<PlannedEntry>> plannedEntriesForMonth(String month) async {
    final referenceMonth = '$month-01';
    final budget =
        await (db.select(db.localBudgets)
              ..where(
                (b) =>
                    b.deletedAt.isNull() &
                    b.referenceMonth.equals(referenceMonth),
              )
              ..limit(1))
            .getSingleOrNull();

    final items = budget == null
        ? <LocalBudgetItem>[]
        : await (db.select(db.localBudgetItems)..where(
                (i) => i.deletedAt.isNull() & i.budgetId.equals(budget.id),
              ))
              .get();
    final linkedDebtBudgetItems = await _linkedDebtBudgetItemIds();
    final visibleItems = items
        .where((item) => !linkedDebtBudgetItems.contains(item.id))
        .toList();

    final categories = await (db.select(
      db.localCategories,
    )..where((c) => c.deletedAt.isNull())).get();
    final categoryName = {for (final c in categories) c.id: c.name};
    final categoryType = {for (final c in categories) c.id: c.type};

    final txs =
        await (db.select(db.localTransactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.type.isIn(['income', 'expense']) &
                  t.status.isNotValue('canceled') &
                  t.competenceDate.like('$month%'),
            ))
            .get();

    bool matches(LocalTransaction t, LocalBudgetItem item) {
      if (isInvoiceSettlement(t)) return false;
      if (_isBudgetVarianceSettlement(t)) {
        return _budgetVarianceMatchesBudgetItem(t, item);
      }
      if (t.categoryId != item.categoryId) return false;
      if (item.subcategoryId != null && t.subcategoryId != item.subcategoryId) {
        return false;
      }
      if (item.accountId != null &&
          item.accountId!.isNotEmpty &&
          t.accountId != item.accountId) {
        return false;
      }
      if (item.cardId != null &&
          item.cardId!.isNotEmpty &&
          t.cardId != item.cardId) {
        return false;
      }
      return true;
    }

    // Cada transação casa com no máximo um item de orçamento (o primeiro),
    // evitando somar o realizado em dobro. As transações casadas ficam
    // acessíveis pela própria linha do orçamento (para conferência e edição).
    final realizedByItem = List<double>.filled(visibleItems.length, 0);
    final settledByItem = List<double>.filled(visibleItems.length, 0);
    final matchedByItem = List<List<LocalTransaction>>.generate(
      visibleItems.length,
      (_) => <LocalTransaction>[],
    );
    final matchedTxIds = <String>{};
    for (final t in txs) {
      final idx = visibleItems.indexWhere((item) => matches(t, item));
      if (idx < 0) continue;
      matchedTxIds.add(t.id);
      matchedByItem[idx].add(t);
      if (_isBudgetVarianceSettlement(t)) {
        settledByItem[idx] += _budgetVarianceAmount(t);
      } else if (t.status == 'paid') {
        final value = t.amount ?? 0;
        realizedByItem[idx] += value;
        settledByItem[idx] += value;
      }
    }

    final entries = <PlannedEntry>[];
    for (var i = 0; i < visibleItems.length; i++) {
      final item = visibleItems[i];
      final type = categoryType[item.categoryId] == 'income'
          ? 'income'
          : 'expense';
      entries.add(
        PlannedEntry(
          type: type,
          description: categoryName[item.categoryId] ?? 'Sem categoria',
          planned: item.plannedAmount,
          realized: realizedByItem[i],
          settled: settledByItem[i],
          categoryId: item.categoryId,
          subcategoryId: item.subcategoryId,
          accountId: item.accountId,
          cardId: item.cardId,
          dueDay: item.dueDay,
          isBudget: true,
          matchedTransactions: matchedByItem[i],
        ),
      );
    }

    entries.addAll(await _debtPlannedEntriesForMonth(month, txs));

    // Previstos avulsos: transações com vencimento que não pertencem a nenhum
    // item de orçamento (ex.: parcelas de cartão de crédito).
    for (final t in txs) {
      if (matchedTxIds.contains(t.id)) continue;
      if (t.dueDate == null) continue;
      if (isInvoiceSettlement(t)) continue;
      entries.add(
        PlannedEntry(
          type: t.type,
          description: t.description,
          planned: t.amountPlanned ?? t.amount ?? 0,
          realized: t.amount ?? 0,
          categoryId: t.categoryId,
          subcategoryId: t.subcategoryId,
          accountId: t.accountId,
          cardId: t.cardId,
          dueDate: t.dueDate,
          status: t.status,
          transaction: t,
        ),
      );
    }

    return entries;
  }
}

/// Uma linha do filtro "previstos": ou um item de orçamento (com o realizado
/// somado das transações que casam) ou uma transação prevista avulsa.
class PlannedEntry {
  const PlannedEntry({
    required this.type,
    required this.description,
    required this.planned,
    required this.realized,
    this.settled,
    this.categoryId,
    this.subcategoryId,
    this.accountId,
    this.cardId,
    this.dueDate,
    this.dueDay,
    this.status,
    this.isBudget = false,
    this.isDebt = false,
    this.debt,
    this.debtInstallmentNumber,
    this.transaction,
    this.matchedTransactions = const [],
  });

  final String type; // income | expense
  final String description;
  final double planned;
  final double realized;
  final double? settled;
  final String? categoryId;
  final String? subcategoryId;
  final String? accountId;
  final String? cardId;
  final String? dueDate;
  final int? dueDay;
  final String? status;
  final bool isBudget;
  final bool isDebt;
  final LocalDebt? debt;
  final int? debtInstallmentNumber;

  /// Transação subjacente, quando a linha é avulsa (permite ações como marcar
  /// pago). Nulo para linhas de orçamento e de dívida calculada.
  final LocalTransaction? transaction;

  /// Transações absorvidas por esta linha de orçamento (o "realizado" vem
  /// delas). Permitem conferir e editar um lançamento que casou com o item —
  /// ex.: valor digitado errado — sem procurá-lo na lista geral.
  final List<LocalTransaction> matchedTransactions;

  double get saldo => planned - (settled ?? realized);
}

/// Entrada unificada da agenda financeira do Dashboard.
///
/// Pode representar um lançamento real agendado ou uma lacuna do orçamento
/// mensal ainda não realizada.
class FinancialAgendaEntry {
  const FinancialAgendaEntry({
    required this.type,
    required this.description,
    required this.amount,
    required this.dueDate,
    this.accountId,
    this.cardId,
    this.categoryId,
    this.subcategoryId,
    this.isBudget = false,
    this.isDebt = false,
    this.debt,
    this.debtInstallmentNumber,
    this.transaction,
  });

  factory FinancialAgendaEntry.fromTransaction(LocalTransaction tx) {
    return FinancialAgendaEntry(
      type: tx.type,
      description: tx.description,
      amount: tx.amountPlanned ?? tx.amount ?? 0,
      accountId: tx.accountId,
      cardId: tx.cardId,
      categoryId: tx.categoryId,
      subcategoryId: tx.subcategoryId,
      dueDate: tx.dueDate,
      isBudget: false,
      isDebt: false,
      transaction: tx,
    );
  }

  final String type; // income | expense
  final String description;
  final double amount;
  final String? dueDate;
  final String? accountId;
  final String? cardId;
  final String? categoryId;
  final String? subcategoryId;
  final bool isBudget;
  final bool isDebt;
  final LocalDebt? debt;
  final int? debtInstallmentNumber;
  final LocalTransaction? transaction;
}

class DashboardSummary {
  const DashboardSummary({
    required this.totalBalance,
    required this.monthOpeningBalance,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthPlannedExpense,
    required this.spentByCategory,
    required this.spentBySubcategory,
    required this.expenseTransactions,
    required this.budgetPlannedByCategory,
    required this.upcomingBills,
    required this.financialAgendaEntries,
    required this.accountBalances,
    required this.cardOpenByCard,
    required this.budgetIncomeByAccount,
    required this.budgetExpenseByAccount,
    required this.overdueCount,
  });

  final double totalBalance;

  /// Saldo consolidado das contas no primeiro dia do mês selecionado.
  final double monthOpeningBalance;
  final double monthIncome;
  final double monthExpense;
  final double monthPlannedExpense;
  final Map<String, double> spentByCategory;
  final Map<String, double> spentBySubcategory;
  final List<LocalTransaction> expenseTransactions;
  final Map<String, double> budgetPlannedByCategory;
  final List<LocalTransaction> upcomingBills;
  final List<FinancialAgendaEntry> financialAgendaEntries;
  final Map<String, double> accountBalances;

  /// Total em aberto (não pago) por cartão, somando todas as faturas — inclusive
  /// parcelas de faturas futuras. É o limite consumido do cartão.
  final Map<String, double> cardOpenByCard;

  /// Receitas previstas ainda não realizadas por conta (lacuna orçado ×
  /// realizado), somadas às receitas e ao saldo futuro na agenda financeira.
  final Map<String, double> budgetIncomeByAccount;

  /// Despesas previstas ainda não realizadas por conta (lacuna orçado ×
  /// realizado), somadas às despesas e subtraídas do saldo futuro.
  final Map<String, double> budgetExpenseByAccount;
  final int overdueCount;

  double get monthResult => monthIncome - monthExpense - monthPlannedExpense;

  /// Posição estimada ao fim do mês: saldo de abertura mais o resultado do
  /// período. É o valor exibido como "Economia do mês".
  double get monthEconomy =>
      monthOpeningBalance + monthIncome - monthExpense - monthPlannedExpense;
}

class CashFlowMonthPoint {
  const CashFlowMonthPoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  final int month;
  final double income;
  final double expense;
}
