import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash_retaguarda/core/providers.dart';
import 'package:hopecash_retaguarda/core/theme/app_theme.dart';
import 'package:hopecash_retaguarda/data/models/app_user.dart';
import 'package:hopecash_retaguarda/data/models/automation_rule.dart';
import 'package:hopecash_retaguarda/data/models/retaguarda_user.dart';
import 'package:hopecash_retaguarda/data/models/push_campaign.dart';
import 'package:hopecash_retaguarda/presentation/screens/app_users_screen.dart';
import 'package:hopecash_retaguarda/presentation/screens/automation_rules_screen.dart';
import 'package:hopecash_retaguarda/presentation/screens/notifications_screen.dart';
import 'package:hopecash_retaguarda/presentation/screens/retaguarda_users_screen.dart';

Widget _wrap(Widget child, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.light(),
    // Espelha producao: o shell coloca a tela dentro de um Scaffold.
    home: Scaffold(body: child),
  ),
);

void main() {
  final user = const RetaguardaUser(
    id: '1',
    name: 'Admin',
    email: 'a@a.com',
    role: 'superuser',
    status: 'active',
  );

  testWidgets('AppUsersScreen renderiza sem excecao (dentro de Scaffold)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppUsersScreen(), [
        authStateProvider.overrideWith((ref) => user),
        appUsersProvider.overrideWith(
          (ref) async => const AppUserPage(users: [], total: 0),
        ),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.takeException(),
      isNull,
      reason: 'AppUsersScreen nao deveria lancar',
    );
  });

  testWidgets('AppUsersScreen indica usuario com push vinculado', (
    tester,
  ) async {
    const appUser = AppUser(
      id: 'push-user',
      name: 'Usuário Push',
      email: 'push@teste.dev',
      status: 'active',
      hasPushToken: true,
    );
    await tester.pumpWidget(
      _wrap(const AppUsersScreen(), [
        authStateProvider.overrideWith((ref) => user),
        appUsersProvider.overrideWith(
          (ref) async => const AppUserPage(users: [appUser], total: 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(find.byTooltip('Push vinculado'), findsOneWidget);
  });

  testWidgets('RetaguardaUsersScreen (lista vazia) sem excecao', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const RetaguardaUsersScreen(), [
        authStateProvider.overrideWith((ref) => user),
        retaguardaUsersProvider.overrideWith((ref) async => <RetaguardaUser>[]),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.takeException(),
      isNull,
      reason: 'RetaguardaUsersScreen (vazia) nao deveria lancar',
    );
  });

  testWidgets('RetaguardaUsersScreen (com linhas) sem excecao', (tester) async {
    await tester.pumpWidget(
      _wrap(const RetaguardaUsersScreen(), [
        authStateProvider.overrideWith((ref) => user),
        retaguardaUsersProvider.overrideWith((ref) async => [user]),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.takeException(),
      isNull,
      reason: 'RetaguardaUsersScreen (linhas) nao deveria lancar',
    );
  });

  testWidgets('Dicas da Hope exibe geracao e envio imediato', (tester) async {
    const tipRule = AutomationRule(
      id: 'tip-rule',
      messageType: 'tip',
      enabled: true,
      frequencyDays: 7,
      title: 'Dica da Hope',
      body: 'Revise seus gastos recorrentes.',
    );
    await tester.pumpWidget(
      _wrap(const AutomationRulesScreen(), [
        authStateProvider.overrideWith((ref) => user),
        automationRulesProvider.overrideWith((ref) async => [tipRule]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerar nova dica'), findsOneWidget);
    expect(find.text('Dica personalizada'), findsOneWidget);
    expect(find.text('Enviar agora'), findsOneWidget);
  });

  testWidgets(
    'Notificacoes identifica canais e oferece modalidade no reenvio',
    (tester) async {
      const campaign = PushCampaign(
        id: 'campaign-1',
        title: 'Campanha multicanal',
        body: 'Mensagem de teste',
        category: 'general',
        audience: 'all',
        targetUserIds: [],
        status: 'sent',
        recipientsTotal: 1,
        successTotal: 2,
        failureTotal: 0,
        createdAt: '2026-07-17',
        deliveryMode: 'both',
        pushDelivery: DeliveryChannelStats(total: 1, sent: 1),
        emailDelivery: DeliveryChannelStats(total: 1, sent: 1),
      );
      await tester.pumpWidget(
        _wrap(const NotificationsScreen(), [
          authStateProvider.overrideWith((ref) => user),
          notificationsProvider.overrideWith(
            (ref) async =>
                const PushCampaignPage(campaigns: [campaign], total: 1),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Push + E-mail'), findsOneWidget);
      expect(find.text('Push: 1/1 confirmadas'), findsOneWidget);
      expect(find.text('E-mail: 1/1 confirmadas'), findsOneWidget);
      expect(find.byTooltip('Consultar destinatários'), findsOneWidget);

      await tester.tap(find.byTooltip('Reenviar (nova campanha)'));
      await tester.pumpAndSettle();
      expect(find.text('Ambos'), findsOneWidget);
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('E-mail'), findsOneWidget);
    },
  );
}
