import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/repositories/finance_repository.dart';

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void main() {
  late AppDatabase db;
  late FinanceRepository repository;

  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
    repository = FinanceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'rateio mantém lançamento único e distribui o gasto por categoria',
    () async {
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: 'pix-coagru',
              type: 'expense',
              description: 'PIX Coagru',
              amount: const Value(756.57),
              amountPlanned: const Value(756.57),
              competenceDate: '2026-08-01',
              status: const Value('paid'),
              categorySplits: Value(
                jsonEncode([
                  {'category_id': 'vehicle', 'amount': 669.57},
                  {'category_id': 'market', 'amount': 87.0},
                ]),
              ),
            ),
          );

      final totals = await repository.spentByCategoryForMonth('2026-08');
      final transactions = await db.select(db.localTransactions).get();

      expect(transactions, hasLength(1));
      expect(totals, {'vehicle': 669.57, 'market': 87.0});
    },
  );

  test('economia mensal parte do saldo de abertura das contas', () async {
    await db
        .into(db.localAccounts)
        .insert(
          LocalAccountsCompanion.insert(
            id: 'opening-account',
            name: 'Conta principal',
            initialBalance: const Value(1000),
          ),
        );
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: 'before-month',
            type: 'expense',
            description: 'Despesa anterior',
            amount: const Value(250),
            competenceDate: '2026-07-20',
            paymentDate: const Value('2026-07-20'),
            status: const Value('paid'),
            accountId: const Value('opening-account'),
          ),
        );
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: 'month-expense',
            type: 'expense',
            description: 'Mercado',
            amount: const Value(200),
            competenceDate: '2026-08-02',
            paymentDate: const Value('2026-08-02'),
            status: const Value('paid'),
            accountId: const Value('opening-account'),
          ),
        );

    final summary = await repository.dashboardSummary(
      forMonth: DateTime(2026, 8),
    );

    expect(summary.monthOpeningBalance, 750);
    expect(summary.monthResult, -200);
    expect(summary.monthEconomy, 550);
  });

  test('fluxo de caixa móvel traz seis meses e atravessa o ano', () async {
    final transactions = [
      ('outside-before', 'income', 100.0, '2025-07-10'),
      ('first-month', 'income', 10.0, '2025-08-10'),
      ('previous-year', 'expense', 20.0, '2025-12-10'),
      ('last-month', 'income', 30.0, '2026-01-10'),
      ('outside-after', 'income', 40.0, '2026-02-10'),
    ];
    for (final (id, type, amount, date) in transactions) {
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: id,
              type: type,
              description: id,
              amount: Value(amount),
              competenceDate: date,
              status: const Value('paid'),
            ),
          );
    }

    final points = await repository.cashFlowForWindow(
      DateTime(2026, 1),
      months: 6,
    );

    expect(points.map((point) => point.month), [8, 9, 10, 11, 12, 1]);
    expect(points.map((point) => point.income), [10, 0, 0, 0, 0, 30]);
    expect(points.map((point) => point.expense), [0, 0, 0, 0, 20, 0]);
  });

  test('rendimento aumenta saldo sem alterar capital aplicado', () async {
    await repository.upsertInvestment(
      id: 'investment-yield',
      name: 'CDB',
      type: 'fixed_income',
      appliedAmount: 1000,
      currentAmount: 1000,
      lastQuoteDate: '2026-07-01',
    );
    var investment = await (db.select(
      db.localInvestments,
    )..where((item) => item.id.equals('investment-yield'))).getSingle();

    await repository.registerInvestmentMovement(
      investment: investment,
      movementType: 'yield',
      amount: 25.75,
      movementDate: '2026-07-16',
    );

    investment = await (db.select(
      db.localInvestments,
    )..where((item) => item.id.equals('investment-yield'))).getSingle();
    expect(investment.appliedAmount, 1000);
    expect(investment.currentAmount, 1025.75);
    expect(investment.lastQuoteDate, '2026-07-16');

    final movements = await db.select(db.localInvestmentMovements).get();
    expect(movements, hasLength(1));
    expect(movements.single.investmentId, investment.id);
    expect(movements.single.type, 'yield');
    expect(movements.single.amount, 25.75);
    expect(movements.single.movementDate, '2026-07-16');

    final movementOperation =
        await (db.select(db.pendingOperations)..where(
              (operation) => operation.entity.equals('investment_movements'),
            ))
            .getSingle();
    final payload =
        jsonDecode(movementOperation.payload!) as Map<String, dynamic>;
    expect(payload['investment_id'], investment.id);
    expect(payload['type'], 'yield');
    expect(payload['amount'], 25.75);
  });

  test(
    'exclusão de movimentações recalcula a posição do investimento',
    () async {
      await repository.upsertInvestment(
        id: 'investment-statement',
        name: 'Fundo',
        type: 'funds',
        appliedAmount: 1000,
        currentAmount: 1000,
      );

      Future<LocalInvestment> investment() => (db.select(
        db.localInvestments,
      )..where((item) => item.id.equals('investment-statement'))).getSingle();

      await repository.registerInvestmentMovement(
        investment: await investment(),
        movementType: 'deposit',
        amount: 200,
      );
      await repository.registerInvestmentMovement(
        investment: await investment(),
        movementType: 'withdrawal',
        amount: 50,
      );
      await repository.registerInvestmentMovement(
        investment: await investment(),
        movementType: 'yield',
        amount: -20,
      );

      var current = await investment();
      expect(current.appliedAmount, 1200);
      expect(current.currentAmount, 1130);

      final movements = await db.select(db.localInvestmentMovements).get();
      final deposit = movements.singleWhere((item) => item.type == 'deposit');
      final withdrawal = movements.singleWhere(
        (item) => item.type == 'withdrawal',
      );
      final negativeYield = movements.singleWhere(
        (item) => item.type == 'yield',
      );

      await repository.deleteInvestmentMovement(
        investment: current,
        movement: deposit,
      );
      current = await investment();
      expect(current.appliedAmount, 1000);
      expect(current.currentAmount, 930);

      await repository.deleteInvestmentMovement(
        investment: current,
        movement: withdrawal,
      );
      current = await investment();
      expect(current.currentAmount, 980);

      await repository.deleteInvestmentMovement(
        investment: current,
        movement: negativeYield,
      );
      current = await investment();
      expect(current.currentAmount, 1000);
      expect(
        await (db.select(
          db.localInvestmentMovements,
        )..where((item) => item.deletedAt.isNull())).get(),
        isEmpty,
      );
    },
  );

  test(
    'orçamento vinculado a cartão só casa com transações do mesmo cartão',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final dueTomorrow = _isoDate(now.add(const Duration(days: 1)));

      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-tires',
              name: 'Troca pneu',
              type: 'expense',
            ),
          );
      await db
          .into(db.localCreditCards)
          .insert(
            LocalCreditCardsCompanion.insert(
              id: 'card-a',
              name: 'Cartão A',
              closingDay: const Value(1),
              dueDay: const Value(5),
            ),
          );
      await db
          .into(db.localCreditCards)
          .insert(
            LocalCreditCardsCompanion.insert(
              id: 'card-b',
              name: 'Cartão B',
              closingDay: const Value(1),
              dueDay: const Value(5),
            ),
          );
      await db
          .into(db.localBudgets)
          .insert(
            LocalBudgetsCompanion.insert(
              id: 'budget-current',
              referenceMonth: '$month-01',
            ),
          );
      await db
          .into(db.localBudgetItems)
          .insert(
            LocalBudgetItemsCompanion.insert(
              id: 'budget-card-a',
              budgetId: 'budget-current',
              categoryId: 'cat-tires',
              plannedAmount: const Value(200),
              isFixed: const Value(true),
              dueDay: const Value(5),
              cardId: const Value('card-a'),
            ),
          );
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: 'tx-card-b',
              type: 'expense',
              description: 'Troca pneu',
              amountPlanned: const Value(200),
              competenceDate: '$month-01',
              dueDate: Value(dueTomorrow),
              status: const Value('planned'),
              cardId: const Value('card-b'),
              categoryId: const Value('cat-tires'),
            ),
          );

      final planned = await repository.plannedEntriesForMonth(month);
      expect(
        planned,
        contains(
          isA<PlannedEntry>()
              .having((entry) => entry.isBudget, 'isBudget', isTrue)
              .having((entry) => entry.cardId, 'cardId', 'card-a')
              .having((entry) => entry.saldo, 'saldo', 200),
        ),
      );
      expect(
        planned,
        contains(
          isA<PlannedEntry>()
              .having(
                (entry) => entry.transaction?.id,
                'transaction id',
                'tx-card-b',
              )
              .having((entry) => entry.cardId, 'cardId', 'card-b'),
        ),
      );

      final summary = await repository.dashboardSummary(forMonth: now);
      expect(
        summary.financialAgendaEntries,
        contains(
          isA<FinancialAgendaEntry>()
              .having((entry) => entry.isBudget, 'isBudget', isTrue)
              .having((entry) => entry.description, 'description', 'Troca pneu')
              .having((entry) => entry.cardId, 'cardId', 'card-a')
              .having((entry) => entry.categoryId, 'categoryId', 'cat-tires'),
        ),
      );
    },
  );

  test('baixa de orçamento da agenda cria despesa realizada', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final settlementDate = '$month-15';

    await repository.upsertAccount(
      id: 'acc-main',
      name: 'Conta principal',
      type: 'checking',
      initialBalance: 1000,
    );
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-home',
            name: 'Moradia',
            type: 'expense',
          ),
        );
    await db
        .into(db.localSubcategories)
        .insert(
          LocalSubcategoriesCompanion.insert(
            id: 'sub-water',
            categoryId: 'cat-home',
            name: 'Agua',
          ),
        );
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: 'budget-current',
            referenceMonth: '$month-01',
          ),
        );
    await db
        .into(db.localBudgetItems)
        .insert(
          LocalBudgetItemsCompanion.insert(
            id: 'budget-water',
            budgetId: 'budget-current',
            categoryId: 'cat-home',
            subcategoryId: const Value('sub-water'),
            plannedAmount: const Value(120),
            dueDay: const Value(1),
            accountId: const Value('acc-main'),
          ),
        );

    final before = await repository.dashboardSummary(forMonth: now);
    final agendaEntry = before.financialAgendaEntries.singleWhere(
      (entry) => entry.isBudget && entry.categoryId == 'cat-home',
    );
    expect(agendaEntry.subcategoryId, 'sub-water');
    expect(before.monthPlannedExpense, 120);

    await repository.launchBudgetAgendaExpense(
      agendaEntry,
      paymentDate: settlementDate,
    );

    final txs = await db.select(db.localTransactions).get();
    final tx = txs.singleWhere((transaction) => transaction.type == 'expense');
    expect(tx.status, 'paid');
    expect(tx.amount, 120);
    expect(tx.amountPlanned, 120);
    expect(tx.accountId, 'acc-main');
    expect(tx.categoryId, 'cat-home');
    expect(tx.subcategoryId, 'sub-water');
    expect(tx.competenceDate, settlementDate);
    expect(tx.paymentDate, settlementDate);

    final after = await repository.dashboardSummary(forMonth: now);
    expect(
      after.financialAgendaEntries.any(
        (entry) => entry.isBudget && entry.categoryId == 'cat-home',
      ),
      isFalse,
    );
    expect(after.monthExpense, 120);
    expect(after.monthPlannedExpense, 0);
  });

  test('baixa parcial de orçamento mantém saldo na agenda', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final settlementDate = '$month-16';

    await repository.upsertAccount(
      id: 'acc-main',
      name: 'Conta principal',
      type: 'checking',
      initialBalance: 1000,
    );
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-home',
            name: 'Moradia',
            type: 'expense',
          ),
        );
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: 'budget-current',
            referenceMonth: '$month-01',
          ),
        );
    await db
        .into(db.localBudgetItems)
        .insert(
          LocalBudgetItemsCompanion.insert(
            id: 'budget-home',
            budgetId: 'budget-current',
            categoryId: 'cat-home',
            plannedAmount: const Value(120),
            dueDay: Value(now.day),
            accountId: const Value('acc-main'),
          ),
        );

    final before = await repository.dashboardSummary(forMonth: now);
    final agendaEntry = before.financialAgendaEntries.singleWhere(
      (entry) => entry.isBudget && entry.categoryId == 'cat-home',
    );

    await repository.launchBudgetAgendaExpense(
      agendaEntry,
      amount: 45,
      paymentDate: settlementDate,
    );

    final txs = await db.select(db.localTransactions).get();
    expect(txs.single.status, 'paid');
    expect(txs.single.amount, 45);
    expect(txs.single.amountPlanned, 45);
    expect(txs.single.competenceDate, settlementDate);
    expect(txs.single.paymentDate, settlementDate);

    final after = await repository.dashboardSummary(forMonth: now);
    final remaining = after.financialAgendaEntries.singleWhere(
      (entry) => entry.isBudget && entry.categoryId == 'cat-home',
    );
    expect(remaining.amount, 75);
    expect(after.monthExpense, 45);
    expect(after.monthPlannedExpense, 75);
  });

  test(
    'baixa de diferença de orçamento fecha pendente sem sensibilizar conta',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final settlementDate = '$month-18';

      await repository.upsertAccount(
        id: 'acc-main',
        name: 'Conta principal',
        type: 'checking',
        initialBalance: 1000,
      );
      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-energy',
              name: 'Energia elétrica',
              type: 'expense',
            ),
          );
      await db
          .into(db.localBudgets)
          .insert(
            LocalBudgetsCompanion.insert(
              id: 'budget-current',
              referenceMonth: '$month-01',
            ),
          );
      await db
          .into(db.localBudgetItems)
          .insert(
            LocalBudgetItemsCompanion.insert(
              id: 'budget-energy',
              budgetId: 'budget-current',
              categoryId: 'cat-energy',
              plannedAmount: const Value(500),
              dueDay: const Value(10),
              accountId: const Value('acc-main'),
            ),
          );
      await repository.addTransaction(
        type: 'expense',
        description: 'Fatura energia',
        amount: 400,
        date: settlementDate,
        isPaid: true,
        accountId: 'acc-main',
        categoryId: 'cat-energy',
      );

      final before = await repository.dashboardSummary(forMonth: now);
      final gap = before.financialAgendaEntries.singleWhere(
        (entry) => entry.isBudget && entry.categoryId == 'cat-energy',
      );
      expect(gap.amount, 100);

      await repository.settleBudgetAgendaDifference(
        gap,
        paymentDate: settlementDate,
      );

      final after = await repository.dashboardSummary(forMonth: now);
      expect(after.monthExpense, 400);
      expect(after.spentByCategory['cat-energy'], 400);
      expect(
        after.expenseTransactions.map((transaction) => transaction.description),
        contains('Fatura energia'),
      );
      expect(after.monthPlannedExpense, 0);
      expect(
        after.financialAgendaEntries.any(
          (entry) => entry.isBudget && entry.categoryId == 'cat-energy',
        ),
        isFalse,
      );

      final account = await (db.select(
        db.localAccounts,
      )..where((account) => account.id.equals('acc-main'))).getSingle();
      expect(await repository.accountBalance(account), 600);

      final transactions = await db.select(db.localTransactions).get();
      expect(transactions, hasLength(2));
      final adjustment = transactions.singleWhere(
        (tx) => tx.description.startsWith('Baixa diferença'),
      );
      expect(adjustment.amount == null, true);
      expect(adjustment.amountPlanned, 100);
      expect(adjustment.accountId == null, true);
      expect(adjustment.cardId == null, true);

      final planned = await repository.plannedEntriesForMonth(month);
      final budgetLine = planned.singleWhere(
        (entry) => entry.isBudget && entry.categoryId == 'cat-energy',
      );
      expect(budgetLine.realized, 400);
      expect(budgetLine.saldo, 0);
    },
  );

  test(
    'lançamento estornado de orçamento pode ser fechado como diferença',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final paymentDate = '$month-18';

      await repository.upsertAccount(
        id: 'acc-main',
        name: 'Conta principal',
        type: 'checking',
        initialBalance: 1000,
      );
      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-energy',
              name: 'Energia elétrica',
              type: 'expense',
            ),
          );
      await db
          .into(db.localBudgets)
          .insert(
            LocalBudgetsCompanion.insert(
              id: 'budget-current',
              referenceMonth: '$month-01',
            ),
          );
      await db
          .into(db.localBudgetItems)
          .insert(
            LocalBudgetItemsCompanion.insert(
              id: 'budget-energy',
              budgetId: 'budget-current',
              categoryId: 'cat-energy',
              plannedAmount: const Value(500),
              dueDay: const Value(10),
              accountId: const Value('acc-main'),
            ),
          );
      await repository.addTransaction(
        type: 'expense',
        description: 'Fatura energia',
        amount: 400,
        date: paymentDate,
        isPaid: true,
        accountId: 'acc-main',
        categoryId: 'cat-energy',
      );

      final gap = (await repository.dashboardSummary(forMonth: now))
          .financialAgendaEntries
          .singleWhere(
            (entry) => entry.isBudget && entry.categoryId == 'cat-energy',
          );
      expect(gap.amount, 100);

      await repository.launchBudgetAgendaExpense(gap, paymentDate: paymentDate);

      var wrongPayment =
          await (db.select(db.localTransactions)..where(
                (tx) =>
                    tx.description.equals('Energia elétrica') &
                    tx.amount.equals(100),
              ))
              .getSingle();
      expect(wrongPayment.status, 'paid');

      await repository.markPlanned(wrongPayment);
      wrongPayment = await (db.select(
        db.localTransactions,
      )..where((tx) => tx.id.equals(wrongPayment.id))).getSingle();
      expect(wrongPayment.status, 'planned');

      final estornoSummary = await repository.dashboardSummary(forMonth: now);
      final estornada = estornoSummary.financialAgendaEntries.singleWhere(
        (entry) => entry.transaction?.id == wrongPayment.id,
      );
      expect(estornada.isBudget, isFalse);
      expect(estornada.amount, 100);

      await repository.settleAgendaTransactionDifference(
        wrongPayment,
        amount: 100,
        paymentDate: paymentDate,
      );

      final after = await repository.dashboardSummary(forMonth: now);
      expect(after.monthExpense, 400);
      expect(after.spentByCategory['cat-energy'], 400);
      expect(after.monthPlannedExpense, 0);
      expect(
        after.financialAgendaEntries.any(
          (entry) => entry.categoryId == 'cat-energy',
        ),
        isFalse,
      );

      final account = await (db.select(
        db.localAccounts,
      )..where((account) => account.id.equals('acc-main'))).getSingle();
      expect(await repository.accountBalance(account), 600);

      final originalAfter = await (db.select(
        db.localTransactions,
      )..where((tx) => tx.id.equals(wrongPayment.id))).getSingle();
      expect(originalAfter.deletedAt != null, true);
      final adjustment = (await db.select(db.localTransactions).get())
          .singleWhere((tx) => tx.description.startsWith('Baixa diferença'));
      expect(adjustment.amount == null, true);
      expect(adjustment.amountPlanned, 100);
      expect(adjustment.accountId == null, true);
      expect(adjustment.cardId == null, true);
    },
  );

  test(
    'baixa parcial de lançamento previsto cria pagamento e preserva saldo',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final dueDate = _isoDate(now);
      final settlementDate = '$month-20';

      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-bills',
              name: 'Contas',
              type: 'expense',
            ),
          );
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: 'tx-energy',
              type: 'expense',
              description: 'Energia',
              amountPlanned: const Value(300),
              competenceDate: '$month-01',
              dueDate: Value(dueDate),
              status: const Value('planned'),
              categoryId: const Value('cat-bills'),
            ),
          );

      final before = await repository.dashboardSummary(forMonth: now);
      final agendaEntry = before.financialAgendaEntries.singleWhere(
        (entry) => entry.transaction?.id == 'tx-energy',
      );

      await repository.settleAgendaTransaction(
        agendaEntry.transaction!,
        amount: 125,
        paymentDate: settlementDate,
      );

      final transactions = await db.select(db.localTransactions).get();
      final original = transactions.singleWhere((tx) => tx.id == 'tx-energy');
      final payment = transactions.singleWhere((tx) => tx.id != 'tx-energy');
      expect(original.status, 'planned');
      expect(original.amount == null, true);
      expect(original.amountPlanned, 175);
      expect(payment.status, 'paid');
      expect(payment.amount, 125);
      expect(payment.amountPlanned, 125);
      expect(payment.competenceDate, settlementDate);
      expect(payment.paymentDate, settlementDate);
      expect(payment.categoryId, 'cat-bills');

      final after = await repository.dashboardSummary(forMonth: now);
      final remaining = after.financialAgendaEntries.singleWhere(
        (entry) => entry.transaction?.id == 'tx-energy',
      );
      expect(remaining.amount, 175);
      expect(after.monthExpense, 125);
      expect(after.monthPlannedExpense, 175);
    },
  );

  test('baixa de orçamento aceita valor maior que o previsto', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final settlementDate = '$month-16';

    await repository.upsertAccount(
      id: 'acc-main',
      name: 'Conta principal',
      type: 'checking',
      initialBalance: 1000,
    );
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-home',
            name: 'Moradia',
            type: 'expense',
          ),
        );
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: 'budget-current',
            referenceMonth: '$month-01',
          ),
        );
    await db
        .into(db.localBudgetItems)
        .insert(
          LocalBudgetItemsCompanion.insert(
            id: 'budget-home',
            budgetId: 'budget-current',
            categoryId: 'cat-home',
            plannedAmount: const Value(120),
            dueDay: Value(now.day),
            accountId: const Value('acc-main'),
          ),
        );

    final before = await repository.dashboardSummary(forMonth: now);
    final agendaEntry = before.financialAgendaEntries.singleWhere(
      (entry) => entry.isBudget && entry.categoryId == 'cat-home',
    );

    await repository.launchBudgetAgendaExpense(
      agendaEntry,
      amount: 150,
      paymentDate: settlementDate,
    );

    final txs = await db.select(db.localTransactions).get();
    expect(txs.single.status, 'paid');
    expect(txs.single.amount, 150);

    final after = await repository.dashboardSummary(forMonth: now);
    expect(
      after.financialAgendaEntries.any(
        (entry) => entry.isBudget && entry.categoryId == 'cat-home',
      ),
      isFalse,
    );
    expect(after.monthExpense, 150);
    expect(after.monthPlannedExpense, 0);
  });

  test('baixa de lançamento previsto com valor maior paga com o valor real '
      'e preserva o previsto', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final dueDate = _isoDate(now);
    final settlementDate = '$month-20';

    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-bills',
            name: 'Contas',
            type: 'expense',
          ),
        );
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: 'tx-energy',
            type: 'expense',
            description: 'Energia',
            amountPlanned: const Value(300),
            competenceDate: '$month-01',
            dueDate: Value(dueDate),
            status: const Value('planned'),
            categoryId: const Value('cat-bills'),
          ),
        );

    final before = await repository.dashboardSummary(forMonth: now);
    final agendaEntry = before.financialAgendaEntries.singleWhere(
      (entry) => entry.transaction?.id == 'tx-energy',
    );

    await repository.settleAgendaTransaction(
      agendaEntry.transaction!,
      amount: 350,
      paymentDate: settlementDate,
    );

    final tx = await (db.select(
      db.localTransactions,
    )..where((t) => t.id.equals('tx-energy'))).getSingle();
    expect(tx.status, 'paid');
    expect(tx.amount, 350);
    expect(tx.amountPlanned, 300);
    expect(tx.paymentDate, settlementDate);

    final after = await repository.dashboardSummary(forMonth: now);
    expect(
      after.financialAgendaEntries.any(
        (entry) => entry.transaction?.id == 'tx-energy',
      ),
      isFalse,
    );
    expect(after.monthExpense, 350);
  });

  test('movimentações de meta criam lançamentos e ajustam acumulado', () async {
    final now = DateTime.now();
    final date = _isoDate(now);

    await repository.upsertAccount(
      id: 'acc-goal',
      name: 'Conta meta',
      type: 'checking',
      initialBalance: 1000,
    );
    await repository.upsertGoal(
      id: 'goal-reserve',
      name: 'Reserva',
      targetAmount: 1000,
      accumulatedAmount: 100,
    );

    var goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-reserve'))).getSingle();

    await repository.upsertGoalMovement(
      goal: goal,
      movementType: 'contribution',
      amount: 200,
      date: date,
      accountId: 'acc-goal',
    );

    goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-reserve'))).getSingle();
    expect(goal.accumulatedAmount, 300);

    var transactions = await db.select(db.localTransactions).get();
    var contribution = transactions.single;
    expect(contribution.type, 'expense');
    expect(contribution.status, 'paid');
    expect(contribution.accountId, 'acc-goal');
    expect(contribution.amount, 200);
    expect(
      FinanceRepository.goalMovementLink(contribution)?.movementType,
      'contribution',
    );

    await repository.upsertGoalMovement(
      goal: goal,
      transaction: contribution,
      movementType: 'contribution',
      amount: 250,
      date: date,
      accountId: 'acc-goal',
    );

    goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-reserve'))).getSingle();
    expect(goal.accumulatedAmount, 350);
    transactions = await db.select(db.localTransactions).get();
    contribution = transactions.single;
    expect(contribution.amount, 250);

    await repository.upsertGoalMovement(
      goal: goal,
      movementType: 'withdrawal',
      amount: 50,
      date: date,
      accountId: 'acc-goal',
    );

    goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-reserve'))).getSingle();
    expect(goal.accumulatedAmount, 300);
    transactions = await db.select(db.localTransactions).get();
    final withdrawal = transactions.singleWhere((tx) => tx.type == 'income');
    expect(withdrawal.amount, 50);
    expect(
      FinanceRepository.goalMovementLink(withdrawal)?.movementType,
      'withdrawal',
    );

    await repository.deleteGoalMovement(contribution);
    goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-reserve'))).getSingle();
    expect(goal.accumulatedAmount, 50);

    await repository.deleteTransaction(withdrawal);
    goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-reserve'))).getSingle();
    expect(goal.accumulatedAmount, 100);
  });

  test('aporte de meta em cartão vira lançamento previsto no cartão', () async {
    final now = DateTime.now();
    final date = _isoDate(now);

    await db
        .into(db.localCreditCards)
        .insert(
          LocalCreditCardsCompanion.insert(
            id: 'card-goal',
            name: 'Cartão meta',
            closingDay: const Value(10),
            dueDay: const Value(20),
          ),
        );
    await repository.upsertGoal(
      id: 'goal-trip',
      name: 'Viagem',
      targetAmount: 2000,
    );

    final goal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-trip'))).getSingle();
    final card = await (db.select(
      db.localCreditCards,
    )..where((c) => c.id.equals('card-goal'))).getSingle();

    await repository.upsertGoalMovement(
      goal: goal,
      movementType: 'contribution',
      amount: 80,
      date: date,
      card: card,
    );

    final updatedGoal = await (db.select(
      db.localGoals,
    )..where((g) => g.id.equals('goal-trip'))).getSingle();
    expect(updatedGoal.accumulatedAmount, 80);

    final transaction = await (db.select(db.localTransactions)).getSingle();
    expect(transaction.type, 'expense');
    expect(transaction.status, 'planned');
    expect(transaction.cardId, 'card-goal');
    expect(transaction.amount == null, true);
    expect(transaction.amountPlanned, 80);
  });

  test('agenda do cartão não duplica orçamento coberto por compra da fatura '
      'seguinte', () async {
    final selected = DateTime.now();
    final month =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}';
    final invoiceDue = _isoDate(DateTime(selected.year, selected.month + 1, 1));

    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-subscriptions',
            name: 'Assinaturas',
            type: 'expense',
          ),
        );
    await db
        .into(db.localSubcategories)
        .insert(
          LocalSubcategoriesCompanion.insert(
            id: 'sub-claude',
            categoryId: 'cat-subscriptions',
            name: 'Claude Anthropic',
          ),
        );
    await db
        .into(db.localCreditCards)
        .insert(
          LocalCreditCardsCompanion.insert(
            id: 'card-claude',
            name: 'Cartão Claude',
            closingDay: const Value(25),
            dueDay: const Value(1),
            limitAmount: const Value(1000),
          ),
        );
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: 'budget-current',
            referenceMonth: '$month-01',
          ),
        );
    await db
        .into(db.localBudgetItems)
        .insert(
          LocalBudgetItemsCompanion.insert(
            id: 'budget-claude',
            budgetId: 'budget-current',
            categoryId: 'cat-subscriptions',
            plannedAmount: const Value(115.45),
            isFixed: const Value(true),
            dueDay: const Value(8),
            subcategoryId: const Value('sub-claude'),
            cardId: const Value('card-claude'),
          ),
        );
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: 'tx-claude',
            type: 'expense',
            description: 'Claude Anthropic',
            amountPlanned: const Value(115.45),
            competenceDate: '$month-08',
            dueDate: Value(invoiceDue),
            status: const Value('planned'),
            categoryId: const Value('cat-subscriptions'),
            subcategoryId: const Value('sub-claude'),
            cardId: const Value('card-claude'),
          ),
        );

    final summary = await repository.dashboardSummary(forMonth: selected);
    final cardEntries = summary.financialAgendaEntries
        .where((entry) => entry.cardId == 'card-claude')
        .toList();

    expect(cardEntries, hasLength(1));
    expect(cardEntries.single.transaction?.id, 'tx-claude');
    expect(cardEntries.single.isBudget, isFalse);
    expect(summary.cardOpenByCard['card-claude'], 115.45);
  });

  test(
    'pagamento de parcela de dívida cria despesa realizada e amortiza previsão',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final dueDate = '$month-05';
      final paymentDate = _isoDate(now);

      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-financing',
              name: 'Financiamentos',
              type: 'expense',
            ),
          );
      await db
          .into(db.localDebts)
          .insert(
            LocalDebtsCompanion.insert(
              id: 'debt-car',
              name: 'Financiamento carro',
              type: const Value('financing'),
              originalAmount: 2000,
              outstandingBalance: 2000,
              totalInstallments: const Value(4),
              paidInstallments: const Value(0),
              installmentAmount: const Value(500),
              firstDueDate: Value(dueDate),
            ),
          );

      final before = await repository.plannedEntriesForMonth(month);
      final debtEntry = before.singleWhere((entry) => entry.isDebt);
      expect(debtEntry.description, 'Financiamento carro · parcela 1/4');
      expect(debtEntry.planned, 500);
      expect(debtEntry.realized, 0);

      final beforeSummary = await repository.dashboardSummary(forMonth: now);
      expect(beforeSummary.monthExpense, 0);
      expect(beforeSummary.monthPlannedExpense, 500);

      await repository.payDebtInstallment(
        debt: debtEntry.debt!,
        plannedAmount: debtEntry.planned,
        amount: 500,
        dueDate: debtEntry.dueDate!,
        paymentDate: paymentDate,
        installmentNumber: debtEntry.debtInstallmentNumber!,
        categoryId: 'cat-financing',
      );

      final debt = await (db.select(
        db.localDebts,
      )..where((d) => d.id.equals('debt-car'))).getSingle();
      expect(debt.outstandingBalance, 1500);
      expect(debt.paidInstallments, 1);
      expect(debt.status, 'active');

      final transactions = await db.select(db.localTransactions).get();
      expect(transactions, hasLength(1));
      expect(transactions.single.status, 'paid');
      expect(transactions.single.amount, 500);
      expect(transactions.single.amountPlanned, 500);
      expect(transactions.single.categoryId, 'cat-financing');
      expect(FinanceRepository.isDebtPayment(transactions.single), isTrue);

      final after = await repository.plannedEntriesForMonth(month);
      expect(after.where((entry) => entry.isDebt), isEmpty);
      expect(
        after,
        contains(
          isA<PlannedEntry>()
              .having(
                (entry) => entry.transaction?.id,
                'transaction id',
                transactions.single.id,
              )
              .having((entry) => entry.realized, 'realized', 500)
              .having((entry) => entry.saldo, 'saldo', 0),
        ),
      );

      final afterSummary = await repository.dashboardSummary(forMonth: now);
      expect(afterSummary.monthExpense, 500);
      expect(afterSummary.monthPlannedExpense, 0);
      expect(afterSummary.spentByCategory['cat-financing'], 500);

      await repository.deleteTransaction(transactions.single);

      final restoredDebt = await (db.select(
        db.localDebts,
      )..where((d) => d.id.equals('debt-car'))).getSingle();
      expect(restoredDebt.outstandingBalance, 2000);
      expect(restoredDebt.paidInstallments, 0);

      final restoredPlanned = await repository.plannedEntriesForMonth(month);
      expect(restoredPlanned.where((entry) => entry.isDebt), hasLength(1));
    },
  );

  test(
    'parcela em atraso paga com juros separa o acréscimo em Juros e Multas',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final dueDate = '$month-05';
      final paymentDate = _isoDate(now);

      await repository.upsertAccount(
        id: 'acc-debt',
        name: 'Conta dívida',
        type: 'checking',
        initialBalance: 2000,
      );
      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-financing',
              name: 'Financiamentos',
              type: 'expense',
            ),
          );
      await db
          .into(db.localDebts)
          .insert(
            LocalDebtsCompanion.insert(
              id: 'debt-loan',
              name: 'Empréstimo',
              type: const Value('loan'),
              originalAmount: 1000,
              outstandingBalance: 1000,
              totalInstallments: const Value(2),
              paidInstallments: const Value(0),
              installmentAmount: const Value(500),
              firstDueDate: Value(dueDate),
              accountId: const Value('acc-debt'),
            ),
          );
      final debt = await (db.select(
        db.localDebts,
      )..where((d) => d.id.equals('debt-loan'))).getSingle();

      await repository.payDebtInstallment(
        debt: debt,
        plannedAmount: 500,
        amount: 550,
        dueDate: dueDate,
        paymentDate: paymentDate,
        installmentNumber: 1,
        interestAmount: 50,
        categoryId: 'cat-financing',
      );

      final updatedDebt = await (db.select(
        db.localDebts,
      )..where((d) => d.id.equals('debt-loan'))).getSingle();
      expect(updatedDebt.outstandingBalance, 500);
      expect(updatedDebt.paidInstallments, 1);

      final transactions = await db.select(db.localTransactions).get();
      expect(transactions, hasLength(2));
      final payment = transactions.singleWhere(
        (tx) => FinanceRepository.isDebtPayment(tx),
      );
      expect(payment.amount, 500);
      expect(payment.amountPlanned, 500);
      expect(payment.categoryId, 'cat-financing');
      final interest = transactions.singleWhere(
        (tx) => !FinanceRepository.isDebtPayment(tx),
      );
      expect(interest.status, 'paid');
      expect(interest.amount, 50);
      expect(interest.accountId, 'acc-debt');
      expect(interest.description, 'Juros/multa Empréstimo (1/2)');

      final interestCategory = (await db.select(db.localCategories).get())
          .singleWhere((c) => c.name == FinanceRepository.interestCategoryName);
      expect(interestCategory.type, 'expense');
      expect(interest.categoryId, interestCategory.id);

      final account = await (db.select(
        db.localAccounts,
      )..where((a) => a.id.equals('acc-debt'))).getSingle();
      expect(await repository.accountBalance(account), 1450);

      // Segunda parcela com juros reutiliza a categoria já criada.
      await repository.payDebtInstallment(
        debt: updatedDebt,
        plannedAmount: 500,
        amount: 520,
        dueDate: dueDate,
        paymentDate: paymentDate,
        installmentNumber: 2,
        interestAmount: 20,
        categoryId: 'cat-financing',
      );
      final interestCategories = (await db.select(db.localCategories).get())
          .where((c) => c.name == FinanceRepository.interestCategoryName);
      expect(interestCategories, hasLength(1));
      final paidOffDebt = await (db.select(
        db.localDebts,
      )..where((d) => d.id.equals('debt-loan'))).getSingle();
      expect(paidOffDebt.outstandingBalance, 0);
      expect(paidOffDebt.status, 'paid_off');
    },
  );

  test('dívida vinculada cria orçamento e baixa herda vínculos', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final dueDate = _isoDate(now);

    await repository.upsertAccount(
      id: 'acc-debt',
      name: 'Conta dívida',
      type: 'checking',
      initialBalance: 2000,
    );
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-debt-linked',
            name: 'Financiamentos',
            type: 'expense',
          ),
        );
    await db
        .into(db.localSubcategories)
        .insert(
          LocalSubcategoriesCompanion.insert(
            id: 'sub-debt-linked',
            categoryId: 'cat-debt-linked',
            name: 'Carro',
          ),
        );

    await repository.upsertDebt(
      id: 'debt-linked',
      name: 'Financiamento vinculado',
      type: 'financing',
      originalAmount: 3000,
      outstandingBalance: 3000,
      totalInstallments: 6,
      installmentAmount: 500,
      firstDueDate: dueDate,
      accountId: 'acc-debt',
      categoryId: 'cat-debt-linked',
      subcategoryId: 'sub-debt-linked',
      budgetReferenceMonth: '$month-01',
    );

    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-linked'))).getSingle();
    expect(debt.budgetItemId != null, true);
    final budgetItem = await (db.select(
      db.localBudgetItems,
    )..where((item) => item.id.equals(debt.budgetItemId!))).getSingle();
    expect(budgetItem.categoryId, 'cat-debt-linked');
    expect(budgetItem.subcategoryId, 'sub-debt-linked');
    expect(budgetItem.accountId, 'acc-debt');
    expect(budgetItem.plannedAmount, 500);

    final planned = await repository.plannedEntriesForMonth(month);
    expect(planned.where((entry) => entry.isBudget), isEmpty);
    final debtEntry = planned.singleWhere((entry) => entry.isDebt);
    expect(debtEntry.categoryId, 'cat-debt-linked');
    expect(debtEntry.subcategoryId, 'sub-debt-linked');

    await repository.payDebtInstallment(
      debt: debt,
      plannedAmount: 500,
      amount: 500,
      dueDate: dueDate,
      paymentDate: dueDate,
      installmentNumber: 1,
    );

    final tx = await (db.select(db.localTransactions)..limit(1)).getSingle();
    expect(tx.categoryId, 'cat-debt-linked');
    expect(tx.subcategoryId, 'sub-debt-linked');
    expect(tx.accountId, 'acc-debt');
    expect(FinanceRepository.isDebtPayment(tx), isTrue);
  });

  test('baixa com desconto de antecipação amortiza mais que o valor pago', () async {
    final now = DateTime.now();
    final dueDate = _isoDate(now);
    await repository.upsertAccount(
      id: 'acc-disc',
      name: 'Conta',
      type: 'checking',
      initialBalance: 2000,
    );
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-disc',
            name: 'Financiamentos',
            type: 'expense',
          ),
        );
    await db
        .into(db.localDebts)
        .insert(
          LocalDebtsCompanion.insert(
            id: 'debt-disc',
            name: 'Empréstimo',
            type: const Value('loan'),
            originalAmount: 1000,
            outstandingBalance: 1000,
            totalInstallments: const Value(2),
            paidInstallments: const Value(0),
            installmentAmount: const Value(500),
            firstDueDate: Value(dueDate),
            accountId: const Value('acc-disc'),
          ),
        );
    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-disc'))).getSingle();

    await repository.payDebtInstallment(
      debt: debt,
      plannedAmount: 500,
      amount: 500,
      dueDate: dueDate,
      paymentDate: dueDate,
      installmentNumber: 1,
      discountAmount: 50,
      categoryId: 'cat-disc',
    );

    final afterPay = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-disc'))).getSingle();
    // A parcela de 500 foi quitada, mas só 450 saíram do caixa.
    expect(afterPay.outstandingBalance, 500);
    expect(afterPay.paidInstallments, 1);
    final tx = await (db.select(db.localTransactions)..limit(1)).getSingle();
    expect(tx.amount, 450);
    final account = await (db.select(
      db.localAccounts,
    )..where((a) => a.id.equals('acc-disc'))).getSingle();
    expect(await repository.accountBalance(account), 1550);

    // Estorno devolve o desconto junto com o valor pago.
    await repository.deleteTransaction(tx);
    final restored = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-disc'))).getSingle();
    expect(restored.outstandingBalance, 1000);
    expect(restored.paidInstallments, 0);
  });

  test('baixa antiga de dívida pode receber categoria depois', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final paymentDate = _isoDate(now);
    final dueDate = '$month-10';

    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-financing',
            name: 'Financiamentos',
            type: 'expense',
          ),
        );
    await db
        .into(db.localSubcategories)
        .insert(
          LocalSubcategoriesCompanion.insert(
            id: 'sub-car',
            categoryId: 'cat-financing',
            name: 'Carro',
          ),
        );
    await db
        .into(db.localDebts)
        .insert(
          LocalDebtsCompanion.insert(
            id: 'debt-car',
            name: 'Financiamento carro',
            type: const Value('financing'),
            originalAmount: 2000,
            outstandingBalance: 1500,
            totalInstallments: const Value(4),
            paidInstallments: const Value(1),
            installmentAmount: const Value(500),
            firstDueDate: Value(dueDate),
          ),
        );
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: 'tx-old-debt-payment',
            type: 'expense',
            description: 'Pagamento Financiamento carro (1/4)',
            amount: const Value(500),
            amountPlanned: const Value(500),
            competenceDate: paymentDate,
            dueDate: Value(dueDate),
            paymentDate: Value(paymentDate),
            status: const Value('paid'),
            notes: Value(
              'hopecash:debt_payment:${jsonEncode({'debt_id': 'debt-car', 'due_date': dueDate, 'installment_number': 1, 'installments_advanced': 1})}',
            ),
          ),
        );

    final beforeSummary = await repository.dashboardSummary(forMonth: now);
    expect(beforeSummary.monthExpense, 500);
    expect(beforeSummary.spentByCategory, isNot(contains('cat-financing')));

    final tx =
        await (db.select(db.localTransactions)..where(
              (transaction) => transaction.id.equals('tx-old-debt-payment'),
            ))
            .getSingle();
    expect(FinanceRepository.isDebtPayment(tx), isTrue);

    await repository.updateDebtPaymentCategory(
      transaction: tx,
      categoryId: 'cat-financing',
      subcategoryId: 'sub-car',
    );

    final updated =
        await (db.select(db.localTransactions)..where(
              (transaction) => transaction.id.equals('tx-old-debt-payment'),
            ))
            .getSingle();
    expect(updated.categoryId, 'cat-financing');
    expect(updated.subcategoryId, 'sub-car');
    expect(updated.amount, 500);
    expect(updated.status, 'paid');
    expect(FinanceRepository.isDebtPayment(updated), isTrue);

    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-car'))).getSingle();
    expect(debt.outstandingBalance, 1500);
    expect(debt.paidInstallments, 1);

    final afterSummary = await repository.dashboardSummary(forMonth: now);
    expect(afterSummary.spentByCategory['cat-financing'], 500);
    expect(afterSummary.spentBySubcategory['cat-financing|sub-car'], 500);

    final operation = await db.select(db.pendingOperations).getSingle();
    expect(operation.entity, 'transactions');
    expect(operation.op, 'update');
    final payload = jsonDecode(operation.payload!) as Map<String, dynamic>;
    expect(payload['category_id'], 'cat-financing');
    expect(payload['subcategory_id'], 'sub-car');
    expect(payload['notes'], updated.notes);
  });

  test('parcela de dívida baixada sai da agenda financeira do mês', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';

    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-debts',
            name: 'Dívidas',
            type: 'expense',
          ),
        );
    // Dívida ancorada apenas no dia de vencimento (sem firstDueDate): a
    // projeção da agenda parte sempre do mês corrente.
    await repository.upsertDebt(
      id: 'debt-loan',
      name: 'Empréstimo pessoal',
      type: 'loan',
      originalAmount: 6000,
      outstandingBalance: 6000,
      totalInstallments: 12,
      installmentAmount: 500,
      dueDay: now.day,
    );

    bool hasDebtEntryThisMonth(DashboardSummary summary) =>
        summary.financialAgendaEntries.any(
          (entry) => entry.isDebt && (entry.dueDate ?? '').startsWith(month),
        );

    final before = await repository.dashboardSummary();
    expect(
      hasDebtEntryThisMonth(before),
      isTrue,
      reason: 'antes da baixa, a parcela do mês deve estar na agenda',
    );

    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-loan'))).getSingle();
    await repository.payDebtInstallment(
      debt: debt,
      plannedAmount: 500,
      amount: 500,
      dueDate: _isoDate(now),
      paymentDate: _isoDate(now),
      installmentNumber: 1,
      categoryId: 'cat-debts',
    );

    final after = await repository.dashboardSummary();
    expect(
      hasDebtEntryThisMonth(after),
      isFalse,
      reason: 'parcela baixada não deve continuar na agenda do mês',
    );
  });

  test('próximo pagamento avança para o mês seguinte após a baixa mesmo sem '
      'firstDueDate', () async {
    // Regressão: dívidas ancoradas só em dueDay (sem firstDueDate) sempre
    // mostravam "próximo pagamento" no dia de vencimento do mês corrente,
    // mesmo já pagas, porque a tela não considerava os meses já baixados.
    final now = DateTime.now();

    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-financiamento',
            name: 'Financiamento',
            type: 'expense',
          ),
        );
    await repository.upsertDebt(
      id: 'debt-financiamento-carro',
      name: 'Financiamento do carro',
      type: 'financing',
      originalAmount: 6000,
      outstandingBalance: 6000,
      totalInstallments: 12,
      installmentAmount: 500,
      dueDay: now.day,
    );

    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-financiamento-carro'))).getSingle();

    final beforePayment = repository.nextOpenDebtInstallment(debt, const []);
    expect(beforePayment != null, true);
    expect(
      beforePayment!.dueDate.startsWith(_isoDate(now).substring(0, 7)),
      isTrue,
    );

    await repository.payDebtInstallment(
      debt: debt,
      plannedAmount: 500,
      amount: 500,
      dueDate: _isoDate(now),
      paymentDate: _isoDate(now),
      installmentNumber: 1,
      categoryId: 'cat-financiamento',
    );

    final updatedDebt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-financiamento-carro'))).getSingle();
    final allTxs = await db.select(db.localTransactions).get();

    final nextInstallment = repository.nextOpenDebtInstallment(
      updatedDebt,
      allTxs,
    );
    expect(nextInstallment != null, true);
    expect(
      nextInstallment!.dueDate.startsWith(_isoDate(now).substring(0, 7)),
      isFalse,
      reason:
          'após a baixa, o próximo pagamento não pode continuar no mesmo '
          'mês já pago',
    );
  });

  test('agenda financeira mostra atrasados e o mês selecionado, '
      'sem o mês seguinte', () async {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final nextMonth = DateTime(now.year, now.month + 1, 15);
    final thisMonthDue = DateTime(now.year, now.month, 28);

    Future<void> addPlanned(String id, DateTime due, {String? cardId}) => db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: id,
            type: 'expense',
            description: 'Compromisso $id',
            amountPlanned: const Value(100),
            competenceDate: _isoDate(due),
            dueDate: Value(_isoDate(due)),
            status: const Value('planned'),
            cardId: Value(cardId),
          ),
        );

    await db
        .into(db.localCreditCards)
        .insert(
          LocalCreditCardsCompanion.insert(
            id: 'card-agenda',
            name: 'Cartão Agenda',
            closingDay: const Value(1),
            dueDay: const Value(15),
          ),
        );

    await addPlanned('tx-atrasado', lastMonth);
    await addPlanned('tx-mes-atual', thisMonthDue);
    await addPlanned('tx-mes-seguinte', nextMonth);
    // Compra de cartão com fatura vencendo no mês seguinte: deve continuar
    // visível na agenda mesmo com o filtro no mês corrente.
    await addPlanned('tx-cartao-fatura', nextMonth, cardId: 'card-agenda');

    Set<String> agendaIds(DashboardSummary summary) => {
      for (final entry in summary.financialAgendaEntries)
        if (entry.transaction != null) entry.transaction!.id,
    };

    // Mês corrente (padrão): atrasado + mês atual + cartão do mês seguinte;
    // compromisso comum do mês seguinte fora.
    final current = await repository.dashboardSummary();
    expect(agendaIds(current), {
      'tx-atrasado',
      'tx-mes-atual',
      'tx-cartao-fatura',
    });

    // Filtro no mês seguinte: o compromisso dele passa a aparecer.
    final next = await repository.dashboardSummary(forMonth: nextMonth);
    expect(agendaIds(next), contains('tx-mes-seguinte'));
  });

  test('lançamento casado com orçamento fica acessível pela linha '
      'do orçamento', () async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';

    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-internet',
            name: 'Internet',
            type: 'expense',
          ),
        );
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: 'budget-m',
            referenceMonth: '$month-01',
          ),
        );
    await db
        .into(db.localBudgetItems)
        .insert(
          LocalBudgetItemsCompanion.insert(
            id: 'item-internet',
            budgetId: 'budget-m',
            categoryId: 'cat-internet',
            plannedAmount: const Value(115.45),
          ),
        );
    // Lançamento pago com o valor errado (115,15 em vez de 115,45): é
    // absorvido pela linha do orçamento e precisa continuar acessível por ela.
    await db
        .into(db.localTransactions)
        .insert(
          LocalTransactionsCompanion.insert(
            id: 'tx-internet',
            type: 'expense',
            description: 'Internet fibra',
            amount: const Value(115.15),
            amountPlanned: const Value(115.15),
            competenceDate: _isoDate(now),
            paymentDate: Value(_isoDate(now)),
            status: const Value('paid'),
            categoryId: const Value('cat-internet'),
          ),
        );

    final planned = await repository.plannedEntriesForMonth(month);
    final budgetLine = planned.firstWhere(
      (entry) => entry.isBudget && entry.categoryId == 'cat-internet',
    );
    expect(budgetLine.realized, 115.15);
    expect(
      budgetLine.matchedTransactions.map((tx) => tx.id),
      contains('tx-internet'),
      reason: 'a linha do orçamento deve expor o lançamento absorvido',
    );
    // E o lançamento não aparece duplicado como linha avulsa.
    expect(
      planned.any((entry) => entry.transaction?.id == 'tx-internet'),
      isFalse,
    );
  });

  test('realizado da mesma categoria é separado por conta e cartão', () async {
    const month = '2026-07';
    await db
        .into(db.localBudgets)
        .insert(
          LocalBudgetsCompanion.insert(
            id: 'budget-split',
            referenceMonth: '$month-01',
          ),
        );
    await db.batch((batch) {
      batch.insertAll(db.localBudgetItems, [
        LocalBudgetItemsCompanion.insert(
          id: 'item-debit',
          budgetId: 'budget-split',
          categoryId: 'cat-market',
          plannedAmount: const Value(1000),
          accountId: const Value('account-debit'),
        ),
        LocalBudgetItemsCompanion.insert(
          id: 'item-credit',
          budgetId: 'budget-split',
          categoryId: 'cat-market',
          plannedAmount: const Value(500),
          cardId: const Value('card-credit'),
        ),
      ]);
      batch.insertAll(db.localTransactions, [
        LocalTransactionsCompanion.insert(
          id: 'tx-debit',
          type: 'expense',
          description: 'Mercado no débito',
          amount: const Value(320),
          competenceDate: '$month-10',
          status: const Value('paid'),
          accountId: const Value('account-debit'),
          categoryId: const Value('cat-market'),
        ),
        LocalTransactionsCompanion.insert(
          id: 'tx-credit',
          type: 'expense',
          description: 'Mercado no crédito',
          amountPlanned: const Value(180),
          competenceDate: '$month-12',
          status: const Value('planned'),
          cardId: const Value('card-credit'),
          categoryId: const Value('cat-market'),
        ),
        LocalTransactionsCompanion.insert(
          id: 'tx-other-account',
          type: 'expense',
          description: 'Mercado em outra conta',
          amount: const Value(90),
          competenceDate: '$month-15',
          status: const Value('paid'),
          accountId: const Value('account-other'),
          categoryId: const Value('cat-market'),
        ),
      ]);
    });

    final realized = await repository.realizedByBudgetItemForMonth(
      month,
      'budget-split',
    );

    expect(realized['item-debit'], 320);
    expect(realized['item-credit'], 180);
    expect(realized.values.reduce((a, b) => a + b), 500);
  });

  test('fila offline consolida edições repetidas no mesmo registro', () async {
    await repository.upsertCategory(
      id: 'cat-offline',
      name: 'Mercado',
      type: 'expense',
      color: '#111111',
    );
    await repository.upsertCategory(
      id: 'cat-offline',
      name: 'Supermercado',
      type: 'expense',
      color: '#222222',
      currentVersion: 1,
    );

    final ops = await db.select(db.pendingOperations).get();
    expect(ops, hasLength(1));
    expect(ops.single.op, 'update');
    final payload = jsonDecode(ops.single.payload!) as Map<String, dynamic>;
    expect(payload['name'], 'Supermercado');
    expect(payload['color'], '#222222');
  });

  test(
    'categoria com lançamentos ou orçamentos não pode ser excluída',
    () async {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final date = _isoDate(now);

      await repository.upsertAccount(
        id: 'acc-main',
        name: 'Conta',
        type: 'checking',
        initialBalance: 1000,
      );
      await db
          .into(db.localCategories)
          .insert(
            LocalCategoriesCompanion.insert(
              id: 'cat-delete',
              name: 'Categoria removida',
              type: 'expense',
              syncStatus: const Value('synced'),
            ),
          );
      await db
          .into(db.localSubcategories)
          .insert(
            LocalSubcategoriesCompanion.insert(
              id: 'sub-delete',
              categoryId: 'cat-delete',
              name: 'Sub removida',
              syncStatus: const Value('synced'),
            ),
          );
      await db
          .into(db.localBudgets)
          .insert(
            LocalBudgetsCompanion.insert(
              id: 'budget-delete',
              referenceMonth: '$month-01',
              syncStatus: const Value('synced'),
            ),
          );
      await db
          .into(db.localBudgetItems)
          .insert(
            LocalBudgetItemsCompanion.insert(
              id: 'budget-item-delete',
              budgetId: 'budget-delete',
              categoryId: 'cat-delete',
              subcategoryId: const Value('sub-delete'),
              plannedAmount: const Value(250),
              accountId: const Value('acc-main'),
              syncStatus: const Value('synced'),
            ),
          );
      await db
          .into(db.localDebts)
          .insert(
            LocalDebtsCompanion.insert(
              id: 'debt-delete',
              name: 'Dívida',
              originalAmount: 1000,
              outstandingBalance: 500,
              categoryId: const Value('cat-delete'),
              subcategoryId: const Value('sub-delete'),
              budgetItemId: const Value('budget-item-delete'),
              syncStatus: const Value('synced'),
            ),
          );
      await repository.addTransaction(
        type: 'expense',
        description: 'Despesa categorizada',
        amount: 120,
        date: date,
        isPaid: true,
        accountId: 'acc-main',
        categoryId: 'cat-delete',
        subcategoryId: 'sub-delete',
      );
      await db.delete(db.pendingOperations).go();

      final category = await (db.select(
        db.localCategories,
      )..where((c) => c.id.equals('cat-delete'))).getSingle();

      expect(await repository.categoryHasReferences('cat-delete'), isTrue);
      await expectLater(
        repository.deleteCategory(category),
        throwsA(isA<StateError>()),
      );

      // Nada foi alterado: categoria, lançamento e orçamento permanecem.
      final after = await (db.select(
        db.localCategories,
      )..where((c) => c.id.equals('cat-delete'))).getSingle();
      expect(after.deletedAt == null, true);

      final transaction = await (db.select(db.localTransactions)).getSingle();
      expect(transaction.categoryId, 'cat-delete');
      expect(transaction.subcategoryId, 'sub-delete');

      final budgetItem = await (db.select(
        db.localBudgetItems,
      )..where((item) => item.id.equals('budget-item-delete'))).getSingle();
      expect(budgetItem.deletedAt == null, true);
      expect(await db.select(db.pendingOperations).get(), isEmpty);
    },
  );

  test('excluir categoria sem lançamentos remove subcategorias e '
      'desvincula dívidas', () async {
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-unused',
            name: 'Categoria sem uso',
            type: 'expense',
            syncStatus: const Value('synced'),
          ),
        );
    await db
        .into(db.localSubcategories)
        .insert(
          LocalSubcategoriesCompanion.insert(
            id: 'sub-unused',
            categoryId: 'cat-unused',
            name: 'Sub sem uso',
            syncStatus: const Value('synced'),
          ),
        );
    await db
        .into(db.localDebts)
        .insert(
          LocalDebtsCompanion.insert(
            id: 'debt-unused',
            name: 'Dívida',
            originalAmount: 1000,
            outstandingBalance: 500,
            categoryId: const Value('cat-unused'),
            subcategoryId: const Value('sub-unused'),
            syncStatus: const Value('synced'),
          ),
        );

    final category = await (db.select(
      db.localCategories,
    )..where((c) => c.id.equals('cat-unused'))).getSingle();

    expect(await repository.categoryHasReferences('cat-unused'), isFalse);
    await repository.deleteCategory(category);

    final after = await (db.select(
      db.localCategories,
    )..where((c) => c.id.equals('cat-unused'))).getSingle();
    expect(after.deletedAt != null, true);

    final subcategory = await (db.select(
      db.localSubcategories,
    )..where((s) => s.id.equals('sub-unused'))).getSingle();
    expect(subcategory.deletedAt != null, true);

    final debt = await (db.select(db.localDebts)).getSingle();
    expect(debt.categoryId == null, true);
    expect(debt.subcategoryId == null, true);
  });

  test('troca de usuário limpa dados persistidos do PWA', () async {
    await db.setStateValue('device_id', 'device-stable');
    await db.setStateValue('active_user_id', 'user-a');
    await db.setStateValue('pull_cursor', 'cursor-a');
    await repository.upsertAccount(
      id: 'acc-user-a',
      name: 'Conta antiga',
      type: 'checking',
      initialBalance: 10,
    );

    await repository.prepareLocalStoreForUser('user-b');

    expect(await db.select(db.localAccounts).get(), isEmpty);
    expect(await db.select(db.pendingOperations).get(), isEmpty);
    expect(await db.stateValue('active_user_id'), 'user-b');
    expect(await db.stateValue('pull_cursor'), '0');
    expect(await db.stateValue('device_id'), 'device-stable');
  });

  test(
    'quitação de fatura escolhe o ciclo pelo valor pago e baixa as compras',
    () async {
      await repository.upsertAccount(
        id: 'acc-pay',
        name: 'Conta',
        type: 'checking',
        initialBalance: 5000,
      );
      await db
          .into(db.localCreditCards)
          .insert(
            LocalCreditCardsCompanion.insert(
              id: 'card-1',
              name: 'Cartão',
              limitAmount: const Value(5000),
              closingDay: const Value(25),
              dueDay: const Value(10),
            ),
          );
      // Dois ciclos abertos: o de setembro (300) e o de outubro (450).
      for (final cycle in [
        ('buy-set', '2026-09-10', 300.0),
        ('buy-out', '2026-10-10', 450.0),
      ]) {
        await db
            .into(db.localTransactions)
            .insert(
              LocalTransactionsCompanion.insert(
                id: cycle.$1,
                type: 'expense',
                description: 'Compra ${cycle.$1}',
                amountPlanned: Value(cycle.$3),
                competenceDate: cycle.$2,
                dueDate: Value(cycle.$2),
                status: const Value('planned'),
                cardId: const Value('card-1'),
              ),
            );
      }
      final card = await (db.select(
        db.localCreditCards,
      )..where((c) => c.id.equals('card-1'))).getSingle();
      final txs = await db.select(db.localTransactions).get();

      // Paga 450 em setembro: o valor decide o ciclo, não a data.
      final cycle = repository.openInvoiceCycle(
        'card-1',
        txs,
        paymentDate: '2026-09-09',
        amount: 450,
      );
      expect(cycle.map((t) => t.id), ['buy-out']);

      await repository.payCardInvoice(
        card: card,
        transactions: cycle,
        accountId: 'acc-pay',
        paymentDate: '2026-09-09',
        paidAmount: 455.30,
        description: 'PAGTO FATURA CARTAO',
      );

      final after = await db.select(db.localTransactions).get();
      expect(after.singleWhere((t) => t.id == 'buy-out').status, 'paid');
      expect(after.singleWhere((t) => t.id == 'buy-set').status, 'planned');
      final settlement = after.singleWhere(
        (t) => FinanceRepository.isInvoiceSettlement(t),
      );
      expect(settlement.description, 'PAGTO FATURA CARTAO');
      expect(settlement.amount, 455.30);
      expect(settlement.accountId, 'acc-pay');
    },
  );

  test('quitação de dívida debita a conta escolhida no lançamento', () async {
    await repository.upsertAccount(
      id: 'acc-outra',
      name: 'Outra conta',
      type: 'checking',
      initialBalance: 3000,
    );
    await db
        .into(db.localCategories)
        .insert(
          LocalCategoriesCompanion.insert(
            id: 'cat-div',
            name: 'Dívidas',
            type: 'expense',
          ),
        );
    await db
        .into(db.localDebts)
        .insert(
          LocalDebtsCompanion.insert(
            id: 'debt-x',
            name: 'Empréstimo X',
            originalAmount: 1000,
            outstandingBalance: 1000,
            totalInstallments: const Value(2),
            installmentAmount: const Value(500),
            firstDueDate: const Value('2026-09-05'),
            accountId: const Value('acc-divida'),
          ),
        );
    final debt = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-x'))).getSingle();

    await repository.payDebtInstallment(
      debt: debt,
      plannedAmount: 500,
      amount: 500,
      dueDate: '2026-09-05',
      paymentDate: '2026-09-05',
      installmentNumber: 1,
      categoryId: 'cat-div',
      accountId: 'acc-outra',
      description: 'PARCELA EMPRESTIMO',
    );

    final payment = (await db.select(db.localTransactions).get()).single;
    expect(payment.accountId, 'acc-outra');
    expect(payment.description, 'PARCELA EMPRESTIMO');
    expect(FinanceRepository.isDebtPayment(payment), isTrue);
    final updated = await (db.select(
      db.localDebts,
    )..where((d) => d.id.equals('debt-x'))).getSingle();
    expect(updated.outstandingBalance, 500);
    expect(updated.paidInstallments, 1);
  });

  test('refaz o orçamento do mês com base no realizado do mês anterior', () async {
    for (final tx in [
      ('mercado-1', 'market', null, 400.0),
      ('mercado-2', 'market', 'sub-feira', 100.0),
      ('luz', 'utilities', null, 250.0),
    ]) {
      await db
          .into(db.localTransactions)
          .insert(
            LocalTransactionsCompanion.insert(
              id: tx.$1,
              type: 'expense',
              description: tx.$1,
              amount: Value(tx.$4),
              competenceDate: '2026-08-10',
              status: const Value('paid'),
              categoryId: Value(tx.$2),
              subcategoryId: Value(tx.$3),
            ),
          );
    }

    // Setembro criado a partir do orçamento de agosto: previsto = previsto.
    final august = await repository.createBudget(referenceMonth: '2026-08-01');
    await repository.upsertBudgetItem(
      budgetId: august,
      categoryId: 'market',
      plannedAmount: 900,
    );
    final september = await repository.generateBudget(
      fromMonth: '2026-08-01',
      toMonth: '2026-09-01',
    );
    expect(september != null, isTrue);
    var items = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull() & i.budgetId.equals(september!))).get();
    expect(items.single.plannedAmount, 900);

    // Sem replace, o mês já orçado é recusado.
    final refused = await repository.generateBudget(
      fromMonth: '2026-08-01',
      toMonth: '2026-09-01',
      source: BudgetSource.realized,
    );
    expect(refused == null, isTrue);

    // Com replace, o previsto vira o realizado de agosto, por subcategoria.
    final redone = await repository.generateBudget(
      fromMonth: '2026-08-01',
      toMonth: '2026-09-01',
      source: BudgetSource.realized,
      replace: true,
    );
    expect(redone, september);
    items = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull() & i.budgetId.equals(redone!))).get();
    expect(items, hasLength(3));
    expect(
      {for (final i in items) '${i.categoryId}|${i.subcategoryId}': i.plannedAmount},
      {'market|null': 400.0, 'market|sub-feira': 100.0, 'utilities|null': 250.0},
    );
  });
}
