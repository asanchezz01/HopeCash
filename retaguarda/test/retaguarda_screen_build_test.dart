import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash_retaguarda/core/providers.dart';
import 'package:hopecash_retaguarda/core/theme/app_theme.dart';
import 'package:hopecash_retaguarda/data/models/retaguarda_user.dart';
import 'package:hopecash_retaguarda/presentation/screens/retaguarda_users_screen.dart';

void main() {
  testWidgets('RetaguardaUsersScreen constroi sem excecao', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => const RetaguardaUser(
              id: '1', name: 'Admin', email: 'a@a.com',
              role: 'superuser', status: 'active',
            ),
          ),
          retaguardaUsersProvider.overrideWith(
            (ref) async => const [
              RetaguardaUser(
                id: '1', name: 'Admin', email: 'a@a.com',
                role: 'superuser', status: 'active',
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RetaguardaUsersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Equipe da retaguarda'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
