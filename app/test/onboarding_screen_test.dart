import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/repositories/auth_repository.dart';
import 'package:hopecash/presentation/screens/onboarding_screen.dart';

void main() {
  late AppDatabase db;

  const user = AuthUser(id: 'user-1', name: 'Teste', email: 't@t.dev');

  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      authStateProvider.overrideWith((ref) => user),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const OnboardingScreen()),
  );

  testWidgets('navega por botão e swipe entre as etapas', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao HopeCash'), findsOneWidget);
    expect(find.text('Pular'), findsOneWidget);
    expect(find.text('Voltar'), findsNothing); // primeira página

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('Lançamentos: o coração do app'), findsOneWidget);
    expect(find.text('Salário'), findsOneWidget);
    expect(find.text('Voltar'), findsOneWidget);

    // Swipe para a esquerda avança.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Categorias organizam tudo'), findsOneWidget);

    // Swipe para a direita volta.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Lançamentos: o coração do app'), findsOneWidget);
  });

  testWidgets('etapas da Hope e do MCP fecham o tutorial', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Dashboard: o resultado de tudo'), findsOneWidget);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('Conheça a Hope, sua assistente'), findsOneWidget);
    expect(find.text('Quanto gastei este mês?'), findsOneWidget);
    // As três formas de conversar com ela.
    expect(find.text('Digite'), findsOneWidget);
    expect(find.text('Fale'), findsOneWidget);
    expect(find.text('Ouça'), findsOneWidget);
    expect(find.text('Começar'), findsNothing);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('A Hope também lança por você'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('Plugue o ChatGPT ou o Claude'), findsOneWidget);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Gerar meu token agora'), findsOneWidget);
    expect(find.text('Começar'), findsOneWidget);
    expect(find.text('Próximo'), findsNothing);

    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    expect(await db.stateValue('onboarding_completed_user-1'), '1');
  });

  testWidgets('todas as etapas cabem numa tela estreita', (tester) async {
    // As ilustrações têm réplicas de UI (barra de navegação, chips, cards de
    // ação) que já estouraram em telas pequenas — este teste falha em qualquer
    // overflow, porque o pumpAndSettle propaga a exceção de layout.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Plugue o ChatGPT ou o Claude'), findsOneWidget);
  });

  testWidgets('pular salva a marca de concluído', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    expect(await db.stateValue('onboarding_completed_user-1'), '1');
  });
}
