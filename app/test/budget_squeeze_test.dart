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
import 'package:hopecash/presentation/screens/budget_screen.dart';

/// Aperto do previsto: a própria barra de execução é a alça. Arrastar para a
/// esquerda encolhe o previsto da linha até o consumido, e nunca abaixo dele.
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

  Future<String> planned(double amount, {String? subcategoryId}) async {
    final budgetId =
        (await (db.select(db.localBudgets)
              ..where((b) => b.deletedAt.isNull()))
            .get()).firstOrNull?.id ??
        await repo.createBudget(referenceMonth: month);
    return repo.upsertBudgetItem(
      budgetId: budgetId,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      plannedAmount: amount,
    );
  }

  Future<void> consumed(double amount, {String? subcategoryId}) =>
      repo.addTransaction(
        type: 'expense',
        description: 'Mercado',
        amount: amount,
        date: todayIso(),
        isPaid: true,
        accountId: 'acc-1',
        categoryId: categoryId,
        subcategoryId: subcategoryId,
      );

  Future<double> storedPlanned(String itemId) async {
    final item = await (db.select(
      db.localBudgetItems,
    )..where((i) => i.id.equals(itemId))).getSingle();
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

  Finder barOf(String itemId) => find.byKey(ValueKey('budget-squeeze-$itemId'));
  Finder headBarOf(String itemId) =>
      find.byKey(ValueKey('budget-squeeze-head-$itemId'));

  /// Arrasta a barra até a fração pedida da própria largura. O primeiro passo
  /// existe só para vencer o slop de toque e virar arraste de verdade.
  Future<void> dragBarTo(
    WidgetTester tester,
    Finder bar,
    double fraction,
  ) async {
    final rect = tester.getRect(bar);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    await gesture.moveTo(
      Offset(rect.left + rect.width * fraction, rect.center.dy),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('arrastar a barra da categoria grava o previsto apertado', (
    tester,
  ) async {
    final itemId = await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);

    // A folga é anunciada com o gesto que a recolhe.
    expect(
      find.textContaining('${formatMoney(500)} de folga'),
      findsOneWidget,
    );
    expect(find.textContaining('arraste a ponta da barra'), findsOneWidget);
    // Nada de botão nem de folha: o controle é a própria barra.
    expect(find.text('Apertar previsto'), findsNothing);

    // Metade da régua (o previsto original de R$ 800,00).
    await dragBarTo(tester, headBarOf(itemId), 0.5);

    expect(await storedPlanned(itemId), 400);
    expect(find.text('Desfazer'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('o consumido é um muro: arrastar além dele para no piso', (
    tester,
  ) async {
    final itemId = await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);

    await dragBarTo(tester, headBarOf(itemId), -0.5);

    expect(await storedPlanned(itemId), 300);

    await disposeApp(tester);
  });

  testWidgets('desfazer devolve o previsto anterior', (tester) async {
    final itemId = await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);
    await dragBarTo(tester, headBarOf(itemId), 0.5);
    expect(await storedPlanned(itemId), 400);

    await tester.tap(find.text('Desfazer'));
    await settle(tester);

    expect(await storedPlanned(itemId), 800);

    await disposeApp(tester);
  });

  testWidgets('linha sem folga não se mexe', (tester) async {
    final itemId = await planned(800);
    await consumed(820);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.textContaining('de folga'), findsNothing);
    await dragBarTo(tester, headBarOf(itemId), 0.3);

    expect(await storedPlanned(itemId), 800);

    await disposeApp(tester);
  });

  testWidgets('toque na linha continua abrindo o formulário', (tester) async {
    await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Alimentação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toda a categoria').first);
    await tester.pumpAndSettle();

    expect(find.text('Editar item'), findsOneWidget);
    expect(find.text('Valor previsto'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('subcategoria tem a própria barra dentro do cartão', (
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
    final marketId = await planned(600, subcategoryId: 'sub-market');
    final deliveryId = await planned(400, subcategoryId: 'sub-delivery');
    await consumed(200, subcategoryId: 'sub-market');

    await tester.pumpWidget(app());
    await settle(tester);

    // Com duas linhas, a barra do cabeçalho é só leitura — o arraste seria
    // ambíguo. Quem aperta é a barra de cada subcategoria.
    await tester.tap(find.text('Alimentação'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(barOf(marketId));
    await tester.pumpAndSettle();
    await dragBarTo(tester, barOf(marketId), 0.5);

    expect(await storedPlanned(marketId), 300);
    expect(await storedPlanned(deliveryId), 400);

    await disposeApp(tester);
  });

  testWidgets('barra da linha aperta a mesma categoria de dentro do cartão', (
    tester,
  ) async {
    final itemId = await planned(800);
    await consumed(300);

    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Alimentação'));
    await tester.pumpAndSettle();

    // Cartão aberto: cabeçalho e linha controlam o mesmo item, com chaves
    // distintas. Arrastar a de dentro grava igual.
    expect(headBarOf(itemId), findsOneWidget);
    await tester.ensureVisible(barOf(itemId));
    await tester.pumpAndSettle();
    await dragBarTo(tester, barOf(itemId), 0.75);

    expect(await storedPlanned(itemId), 600);

    await disposeApp(tester);
  });

  testWidgets('a barra cabe e responde em tela estreita', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final itemId = await planned(1000);
    await consumed(250);

    await tester.pumpWidget(app());
    await settle(tester);

    await dragBarTo(tester, headBarOf(itemId), 0.6);

    expect(await storedPlanned(itemId), 600);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
