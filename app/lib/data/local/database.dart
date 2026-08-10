import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Colunas comuns de sincronização offline-first.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();
  TextColumn get deletedAt => text().nullable()();

  /// synced | pending | conflict — estado local em relação ao servidor.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
}

class LocalAccounts extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('checking'))();
  RealColumn get initialBalance => real().withDefault(const Constant(0))();
  TextColumn get bankName => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get includeInTotal =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCategories extends Table with SyncColumns {
  TextColumn get name => text()();

  /// income | expense
  TextColumn get type => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSubcategories extends Table with SyncColumns {
  TextColumn get categoryId => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalTransactions extends Table with SyncColumns {
  /// income | expense | transfer
  TextColumn get type => text()();
  TextColumn get description => text()();
  RealColumn get amount => real().nullable()();
  RealColumn get amountPlanned => real().nullable()();
  TextColumn get competenceDate => text()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get paymentDate => text().nullable()();

  /// planned | paid | overdue | canceled
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get accountId => text().nullable()();
  TextColumn get cardId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get subcategoryId => text().nullable()();

  /// JSON: [{category_id, subcategory_id?, amount}]. Mantém um único débito
  /// bancário e distribui seu valor nos relatórios por categoria.
  TextColumn get categorySplits => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get installmentNumber => integer().nullable()();
  IntColumn get installmentTotal => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCreditCards extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get issuer => text().nullable()();
  RealColumn get limitAmount => real().withDefault(const Constant(0))();
  IntColumn get closingDay => integer().withDefault(const Constant(1))();
  IntColumn get dueDay => integer().withDefault(const Constant(10))();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get defaultAccountId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalGoals extends Table with SyncColumns {
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  TextColumn get targetDate => text().nullable()();
  RealColumn get accumulatedAmount => real().withDefault(const Constant(0))();
  TextColumn get linkedAccountId => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();

  /// active | done | paused
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalDebts extends Table with SyncColumns {
  TextColumn get name => text()();

  /// loan | financing | installment_plan
  TextColumn get type => text().withDefault(const Constant('loan'))();
  TextColumn get institution => text().nullable()();
  RealColumn get originalAmount => real()();
  RealColumn get outstandingBalance => real()();
  RealColumn get interestRateMonthly => real().withDefault(const Constant(0))();
  IntColumn get totalInstallments => integer().withDefault(const Constant(1))();
  IntColumn get paidInstallments => integer().withDefault(const Constant(0))();
  RealColumn get installmentAmount => real().withDefault(const Constant(0))();
  TextColumn get firstDueDate => text().nullable()();
  IntColumn get dueDay => integer().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get subcategoryId => text().nullable()();
  TextColumn get budgetItemId => text().nullable()();

  /// active | paid_off | renegotiated
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalInvestments extends Table with SyncColumns {
  TextColumn get name => text()();

  /// fixed_income | stocks | funds | pension | crypto | other
  TextColumn get type => text().withDefault(const Constant('fixed_income'))();
  TextColumn get institution => text().nullable()();
  RealColumn get appliedAmount => real().withDefault(const Constant(0))();
  RealColumn get currentAmount => real().withDefault(const Constant(0))();
  TextColumn get lastQuoteDate => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalInvestmentMovements extends Table with SyncColumns {
  TextColumn get investmentId => text()();

  /// deposit | withdrawal | yield
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get movementDate => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalBudgets extends Table with SyncColumns {
  /// Primeiro dia do mês: YYYY-MM-01.
  TextColumn get referenceMonth => text()();

  /// personal | family
  TextColumn get scope => text().withDefault(const Constant('personal'))();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalBudgetItems extends Table with SyncColumns {
  TextColumn get budgetId => text()();
  TextColumn get categoryId => text()();
  TextColumn get subcategoryId => text().nullable()();
  RealColumn get plannedAmount => real().withDefault(const Constant(0))();
  BoolColumn get isFixed => boolean().withDefault(const Constant(false))();

  /// Dia do mês do vencimento/recebimento (1-31), para itens fixos.
  IntColumn get dueDay => integer().nullable()();

  /// Conta prevista de entrada (receita) ou saída (despesa). Quando definida,
  /// a previsão compõe o saldo futuro dessa conta.
  TextColumn get accountId => text().nullable()();

  /// Cartão de crédito previsto de saída (despesas recorrentes, ex.: assinaturas).
  /// Alternativa a [accountId] quando a despesa é cobrada no cartão.
  TextColumn get cardId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sugestões de lançamento geradas a partir de notificações bancárias
/// capturadas no Android. Dados 100% locais — nunca são sincronizados.
class LocalNotificationSuggestions extends Table {
  TextColumn get id => text()();
  TextColumn get sourcePackage => text()();
  TextColumn get sourceAppName => text().withDefault(const Constant(''))();

  /// Hash da notificação original (dedupe). Único por sugestão.
  TextColumn get notificationHash => text()();
  TextColumn get rawTitle => text().withDefault(const Constant(''))();
  TextColumn get rawText => text().withDefault(const Constant(''))();

  /// account_debit | account_credit | card_purchase | card_refund
  TextColumn get eventType => text()();

  /// income | expense
  TextColumn get transactionType => text()();
  RealColumn get amount => real()();
  TextColumn get description => text()();
  TextColumn get suggestedAccountId => text().nullable()();
  TextColumn get suggestedCardId => text().nullable()();
  TextColumn get suggestedCategoryId => text().nullable()();
  RealColumn get confidence => real().withDefault(const Constant(0))();

  /// pending | approved | ignored | duplicate
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Data/hora da notificação (ISO), usada como data do lançamento.
  TextColumn get receivedAt => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {notificationHash},
  ];
}

/// Fila de operações offline aguardando push para o servidor.
class PendingOperations extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get operationId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// create | update | delete
  TextColumn get op => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get clientUpdatedAt => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// Chave/valor de estado da sincronização (cursor do pull, device_id...).
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    LocalAccounts,
    LocalCategories,
    LocalSubcategories,
    LocalTransactions,
    LocalCreditCards,
    LocalGoals,
    LocalDebts,
    LocalInvestments,
    LocalInvestmentMovements,
    LocalBudgets,
    LocalBudgetItems,
    LocalNotificationSuggestions,
    PendingOperations,
    SyncState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'hopecash',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  /// Para testes: banco em memória.
  AppDatabase.test(super.executor);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localCreditCards);
      }
      if (from < 3) {
        await m.createTable(localGoals);
        await m.createTable(localDebts);
        await m.createTable(localInvestments);
        await m.createTable(localBudgets);
        await m.createTable(localBudgetItems);
      }
      if (from < 4) {
        await m.addColumn(localTransactions, localTransactions.cardId);
        await m.addColumn(
          localTransactions,
          localTransactions.installmentNumber,
        );
        await m.addColumn(
          localTransactions,
          localTransactions.installmentTotal,
        );
      }
      if (from < 5) {
        await m.createTable(localSubcategories);
        await m.addColumn(localTransactions, localTransactions.subcategoryId);
      }
      if (from < 6) {
        await m.addColumn(localBudgetItems, localBudgetItems.subcategoryId);
        await m.addColumn(localBudgetItems, localBudgetItems.dueDay);
      }
      if (from < 7) {
        await m.addColumn(localBudgetItems, localBudgetItems.accountId);
      }
      if (from < 8) {
        await m.addColumn(localDebts, localDebts.accountId);
      }
      if (from < 9) {
        await m.addColumn(localBudgetItems, localBudgetItems.cardId);
      }
      if (from < 10) {
        await m.addColumn(localDebts, localDebts.categoryId);
        await m.addColumn(localDebts, localDebts.subcategoryId);
        await m.addColumn(localDebts, localDebts.budgetItemId);
      }
      if (from < 11) {
        await m.createTable(localNotificationSuggestions);
      }
      if (from < 12) {
        await m.createTable(localInvestmentMovements);
      }
      if (from < 13) {
        await m.addColumn(localTransactions, localTransactions.categorySplits);
      }
    },
  );

  Future<String?> stateValue(String key) async {
    final row = await (select(
      syncState,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setStateValue(String key, String value) => into(
    syncState,
  ).insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));
}
