import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/providers.dart';
import 'package:hopecash/core/theme/app_theme.dart';
import 'package:hopecash/data/local/database.dart';
import 'package:hopecash/data/remote/api_client.dart';
import 'package:hopecash/data/sync/sync_service.dart';
import 'package:hopecash/presentation/screens/more_screen.dart';

void main() {
  testWidgets('mantém Hope no menu quando a IA está indisponível', (
    tester,
  ) async {
    final database = AppDatabase.test(NativeDatabase.memory());
    final sync = SyncService(database, ApiClient(dio: Dio()));
    addTearDown(() {
      sync.stop();
      return database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          syncServiceProvider.overrideWithValue(sync),
          pendingCountProvider.overrideWith((ref) => Stream.value(0)),
          notificationSuggestionsCountProvider.overrideWith(
            (ref) => Stream.value(0),
          ),
          aiAvailableProvider.overrideWith((ref) async => false),
          biometricAvailableProvider.overrideWith((ref) async => false),
          biometricLockEnabledProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const MoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('hope-menu-entry')), findsOneWidget);
    expect(find.text('Hope, sua assistente'), findsOneWidget);
    expect(
      find.text('Temporariamente indisponível — toque para tentar'),
      findsOneWidget,
    );
  });
}
