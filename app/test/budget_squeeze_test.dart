import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/core/utils/money.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/remote/api_client.dart';
import 'package:hopecash/data/repositories/finance_repository.dart';
import 'package:hopecash/presentation/components/hope_components.dart';
import 'package:hopecash/presentation/screens/budget_screen.dart';

/// Aperto do previsto: arrastar a barra reduz o orçamento de uma linha até o
/// que o mês já consumiu, e nunca abaixo disso.
class _ApiAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'data': <Object>[]}),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// Mesmo padrão dos outros testes de tela: drena os timers dos streams do
/// drift para não cair no "Timer is still pending".
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  late AppDatabase db;
  late ApiClient api;
  late FinanceRepository repo;

  const categoryId = 'cat-food';
  final now = DateTime.now();
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    repo = FinanceRepository(db);
    api = ApiClient(dio: Dio()..httpClientAdapter = _ApiAdapter());
    await repo.upsertAccount(
      id: 'acc-1',
      name: 'Conta corrente',
      type: 'checking',
      initialBalance: 5000,
    );
    await repo.upsertCategory(
      id: categoryId,
      name: 'Alimentação',
      type: 'expense',
    );
  });

  tearDown(() => db.close());

  Future<void> planned(double amount) async {
    final budgetId = await repo.createBudget(referenceMonth: month);
    await repo.upsertBudgetItem(
      budgetId: budgetId,
      categoryId: categoryId,
      plannedAmount: amount,
    );
  }

  Future<void> consumed(double amount) => repo.addTransaction(
    type: 'expense',
    description: 'Mercado',
    amount: amount,
    date: todayIso(),
    isPaid: true,
    accountId: 'acc-1',
    categoryId: categoryId,
  );

  Future<double> storedPlanned() async {
    final item = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull())).getSingle();
    return item.plannedAmount;
  }

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const BudgetScreen()),
  );

  /// O realizado por item vem de uma cadeia de FutureProviders; um pump só não
  /// basta para ela resolver.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('arrasto trava no consumido e grava o previsto apertado', (
    tester,
  ) async {
    await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);

    // A situação aparece antes da ação: R$ 500,00 de folga em 1 linha.
    expect(
      find.textContaining('${formatMoney(500)} de folga'),
      findsOneWidget,
    );

    await tester.tap(find.text('Apertar previsto'));
    await tester.pumpAndSettle();
    expect(find.text('Aperto do previsto'), findsOneWidget);
    expect(find.text('Arraste para apertar'), findsOneWidget);

    // Arrasto bem além do piso: o valor tem que parar no consumido.
    await tester.drag(find.byType(Slider), const Offset(-2000, 0));
    await tester.pumpAndSettle();

    // R$ 300,00 duas vezes: o novo previsto encostou no consumido.
    expect(find.text(formatMoney(300)), findsNWidgets(2));
    expect(
      find.widgetWithText(FilledButton, 'Apertar ${formatMoney(500)}'),
      findsOneWidget,
    );

    await tester.tap(find.text('Apertar ${formatMoney(500)}'));
    await tester.pumpAndSettle();

    expect(await storedPlanned(), 300);
    // Sem folga sobrando, o convite para apertar sai da tela.
    expect(find.text('Apertar previsto'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('cancelar não grava o arrasto', (tester) async {
    await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Apertar previsto'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(await storedPlanned(), 800);

    await disposeApp(tester);
  });

  testWidgets('linha sem folga não oferece aperto', (tester) async {
    await planned(800);
    await consumed(820);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Apertar previsto'), findsNothing);
    expect(find.textContaining('de folga'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('aperto pela categoria trata as subcategorias juntas', (
    tester,
  ) async {
    await repo.upsertSubcategory(
      id: 'sub-market',
      categoryId: categoryId,
      name: 'Mercado',
    );
    await repo.upsertSubcategory(
      id: 'sub-delivery',
      categoryId: categoryId,
      name: 'Delivery',
    );
    final budgetId = await repo.createBudget(referenceMonth: month);
    await repo.upsertBudgetItem(
      budgetId: budgetId,
      categoryId: categoryId,
      subcategoryId: 'sub-market',
      plannedAmount: 600,
    );
    await repo.upsertBudgetItem(
      budgetId: budgetId,
      categoryId: categoryId,
      subcategoryId: 'sub-delivery',
      plannedAmount: 400,
    );
    await repo.addTransaction(
      type: 'expense',
      description: 'Feira',
      amount: 200,
      date: todayIso(),
      isPaid: true,
      accountId: 'acc-1',
      categoryId: categoryId,
      subcategoryId: 'sub-market',
    );

    await tester.pumpWidget(app());
    await settle(tester);

    // Entrada pelo cartão da categoria (a última das duas, já que o resumo do
    // mês também oferece o aperto).
    await tester.tap(find.text('Alimentação'));
    await tester.pumpAndSettle();
    final cardAction = find.widgetWithText(OutlinedButton, 'Apertar previsto');
    await tester.ensureVisible(cardAction.last);
    await tester.pumpAndSettle();
    await tester.tap(cardAction.last);
    await tester.pumpAndSettle();

    // Uma seção por item — os mesmos nomes também estão na lista atrás da
    // folha, então a busca se limita às seções da folha.
    Finder inSheet(String text) => find.descendant(
      of: find.byType(PremiumFormSection),
      matching: find.text(text),
    );
    expect(inSheet('Delivery'), findsOneWidget);
    expect(inSheet('Mercado'), findsOneWidget);

    for (final slider in [0, 1]) {
      await tester.drag(find.byType(Slider).at(slider), const Offset(-2000, 0));
      await tester.pumpAndSettle();
    }

    // 400 de Delivery + 400 de folga do Mercado. O total e o botão ficam abaixo
    // das duas barras: a folha rola até eles.
    final label = 'Apertar ${formatMoney(800)}';
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Folga liberada'), findsOneWidget);
    expect(find.text('2 linhas apertadas'), findsOneWidget);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    final items = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.deletedAt.isNull())).get();
    expect(
      {for (final item in items) item.subcategoryId: item.plannedAmount},
      {'sub-market': 200.0, 'sub-delivery': 0.0},
    );

    await disposeApp(tester);
  });

  testWidgets('a folha do aperto cabe em tela estreita', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await planned(1234.56);
    await consumed(345.67);

    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Apertar previsto'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(find.text('Aperto do previsto'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
