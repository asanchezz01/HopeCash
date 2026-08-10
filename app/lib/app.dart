import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/accounts_screen.dart';
import 'presentation/screens/ai_chat_screen.dart';
import 'presentation/screens/api_tokens_screen.dart';
import 'presentation/screens/budget_screen.dart';
import 'presentation/screens/card_invoices_screen.dart';
import 'presentation/screens/categories_screen.dart';
import 'presentation/screens/credit_cards_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/debts_screen.dart';
import 'presentation/screens/goals_screen.dart';
import 'presentation/screens/import_screen.dart';
import 'presentation/screens/investments_screen.dart';
import 'presentation/screens/login_data_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/more_screen.dart';
import 'presentation/screens/notification_suggestions_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/push_preferences_screen.dart';
import 'presentation/screens/shell_screen.dart';
import 'presentation/screens/transactions_screen.dart';
import 'presentation/screens/unlock_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  // watch: o router é recriado quando o usuário loga/desloga (ou a trava
  // biométrica abre), fazendo o redirect reavaliar e navegar para a tela
  // correta.
  final loggedIn = ref.watch(authStateProvider) != null;
  final locked = ref.watch(appLockedProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final goingToLogin = state.matchedLocation == '/login';
      final goingToUnlock = state.matchedLocation == '/unlock';
      // Sessão salva aguardando biometria: nada além do desbloqueio.
      if (loggedIn && locked) return goingToUnlock ? null : '/unlock';
      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && (goingToLogin || goingToUnlock)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // Confirmação biométrica da sessão salva no aparelho.
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockScreen()),
      // Tutorial em tela cheia, acima da casca de navegação.
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      // Chat com a Hope em tela cheia, acima da casca de navegação.
      GoRoute(path: '/ai-chat', builder: (_, _) => const AiChatScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ShellScreen(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (_, state) => TransactionsScreen(
                  initialSourceKind: state.uri.queryParameters['sourceKind'],
                  initialSourceId: state.uri.queryParameters['sourceId'],
                  initialOpenTransactionId:
                      state.uri.queryParameters['openTransactionId'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accounts',
                builder: (_, _) => const AccountsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'login-data',
                    builder: (_, _) => const LoginDataScreen(),
                  ),
                  GoRoute(
                    path: 'api-tokens',
                    builder: (_, _) => const ApiTokensScreen(),
                  ),
                  GoRoute(
                    path: 'credit-cards',
                    builder: (_, _) => const CreditCardsScreen(),
                    routes: [
                      GoRoute(
                        path: ':cardId',
                        builder: (_, state) => CardInvoicesScreen(
                          cardId: state.pathParameters['cardId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'categories',
                    builder: (_, _) => const CategoriesScreen(),
                  ),
                  GoRoute(
                    path: 'budget',
                    builder: (_, _) => const BudgetScreen(),
                  ),
                  GoRoute(
                    path: 'goals',
                    builder: (_, _) => const GoalsScreen(),
                  ),
                  GoRoute(
                    path: 'debts',
                    builder: (_, _) => const DebtsScreen(),
                  ),
                  GoRoute(
                    path: 'investments',
                    builder: (_, _) => const InvestmentsScreen(),
                  ),
                  GoRoute(
                    path: 'import',
                    builder: (_, state) => ImportScreen(
                      initialCardId: state.uri.queryParameters['cardId'],
                      initialReferenceMonth:
                          state.uri.queryParameters['referenceMonth'],
                      initialDueDate: state.uri.queryParameters['dueDate'],
                    ),
                  ),
                  GoRoute(
                    path: 'notification-suggestions',
                    builder: (_, _) => const NotificationSuggestionsScreen(),
                  ),
                  GoRoute(
                    path: 'push-preferences',
                    builder: (_, _) => const PushPreferencesScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class HopeCashApp extends ConsumerWidget {
  const HopeCashApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Notificação tocada (app em segundo plano/encerrado) → navega assim que
    // houver usuário autenticado E a trava biométrica estiver aberta.
    // Consumir o link só nessa condição faz ele sobreviver ao boot travado:
    // após o desbloqueio o rebuild passa por aqui e entrega a navegação.
    final pendingLink = ref.watch(pendingDeepLinkProvider);
    if (pendingLink != null &&
        ref.watch(authStateProvider) != null &&
        !ref.watch(appLockedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(pendingDeepLinkProvider) != pendingLink) return;
        router.go(pendingLink);
        ref.read(pendingDeepLinkProvider.notifier).state = null;
      });
    }

    return MaterialApp.router(
      title: 'HopeCash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
