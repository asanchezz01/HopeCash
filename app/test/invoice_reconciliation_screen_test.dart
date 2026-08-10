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
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/remote/api_client.dart';
import 'package:hopecash/data/repositories/finance_repository.dart';
import 'package:hopecash/presentation/screens/card_invoices_screen.dart';
import 'package:hopecash/presentation/screens/import_screen.dart';

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

/// Desmonta a árvore e drena os timers de limpeza dos streams do drift, para
/// não disparar o invariante "Timer is still pending" do framework de teste.
/// Mesmo padrão já usado em `transactions_screen_test.dart`.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  late AppDatabase db;
  late ApiClient api;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.test(NativeDatabase.memory());
    await FinanceRepository(db).upsertCreditCard(
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

  Widget app(Widget home) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  testWidgets(
    'entrada contextual abre o mesmo importador preenchido para fatura',
    (tester) async {
      await tester.pumpWidget(
        app(
          const ImportScreen(
            initialCardId: 'card-1',
            initialReferenceMonth: '2026-07-01',
            initialDueDate: '2026-07-05',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Fatura de cartão'), findsOneWidget);
      expect(find.text('Cartão Hope'), findsOneWidget);
      expect(find.text('Ref.: 07/2026'), findsOneWidget);
      expect(find.text('Venc.: 05/07/2026'), findsOneWidget);
      expect(
        find.textContaining('diferença exata de R\$ 0,00'),
        findsOneWidget,
      );

      await disposeApp(tester);
    },
  );

  testWidgets('tela da fatura expõe ação de importar e conciliar', (
    tester,
  ) async {
    await tester.pumpWidget(app(const CardInvoicesScreen(cardId: 'card-1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Importar e conciliar fatura'), findsOneWidget);

    await disposeApp(tester);
  });
}
