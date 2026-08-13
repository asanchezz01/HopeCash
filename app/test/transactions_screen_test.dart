import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/core/utils/money.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/repositories/finance_repository.dart';
import 'package:hopecash/presentation/screens/transactions_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Bombeia alguns frames com duração fixa. Não usa pumpAndSettle porque o
/// esqueleto de carregamento (shimmer) anima em loop e nunca "assenta".
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Desmonta a árvore e drena os timers de limpeza dos streams do drift, para
/// não disparar o invariante "Timer is still pending" do framework de teste.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Tipo, origem e ordenação moraram numa pilha de faixas fixas até a revisão de
/// interface; hoje vivem numa folha, aberta pelo botão de filtros.
Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Filtrar e ordenar'));
  await pumpFrames(tester);
}

Future<void> closeFilters(WidgetTester tester) async {
  await tester.tap(find.text('Ver resultados'));
  await pumpFrames(tester);
}

/// Abre a folha, escolhe uma origem (conta ou cartão) e volta para a lista.
Future<void> selectSource(WidgetTester tester, String label) async {
  await openFilters(tester);
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await pumpFrames(tester);
  await closeFilters(tester);
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

  Widget buildApp({
    DateTime? month,
    String? initialSourceKind,
    String? initialSourceId,
  }) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      if (month != null) selectedMonthProvider.overrideWith((ref) => month),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: TransactionsScreen(
        initialSourceKind: initialSourceKind,
        initialSourceId: initialSourceId,
      ),
    ),
  );

  Future<void> seedData() async {
    final repo = FinanceRepository(db);
    await repo.upsertAccount(
      id: 'acc-1',
      name: 'Conta Hope',
      type: 'checking',
      initialBalance: 0,
    );
    await repo.upsertCreditCard(
      id: 'card-1',
      name: 'Cartão Hope',
      limitAmount: 5000,
      closingDay: 28,
      dueDay: 8,
    );
    final today = todayIso();
    // Efetivado na conta.
    await repo.addTransaction(
      type: 'expense',
      description: 'Padaria',
      amount: 50,
      date: today,
      isPaid: true,
      accountId: 'acc-1',
    );
    // Previsto na conta (ainda não aconteceu).
    await repo.addTransaction(
      type: 'expense',
      description: 'Aluguel',
      amount: 2000,
      date: today,
      isPaid: false,
      accountId: 'acc-1',
    );
    // Compra na fatura do cartão (planned até o pagamento da fatura).
    await repo.addTransaction(
      type: 'expense',
      description: 'Notebook (1/3)',
      amount: 1200,
      date: today,
      isPaid: false,
      cardId: 'card-1',
    );
    // Liquidação de fatura: débito na conta vinculado ao cartão.
    await repo.addTransaction(
      type: 'expense',
      description: 'Pagamento fatura Cartão Hope',
      amount: 300,
      date: today,
      isPaid: true,
      accountId: 'acc-1',
      cardId: 'card-1',
    );
  }

  testWidgets('Extrato é padrão; Previsto mostra também o que falta realizar', (
    tester,
  ) async {
    await seedData();
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);

    // Extrato (padrão): só movimentações efetivadas da conta, incluindo a
    // liquidação da fatura.
    expect(find.text('Padaria'), findsOneWidget);
    expect(find.text('Pagamento fatura Cartão Hope'), findsOneWidget);
    expect(find.text('Aluguel'), findsNothing);
    expect(find.text('Notebook (1/3)'), findsNothing);
    expect(find.text('Entradas'), findsOneWidget);
    expect(find.text('Saídas'), findsOneWidget);
    expect(find.text('Resultado'), findsOneWidget);
    await openFilters(tester);
    expect(find.text('Receitas previstas'), findsNothing);
    expect(find.text('Pendentes'), findsNothing);
    await closeFilters(tester);

    // Previsto reúne realizados e pendentes e expõe os filtros próprios.
    await tester.tap(find.text('Previsto'));
    await pumpFrames(tester);
    expect(find.text('Padaria'), findsOneWidget);
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Notebook (1/3)'), findsOneWidget);
    expect(find.text('Realizado'), findsOneWidget);
    expect(find.text('A realizar'), findsOneWidget);
    expect(find.text('Projeção do mês'), findsOneWidget);
    await openFilters(tester);
    expect(find.text('Receitas previstas'), findsOneWidget);
    expect(find.text('Pendentes'), findsOneWidget);
    expect(find.text('Efetivados'), findsOneWidget);
    await closeFilters(tester);

    await disposeApp(tester);
  });

  testWidgets('Previsto filtra lançamentos pendentes e efetivados', (
    tester,
  ) async {
    await seedData();
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);
    await tester.tap(find.text('Previsto'));
    await pumpFrames(tester);

    await openFilters(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pendentes'));
    await pumpFrames(tester);
    await closeFilters(tester);

    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Notebook (1/3)'), findsOneWidget);
    expect(find.text('Padaria'), findsNothing);
    expect(find.text('Pagamento fatura Cartão Hope'), findsNothing);
    expect(find.text('Pendentes'), findsOneWidget);

    await openFilters(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Efetivados'));
    await pumpFrames(tester);
    await closeFilters(tester);

    expect(find.text('Padaria'), findsOneWidget);
    expect(find.text('Pagamento fatura Cartão Hope'), findsOneWidget);
    expect(find.text('Aluguel'), findsNothing);
    expect(find.text('Notebook (1/3)'), findsNothing);
    expect(find.text('Efetivados'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('Extrato com cartão selecionado confere a fatura', (
    tester,
  ) async {
    await seedData();
    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);

    await selectSource(tester, 'Cartão Hope');

    // Compras do cartão aparecem; a liquidação (débito na conta) não é uma
    // compra da fatura e fica de fora, assim como movimentações de conta.
    expect(find.text('Notebook (1/3)'), findsOneWidget);
    expect(find.text('Padaria'), findsNothing);
    expect(find.text('Pagamento fatura Cartão Hope'), findsNothing);
    expect(find.text('Compras'), findsOneWidget);
    expect(find.text('Estornos'), findsOneWidget);
    expect(find.text('Total no mês'), findsOneWidget);
    expect(find.textContaining('fatura '), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('extrato do cartão exclui previsões futuras e mantém parcelas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = FinanceRepository(db);
    await repo.upsertCreditCard(
      id: 'card-1',
      name: 'Cartão Hope',
      limitAmount: 5000,
      closingDay: 28,
      dueDay: 8,
    );
    // Compra real parcelada: a 2ª parcela cai no mês seguinte (competência
    // futura), mas já pertence à fatura.
    await repo.addCardExpense(
      card: (await db.select(db.localCreditCards).get()).single,
      description: 'Notebook',
      totalAmount: 1000,
      purchaseDate: todayIso(),
      installments: 2,
    );
    // Previsão futura lançada no cartão (ex.: assinatura prevista): não é
    // compra efetivada.
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    final forecastDate =
        '${nextMonth.year.toString().padLeft(4, '0')}-'
        '${nextMonth.month.toString().padLeft(2, '0')}-05';
    await repo.addTransaction(
      type: 'expense',
      description: 'Assinatura prevista',
      amount: 80,
      date: forecastDate,
      isPaid: false,
      cardId: 'card-1',
    );

    await tester.pumpWidget(buildApp(month: nextMonth));
    await pumpFrames(tester);

    await selectSource(tester, 'Cartão Hope');

    expect(find.text('Notebook (2/2)'), findsOneWidget);
    expect(find.text('Assinatura prevista'), findsNothing);

    // No modo Previsto a previsão aparece normalmente.
    await tester.tap(find.text('Previsto'));
    await pumpFrames(tester);
    expect(find.text('Assinatura prevista'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('extrato permite alternar a ordenação por data', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = FinanceRepository(db);
    await repo.upsertAccount(
      id: 'acc-1',
      name: 'Conta Hope',
      type: 'checking',
      initialBalance: 0,
    );
    await repo.addTransaction(
      type: 'expense',
      description: 'Compra antiga',
      amount: 10,
      date: '2026-05-05',
      isPaid: true,
      accountId: 'acc-1',
    );
    await repo.addTransaction(
      type: 'expense',
      description: 'Compra recente',
      amount: 20,
      date: '2026-05-20',
      isPaid: true,
      accountId: 'acc-1',
    );

    await tester.pumpWidget(buildApp(month: DateTime(2026, 5)));
    await pumpFrames(tester);
    // Padrão: mais recentes primeiro.
    expect(
      tester.getTopLeft(find.text('20/05/2026')).dy,
      lessThan(tester.getTopLeft(find.text('05/05/2026')).dy),
    );

    await openFilters(tester);
    await tester.tap(find.text('Mais antigas'));
    await pumpFrames(tester);
    await closeFilters(tester);

    // A ordenação ativa volta para a barra como etiqueta removível.
    expect(find.text('Mais antigas primeiro'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('05/05/2026')).dy,
      lessThan(tester.getTopLeft(find.text('20/05/2026')).dy),
    );

    await disposeApp(tester);
  });

  testWidgets('resumo mantém valores monetários em uma única linha', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = FinanceRepository(db);
    await repo.upsertAccount(
      id: 'acc-1',
      name: 'Conta Hope',
      type: 'checking',
      initialBalance: 0,
    );
    await repo.addTransaction(
      type: 'income',
      description: 'Receita de cinco dígitos',
      amount: 12345.67,
      date: todayIso(),
      isPaid: true,
      accountId: 'acc-1',
    );

    await tester.pumpWidget(buildApp());
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    final summaryCard = find
        .ancestor(of: find.text('Entradas'), matching: find.byType(Card))
        .first;
    final moneyTexts = tester
        .widgetList<Text>(
          find.descendant(of: summaryCard, matching: find.byType(Text)),
        )
        .where((text) => text.data?.contains(r'R$') ?? false);
    expect(moneyTexts, isNotEmpty);
    for (final text in moneyTexts) {
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
    }

    await disposeApp(tester);
  });

  testWidgets('trocar de origem persiste mesmo com filtro inicial da rota', (
    tester,
  ) async {
    await seedData();

    // Aberta via "ver lançamentos" da conta: o filtro da rota se aplica...
    await tester.pumpWidget(
      buildApp(initialSourceKind: 'account', initialSourceId: 'acc-1'),
    );
    await pumpFrames(tester);
    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    await openFilters(tester);
    expect(chip('Conta Hope').selected, isTrue);
    await closeFilters(tester);

    // ...mas uma troca manual de origem não pode ser desfeita no frame
    // seguinte (regressão: a tela "piscava" e voltava para a conta).
    await selectSource(tester, 'Cartão Hope');
    await openFilters(tester);
    expect(chip('Cartão Hope').selected, isTrue);
    expect(chip('Conta Hope').selected, isFalse);
    await closeFilters(tester);
    expect(find.text('Notebook (1/3)'), findsOneWidget);

    await disposeApp(tester);
  });
}
