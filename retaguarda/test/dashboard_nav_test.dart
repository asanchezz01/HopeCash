import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash_retaguarda/app.dart';
import 'package:hopecash_retaguarda/core/providers.dart';
import 'package:hopecash_retaguarda/data/models/ai_health.dart';
import 'package:hopecash_retaguarda/data/models/api_version.dart';
import 'package:hopecash_retaguarda/data/models/app_user.dart';
import 'package:hopecash_retaguarda/data/models/retaguarda_user.dart';

void main() {
  testWidgets('card "Equipe da retaguarda" navega para a lista', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => const RetaguardaUser(
              id: '1',
              name: 'Teste Admin',
              email: 't@t.com',
              role: 'superuser',
              status: 'active',
            ),
          ),
          statsProvider.overrideWith(
            (ref) async => const RetaguardaStats(
              appUsersTotal: 0,
              appUsersActive: 0,
              appUsersBlocked: 0,
              retaguardaUsersTotal: 1,
            ),
          ),
          dashboardUsersProvider.overrideWith((ref) async => <AppUser>[]),
          aiHealthProvider.overrideWith(
            (ref) async => const AiHealth(ok: false, url: ''),
          ),
          retaguardaUsersProvider.overrideWith(
            (ref) async => <RetaguardaUser>[],
          ),
          apiVersionProvider.overrideWith(
            (ref) async => const ApiVersion(version: '0.1.0', ref: '0f94397'),
          ),
        ],
        child: const RetaguardaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Contas'), findsOneWidget);
    expect(find.text('Cartões de crédito'), findsOneWidget);
    expect(find.text('Dívidas'), findsOneWidget);
    expect(find.text('Orçamentos'), findsOneWidget);
    expect(find.text('Lançamentos de receita'), findsOneWidget);
    expect(find.text('Lançamentos de despesa'), findsOneWidget);
    expect(find.text('Todos os usuários'), findsOneWidget);

    // Traz o card para a viewport (ele fica abaixo da dobra) e toca.
    final card = find.text('Equipe da retaguarda');
    await tester.dragUntilVisible(
      card,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(
      find.text('Administradores com acesso a este painel.'),
      findsOneWidget,
      reason: 'O card deveria navegar para a lista da equipe da retaguarda.',
    );
  });
}
