import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  final container = ProviderContainer();
  // Aplica a preferência visual antes do primeiro frame, evitando que o tema
  // claro apareça por um instante quando o modo escuro estiver salvo.
  await container.read(themeModeProvider.notifier).load();

  // Inicializa o Firebase e os listeners de push antes de tudo, para que uma
  // notificação que abriu o app (app encerrado) já seja capturada aqui.
  final pushService = container.read(pushNotificationsServiceProvider);
  await pushService.initialize(
    onDeepLink: (link) =>
        container.read(pendingDeepLinkProvider.notifier).state = link,
  );

  // Restaura a sessão salva — o login é persistente no aparelho. Com
  // biometria disponível (e a preferência ligada), o app abre travado na
  // tela de desbloqueio e só liga sincronização/push após a confirmação;
  // sem biometria, abre direto no dashboard como antes.
  final user = await container.read(authRepositoryProvider).restoreSession();
  container.read(authStateProvider.notifier).state = user;
  if (user != null) {
    final lockEnabled = await container.read(
      biometricLockEnabledProvider.future,
    );
    final canLock =
        lockEnabled &&
        await container.read(biometricAuthServiceProvider).isAvailable();
    if (canLock) {
      container.read(appLockedProvider.notifier).state = true;
    } else {
      await startUserSession(container, user);
    }
  }

  // Notificações bancárias capturadas viram sugestões pendentes (Android).
  // Processa sempre que o app volta do background; no boot/desbloqueio quem
  // dispara é startUserSession. Nada roda com a trava biométrica fechada.
  Future<void> ingestNotifications() async {
    if (container.read(authStateProvider) == null) return;
    if (container.read(appLockedProvider)) return;
    await container.read(notificationIngestionServiceProvider).ingestPending();
  }

  // Reconcilia o registro do token de push ao retomar o app — cobre o caso de
  // o dispositivo estar sem conexão no momento em que tentamos registrar.
  Future<void> reconcilePush() async {
    if (container.read(authStateProvider) == null) return;
    if (container.read(appLockedProvider)) return;
    await pushService.ensureRegistered(
      locale: WidgetsBinding.instance.platformDispatcher.locale.toString(),
    );
  }

  AppLifecycleListener(
    onResume: () {
      unawaited(ingestNotifications());
      unawaited(reconcilePush());
    },
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const HopeCashApp()),
  );
}
