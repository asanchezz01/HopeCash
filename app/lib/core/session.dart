import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/auth_repository.dart';
import 'providers.dart';

/// Liga os serviços que dependem de um usuário autenticado: conta delegada
/// salva, store local, sincronização, push e ingestão de notificações.
///
/// Usado no boot (sessão restaurada sem trava biométrica) e após o
/// desbloqueio — com a trava ativa, nada disso roda antes de a identidade
/// ser confirmada, para nenhum dado ser tocado na tela de bloqueio.
Future<void> startUserSession(
  ProviderContainer container,
  AuthUser user,
) async {
  final acting = await container.read(authRepositoryProvider).restoreActing();
  container.read(actingAccountProvider.notifier).state = acting;
  await container
      .read(financeRepositoryProvider)
      .prepareLocalStoreForUser(acting?.ownerId ?? user.id);
  container.read(syncServiceProvider).start();
  // Reconcilia o token de push (idempotente) — cobre a permissão já
  // concedida antes com registro precisando ser reafirmado/atualizado.
  unawaited(
    container.read(pushNotificationsServiceProvider).ensureRegistered(
      locale: WidgetsBinding.instance.platformDispatcher.locale.toString(),
    ),
  );
  // Notificações bancárias capturadas viram sugestões pendentes (Android).
  unawaited(
    container.read(notificationIngestionServiceProvider).ingestPending(),
  );
}
