import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/ai_health.dart';
import '../data/models/api_version.dart';
import '../data/models/app_user.dart';
import '../data/models/automation_rule.dart';
import '../data/models/push_campaign.dart';
import '../data/models/retaguarda_user.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/app_users_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/automation_rules_repository.dart';
import '../data/repositories/notifications_repository.dart';
import '../data/repositories/retaguarda_users_repository.dart';
import 'config/app_config.dart';

/// Injeção de dependências central (Riverpod) da retaguarda.

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final retaguardaUsersRepositoryProvider = Provider<RetaguardaUsersRepository>(
  (ref) => RetaguardaUsersRepository(ref.watch(apiClientProvider)),
);

final appUsersRepositoryProvider = Provider<AppUsersRepository>(
  (ref) => AppUsersRepository(ref.watch(apiClientProvider)),
);

/// Usuário da retaguarda autenticado (null = tela de login).
final authStateProvider = StateProvider<RetaguardaUser?>((ref) => null);

/// Usuário selecionado no filtro do dashboard (null = todos).
final dashboardUserFilterProvider = StateProvider<String?>((ref) => null);

/// Usuários disponíveis no filtro do dashboard.
final dashboardUsersProvider = FutureProvider<List<AppUser>>(
  (ref) => ref.watch(appUsersRepositoryProvider).listAll(),
);

/// Indicadores do painel inicial.
final statsProvider = FutureProvider<RetaguardaStats>(
  (ref) => ref
      .watch(appUsersRepositoryProvider)
      .stats(userId: ref.watch(dashboardUserFilterProvider)),
);

/// Lista de usuários da retaguarda.
final retaguardaUsersProvider = FutureProvider<List<RetaguardaUser>>(
  (ref) => ref.watch(retaguardaUsersRepositoryProvider).list(),
);

/// Versão publicada do backend (app/API) — rota pública GET /version.
final apiVersionProvider = FutureProvider<ApiVersion>((ref) async {
  final res = await ref.watch(apiClientProvider).dio.get('/version');
  return ApiVersion.fromJson(res.data['data'] as Map<String, dynamic>);
});

/// Estado do servidor de IA (Ollama) — GET /retaguarda/ai/health.
final aiHealthProvider = FutureProvider<AiHealth>((ref) async {
  final res = await ref
      .watch(apiClientProvider)
      .dio
      .get('${AppConfig.retaguardaPrefix}/ai/health');
  return AiHealth.fromJson(res.data['data'] as Map<String, dynamic>);
});

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

/// Filtro de status das campanhas (null = todos).
final notificationsStatusFilterProvider = StateProvider<String?>((ref) => null);

/// Página de campanhas conforme o filtro de status atual.
final notificationsProvider = FutureProvider<PushCampaignPage>((ref) {
  final status = ref.watch(notificationsStatusFilterProvider);
  return ref.watch(notificationsRepositoryProvider).list(status: status);
});

final automationRulesRepositoryProvider = Provider<AutomationRulesRepository>(
  (ref) => AutomationRulesRepository(ref.watch(apiClientProvider)),
);

/// Regras das mensagens push automáticas (avisos de vencimento, insights, dicas).
final automationRulesProvider = FutureProvider<List<AutomationRule>>(
  (ref) => ref.watch(automationRulesRepositoryProvider).list(),
);

/// Filtro de busca dos usuários do app.
final appUsersQueryProvider = StateProvider<String>((ref) => '');

/// Filtro de status dos usuários do app (null = todos).
final appUsersStatusProvider = StateProvider<String?>((ref) => null);

/// Página de usuários do app conforme filtros atuais.
final appUsersProvider = FutureProvider<AppUserPage>((ref) {
  final search = ref.watch(appUsersQueryProvider);
  final status = ref.watch(appUsersStatusProvider);
  return ref
      .watch(appUsersRepositoryProvider)
      .list(search: search, status: status);
});
