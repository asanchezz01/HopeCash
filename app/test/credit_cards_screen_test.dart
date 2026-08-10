import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/core/utils/money.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/remote/api_client.dart';
import 'package:hopecash/data/repositories/finance_repository.dart';
import 'package:hopecash/presentation/screens/credit_cards_screen.dart';

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

/// Mesmo padrão de `invoice_reconciliation_screen_test.dart`: drena os timers
/// dos streams do drift para não cair no "Timer is still pending".
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  late AppDatabase db;
  late ApiClient api;
  late FinanceRepository repo;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.test(NativeDatabase.memory());
    repo = FinanceRepository(db);
    await repo.upsertCreditCard(
      id: 'card-1',
      name: 'Cartão Hope',
      limitAmount: 5000,
      closingDay: 25,
      dueDay: 5,
    );
    final dio = Dio()..httpClientAdapter = _ApiAdapter();
    api = ApiClient(dio: dio);
  });

  tearDown(() => db.close());

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const CreditCardsScreen(),
    ),
  );

  /// O valor em aberto vem de um FutureProvider encadeado em dois outros
  /// providers; um pump só não basta para a cadeia resolver.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> spend(double amount) async {
    final card = await (db.select(
      db.localCreditCards,
    )..where((c) => c.id.equals('card-1'))).getSingle();
    await repo.addCardExpense(
      card: card,
      description: 'Compra',
      totalAmount: amount,
      purchaseDate: '2026-08-01',
    );
  }

  testWidgets('cartão sem gasto mostra limite cheio disponível', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Limite'), findsOneWidget);
    expect(find.text('Utilizado'), findsOneWidget);
    expect(find.text('Disponível'), findsOneWidget);
    expect(find.text(formatMoney(5000)), findsNWidgets(2)); // limite e disponível
    expect(find.text(formatMoney(0)), findsOneWidget); // utilizado

    await disposeApp(tester);
  });

  testWidgets('utilizado abate do disponível', (tester) async {
    await spend(1200);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text(formatMoney(5000)), findsOneWidget); // limite
    expect(find.text(formatMoney(1200)), findsOneWidget); // utilizado
    expect(find.text(formatMoney(3800)), findsOneWidget); // disponível

    await disposeApp(tester);
  });

  testWidgets('gasto acima do limite deixa o disponível negativo', (
    tester,
  ) async {
    await spend(5600);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text(formatMoney(5600)), findsOneWidget); // utilizado
    expect(find.text(formatMoney(-600)), findsOneWidget); // disponível estourado

    await disposeApp(tester);
  });

  testWidgets('fechamento e vencimento continuam visíveis', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(
      find.text('Fechamento dia 25 · Vencimento dia 5'),
      findsOneWidget,
    );

    await disposeApp(tester);
  });
}
