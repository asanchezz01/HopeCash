import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/app_users_screen.dart';
import 'presentation/screens/automation_rules_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/notifications_screen.dart';
import 'presentation/screens/profile_screen.dart';
import 'presentation/screens/retaguarda_users_screen.dart';
import 'presentation/screens/shell_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final loggedIn = ref.watch(authStateProvider) != null;
  return GoRouter(
    redirect: (context, state) {
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn && !goingToLogin) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '/login?from=$from';
      }
      if (loggedIn && goingToLogin) {
        final from = state.uri.queryParameters['from'];
        if (from != null && from.startsWith('/') && !from.startsWith('//')) {
          return from;
        }
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
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
                path: '/app-users',
                builder: (_, _) => const AppUsersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/retaguarda-users',
                builder: (_, _) => const RetaguardaUsersScreen(),
              ),
              GoRoute(
                path: '/retaguarda-users/new',
                builder: (_, _) =>
                    const RetaguardaUsersScreen(openCreateOnLoad: true),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (_, _) => const NotificationsScreen(),
                routes: [
                  GoRoute(
                    path: 'automation',
                    builder: (_, _) => const AutomationRulesScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class RetaguardaApp extends ConsumerWidget {
  const RetaguardaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: 'HopeCash Retaguarda',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
