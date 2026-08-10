import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/data/remote/ai_api.dart';
import 'package:hopecash/data/remote/api_client.dart';
import 'package:hopecash/presentation/screens/ai_chat_screen.dart';

class _FakeAiApi extends AiApi {
  _FakeAiApi() : super(ApiClient());

  @override
  Stream<AiChatEvent> chat({
    String? conversationId,
    required String message,
  }) async* {
    yield const AiChatEvent('action', {
      'id': 'action-1',
      'tool_name': 'create_transaction',
      'status': 'proposed',
      'expires_at': '2026-07-17 12:00:00.000',
      'payload': {
        'type': 'expense',
        'description': 'Mercado',
        'amount': 50,
        'date': '2026-07-17',
        'paid': true,
      },
      'summary': {
        'title': 'Nova despesa',
        'fields': [
          {'label': 'Valor', 'value': 50, 'kind': 'money'},
        ],
      },
    });
    yield const AiChatEvent('done', {});
  }
}

void main() {
  testWidgets('permite sair do chat aberto diretamente no desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/ai-chat',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Início')),
        ),
        GoRoute(path: '/ai-chat', builder: (_, _) => const AiChatScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );

    expect(find.byTooltip('Sair do chat'), findsOneWidget);

    await tester.tap(find.byTooltip('Sair do chat'));
    await tester.pumpAndSettle();

    expect(find.text('Início'), findsOneWidget);
    expect(find.byType(AiChatScreen), findsNothing);
  });

  testWidgets('mostra Confirmar no card de ação em tela estreita', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiApiProvider.overrideWithValue(_FakeAiApi())],
        child: MaterialApp(theme: AppTheme.light(), home: const AiChatScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Lance 50 de mercado');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    final confirm = find.text('Confirmar');
    expect(confirm, findsOneWidget);
    expect(confirm.hitTestable(), findsOneWidget);

    final rect = tester.getRect(confirm);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
  });

  testWidgets(
    'card de lançamento tem Recusar, Revisar e Confirmar com a mesma altura',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiApiProvider.overrideWithValue(_FakeAiApi())],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AiChatScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Lance 50 de mercado');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      final heights = <double>[];
      for (final label in ['Recusar', 'Revisar', 'Confirmar']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) => w is OutlinedButton || w is FilledButton,
          ),
        );
        expect(button, findsOneWidget, reason: 'botão $label ausente');
        heights.add(tester.getSize(button).height);
      }
      expect(heights.toSet(), hasLength(1), reason: 'alturas diferentes');
    },
  );
}
