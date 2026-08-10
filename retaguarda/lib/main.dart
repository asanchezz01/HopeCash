import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setUrlStrategy(const HashUrlStrategy());
  await initializeDateFormatting('pt_BR');

  final container = ProviderContainer();
  // Restaura a sessão salva (abre direto no painel se já autenticado).
  final user = await container.read(authRepositoryProvider).restoreSession();
  container.read(authStateProvider.notifier).state = user;

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RetaguardaApp(),
    ),
  );
}
