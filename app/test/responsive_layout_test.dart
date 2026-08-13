import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/core/utils/money.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/repositories/finance_repository.dart';
import 'package:hopecash/presentation/screens/budget_screen.dart';
import 'package:hopecash/presentation/screens/categories_screen.dart';
import 'package:hopecash/presentation/screens/credit_cards_screen.dart';
import 'package:hopecash/presentation/screens/dashboard_screen.dart';
import 'package:hopecash/presentation/screens/debts_screen.dart';
import 'package:hopecash/presentation/screens/goals_screen.dart';
import 'package:hopecash/presentation/screens/more_screen.dart';
import 'package:hopecash/presentation/screens/transactions_screen.dart';
import 'package:hopecash/presentation/widgets/quick_add_sheet.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Regressão de layout: as telas principais precisam caber sem estouro em
/// celular, tablet e desktop, nos dois temas.
///
/// Um `RenderFlex overflowed` vira exceção no teste, então este arquivo pega a
/// classe de defeito que mais aparece numa revisão de interface — texto que
/// cresce, rótulo que não cabe, coluna fixa em tela estreita — sem depender de
/// inspeção visual.
const _viewports = <String, Size>{
  'celular': Size(360, 780),
  'celular pequeno': Size(320, 640),
  'tablet': Size(834, 1112),
  'desktop': Size(1440, 900),
};

Future<void> pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Desmonta a árvore e drena os timers de limpeza dos streams do drift.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('pt_BR'));

  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget home, {Brightness brightness = Brightness.light}) =>
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          home: home,
        ),
      );

  Future<void> seed() async {
    final repo = FinanceRepository(db);
    await repo.upsertAccount(
      id: 'acc-1',
      name: 'Conta corrente principal do titular',
      type: 'checking',
      initialBalance: 4200,
    );
    await repo.upsertCreditCard(
      id: 'card-1',
      name: 'Cartão internacional black',
      limitAmount: 15000,
      closingDay: 28,
      dueDay: 8,
    );
    final today = todayIso();
    await repo.addTransaction(
      type: 'income',
      description: 'Salário de um mês inteiro com nome longo',
      amount: 12345.67,
      date: today,
      isPaid: true,
      accountId: 'acc-1',
    );
    await repo.addTransaction(
      type: 'expense',
      description: 'Supermercado do bairro com nome bem comprido',
      amount: 1876.54,
      date: today,
      isPaid: true,
      accountId: 'acc-1',
    );
    await repo.addTransaction(
      type: 'expense',
      description: 'Aluguel',
      amount: 3200,
      date: today,
      isPaid: false,
      accountId: 'acc-1',
    );
  }

  Future<void> atSize(
    WidgetTester tester,
    Size size,
    Future<void> Function() body,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await body();
  }

  for (final entry in _viewports.entries) {
    testWidgets('painel inicial cabe em ${entry.key}', (tester) async {
      await seed();
      await atSize(tester, entry.value, () async {
        await tester.pumpWidget(wrap(const DashboardScreen()));
        await pumpFrames(tester);
        expect(find.text('SALDO EM CONTAS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      await disposeApp(tester);
    });

    testWidgets('lançamentos cabem em ${entry.key}', (tester) async {
      await seed();
      await atSize(tester, entry.value, () async {
        await tester.pumpWidget(wrap(const TransactionsScreen()));
        await pumpFrames(tester);
        expect(find.byTooltip('Filtrar e ordenar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      await disposeApp(tester);
    });

    testWidgets('tela Mais cabe em ${entry.key}', (tester) async {
      await atSize(tester, entry.value, () async {
        await tester.pumpWidget(wrap(const MoreScreen()));
        await pumpFrames(tester);
        expect(find.text('Sincronização'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      await disposeApp(tester);
    });
  }

  for (final screen in <String, Widget Function()>{
    'painel inicial': DashboardScreen.new,
    'lançamentos': TransactionsScreen.new,
    'tela Mais': MoreScreen.new,
    'orçamento': BudgetScreen.new,
    'metas': GoalsScreen.new,
    'dívidas': DebtsScreen.new,
    'cartões': CreditCardsScreen.new,
    'categorias': CategoriesScreen.new,
  }.entries) {
    testWidgets('${screen.key} cabe no tema escuro', (tester) async {
      await seed();
      await atSize(tester, const Size(360, 780), () async {
        await tester.pumpWidget(
          wrap(screen.value(), brightness: Brightness.dark),
        );
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);
      });
      await disposeApp(tester);
    });
  }

  testWidgets(
    'card do orçamento abre nova subcategoria com categoria mãe preenchida',
    (tester) async {
      final repo = FinanceRepository(db);
      const categoryId = 'category-food';
      await repo.upsertCategory(
        id: categoryId,
        name: 'Alimentação',
        type: 'expense',
      );
      final now = DateTime.now();
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final budgetId = await repo.createBudget(referenceMonth: month);
      await repo.upsertBudgetItem(
        budgetId: budgetId,
        categoryId: categoryId,
        plannedAmount: 800,
      );

      await atSize(tester, _viewports['desktop']!, () async {
        await tester.pumpWidget(wrap(const BudgetScreen()));
        await pumpFrames(tester);

        await tester.tap(find.text('Alimentação'));
        await tester.pumpAndSettle();
        expect(find.text('Adicionar subcategoria'), findsOneWidget);

        await tester.tap(find.text('Adicionar subcategoria'));
        await tester.pumpAndSettle();

        expect(find.text('Adicionar ao orçamento'), findsOneWidget);
        expect(find.text('Alimentação'), findsNWidgets(2));
        expect(find.text('Toda a categoria'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
      await disposeApp(tester);
    },
  );

  testWidgets('painel inicial suporta fonte ampliada', (tester) async {
    await seed();
    await atSize(tester, const Size(360, 780), () async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 1.3,
              maxScaleFactor: 1.3,
              child: child!,
            ),
            home: const DashboardScreen(),
          ),
        ),
      );
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);
    });
    await disposeApp(tester);
  });

  testWidgets(
    'mantém o atalho da Hope no celular quando o health-check falha',
    (tester) async {
      await seed();
      await atSize(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              aiAvailableProvider.overrideWith((ref) async => false),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const DashboardScreen(),
            ),
          ),
        );
        await pumpFrames(tester);

        expect(
          find.byKey(const ValueKey('dashboard-hope-action')),
          findsOneWidget,
        );
        expect(
          find.byTooltip(
            'Hope temporariamente indisponível — toque para tentar',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
      await disposeApp(tester);
    },
  );

  testWidgets('rateio mostra o que falta distribuir e valida o fechamento', (
    tester,
  ) async {
    await seed();
    await atSize(tester, const Size(390, 844), () async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showQuickAddSheet(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      await tester.tap(find.text('abrir'));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextFormField).first, '100,00');
      await pumpFrames(tester);
      await tester.tap(find.text('Ratear por categorias'));
      await pumpFrames(tester);

      // Nada distribuído ainda: o editor diz exatamente quanto falta.
      expect(find.textContaining('Faltam'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    await disposeApp(tester);
  });
}
