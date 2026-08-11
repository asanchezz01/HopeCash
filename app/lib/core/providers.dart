import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/database.dart';
import '../data/models/push_preferences.dart';
import '../data/remote/ai_api.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/finance_repository.dart';
import '../data/repositories/notification_suggestions_repository.dart';
import '../data/repositories/pat_repository.dart';
import '../data/repositories/push_notifications_repository.dart';
import '../data/services/notification_ingestion_service.dart';
import '../data/sync/sync_service.dart';
import 'platform/notification_capture.dart';
import 'services/biometric_auth_service.dart';
import 'services/push_notifications_service.dart';

/// Injeção de dependências central (Riverpod).

const _themeModeStateKey = 'theme_mode';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) {
    return ThemeModeController(ref.watch(databaseProvider));
  },
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._database) : super(ThemeMode.system);

  final AppDatabase _database;

  Future<void> load() async {
    final savedMode = await _database.stateValue(_themeModeStateKey);
    state = switch (savedMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  Future<void> setDarkMode(bool enabled) async {
    state = enabled ? ThemeMode.dark : ThemeMode.light;
    await _database.setStateValue(
      _themeModeStateKey,
      enabled ? 'dark' : 'light',
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final aiApiProvider = Provider<AiApi>(
  (ref) => AiApi(ref.watch(apiClientProvider)),
);

/// A IA (Hope) está disponível neste momento?
///
/// Este estado informa a UI, mas nunca controla se a Hope existe na navegação:
/// uma falha transitória de rede, autenticação ou do Ollama não pode remover a
/// assistente do app. O status se reavalia sozinho e também pode ser invalidado
/// manualmente pela tela do chat.
final aiAvailableProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(authStateProvider) == null) return false;
  final ok = await ref.watch(aiApiProvider).health();
  final timer = Timer(
    Duration(minutes: ok ? 10 : 1),
    () => ref.invalidateSelf(),
  );
  ref.onDispose(timer.cancel);
  return ok;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final patRepositoryProvider = Provider<PatRepository>(
  (ref) => PatRepository(ref.watch(apiClientProvider)),
);

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(databaseProvider)),
);

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
  );
  ref.onDispose(service.stop);
  return service;
});

/// Usuário autenticado (null = tela de login). Carregado do storage no boot.
final authStateProvider = StateProvider<AuthUser?>((ref) => null);

// ---------------- Trava biométrica (login persistente) ----------------

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
  (ref) => BiometricAuthService(),
);

/// Chave da preferência (por aparelho) da trava biométrica.
const biometricLockStateKey = 'biometric_lock_enabled';

/// Trava biométrica ligada? Padrão: ligada — quem tem biometria disponível
/// passa a confirmar a identidade ao abrir o app com sessão salva.
final biometricLockEnabledProvider = FutureProvider<bool>((ref) async {
  final value = await ref
      .watch(databaseProvider)
      .stateValue(biometricLockStateKey);
  return value != '0';
});

/// Biometria utilizável neste aparelho (controla a exibição da preferência).
final biometricAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricAuthServiceProvider).isAvailable(),
);

/// Sessão restaurada aguardando confirmação biométrica: enquanto true, o
/// router prende a navegação na tela de desbloqueio e a sincronização nem
/// sequer inicia.
final appLockedProvider = StateProvider<bool>((ref) => false);

// ---------------- Notificações push (Firebase Cloud Messaging) ----------------

final pushNotificationsRepositoryProvider =
    Provider<PushNotificationsRepository>(
      (ref) => PushNotificationsRepository(ref.watch(apiClientProvider)),
    );

/// Serviço único do app para o ciclo de vida do FCM — inicializado uma vez em
/// main.dart. Instância única por processo (Provider simples, sem `watch` de
/// estado externo) para não recriar listeners a cada rebuild.
final pushNotificationsServiceProvider = Provider<PushNotificationsService>((
  ref,
) {
  final service = PushNotificationsService(
    ref.watch(pushNotificationsRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Deep link pendente de uma notificação tocada — a UI (HopeCashApp) observa
/// e navega assim que houver uma rota autenticada disponível.
final pendingDeepLinkProvider = StateProvider<String?>((ref) => null);

final pushPreferencesProvider = FutureProvider<PushPreferences>(
  (ref) => ref.watch(pushNotificationsRepositoryProvider).getPreferences(),
);

/// Conta delegada em visualização (null = a própria conta do usuário).
/// Quando definida, o app opera sobre os dados do titular via token delegado.
final actingAccountProvider = StateProvider<DelegatedAccount?>((ref) => null);

/// O usuário atual já viu (concluiu ou pulou) o tutorial de boas-vindas?
/// A fonte da verdade é o servidor (a marca vale por usuário, em qualquer
/// aparelho); o banco local é cache — evita repetir a consulta e responde
/// offline. true quando não há usuário logado, para nunca abrir fora de
/// sessão.
final onboardingSeenProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider);
  if (user == null) return true;
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(authRepositoryProvider);
  final cacheKey = 'onboarding_completed_${user.id}';
  if (await db.stateValue(cacheKey) == '1') return true;
  final seen = await repo.fetchOnboardingSeen();
  if (seen == true) await db.setStateValue(cacheKey, '1');
  return seen ?? false;
});

/// Mês em exibição (período fechado) no dashboard e na lista de lançamentos.
/// Sempre o primeiro dia do mês; padrão = mês atual.
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// Streams reativas do banco local — a UI nunca espera a rede.
final accountsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchAccounts(),
);

final categoriesProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchCategories(),
);

final subcategoriesProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchSubcategories(),
);

final subcategoriesByCategoryProvider = StreamProvider.family(
  (ref, String categoryId) => ref
      .watch(financeRepositoryProvider)
      .watchSubcategories(categoryId: categoryId),
);

final transactionsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchTransactions(),
);

final creditCardsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchCreditCards(),
);

final goalsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchGoals(),
);

final goalMovementsProvider = StreamProvider.family(
  (ref, String goalId) =>
      ref.watch(financeRepositoryProvider).watchGoalMovements(goalId),
);

final debtsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchDebts(),
);

final debtPaymentsProvider = StreamProvider.family(
  (ref, String debtId) =>
      ref.watch(financeRepositoryProvider).watchDebtPayments(debtId),
);

final investmentsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchInvestments(),
);

final investmentMovementsProvider = StreamProvider.family(
  (ref, String investmentId) => ref
      .watch(financeRepositoryProvider)
      .watchInvestmentMovements(investmentId),
);

/// Todas as movimentações de investimentos — usado no gráfico de evolução
/// do patrimônio (últimos 6 meses) da tela de investimentos.
final allInvestmentMovementsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchAllInvestmentMovements(),
);

/// Orçamento do mês (parâmetro: YYYY-MM-01).
final budgetForMonthProvider = StreamProvider.family(
  (ref, String month) =>
      ref.watch(financeRepositoryProvider).watchBudgetForMonth(month),
);

final budgetItemsProvider = StreamProvider.family(
  (ref, String budgetId) =>
      ref.watch(financeRepositoryProvider).watchBudgetItems(budgetId),
);

/// Todos os itens de orçamento — usado só para invalidar o dashboard quando
/// uma previsão (que compõe o saldo futuro das contas) muda.
final allBudgetItemsProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchAllBudgetItems(),
);

/// Gastos por categoria no mês (parâmetro: YYYY-MM), reativo às transações.
final monthSpendingProvider =
    FutureProvider.family<Map<String, double>, String>((ref, month) {
      ref.watch(transactionsProvider); // invalida quando o banco local muda
      return ref
          .watch(financeRepositoryProvider)
          .spentByCategoryForMonth(month);
    });

/// Realizado por categoria/subcategoria no mês (parâmetro: YYYY-MM),
/// receitas e despesas. Chaves: categoryId e 'categoryId|subcategoryId'.
final monthRealizedProvider =
    FutureProvider.family<Map<String, double>, String>((ref, month) {
      ref.watch(transactionsProvider); // invalida quando o banco local muda
      return ref
          .watch(financeRepositoryProvider)
          .realizedByCategoryForMonth(month);
    });

/// Realizado distribuído entre os itens de um orçamento. A conta ou cartão
/// vinculado ao item participa da correspondência, permitindo repetir uma
/// categoria em meios de pagamento diferentes sem duplicar valores.
final budgetItemRealizedProvider =
    FutureProvider.family<
      Map<String, double>,
      ({String month, String budgetId})
    >((ref, query) {
      ref.watch(transactionsProvider);
      ref.watch(budgetItemsProvider(query.budgetId));
      return ref
          .watch(financeRepositoryProvider)
          .realizedByBudgetItemForMonth(query.month, query.budgetId);
    });

final pendingCountProvider = StreamProvider(
  (ref) => ref.watch(financeRepositoryProvider).watchPendingCount(),
);

// ---------------- Notificações bancárias (Android) ----------------

final notificationCaptureProvider = Provider<NotificationCapture>(
  (ref) => NotificationCapture(),
);

final notificationSuggestionsRepositoryProvider =
    Provider<NotificationSuggestionsRepository>(
      (ref) => NotificationSuggestionsRepository(ref.watch(databaseProvider)),
    );

final notificationIngestionServiceProvider =
    Provider<NotificationIngestionService>(
      (ref) => NotificationIngestionService(
        ref.watch(databaseProvider),
        ref.watch(notificationCaptureProvider),
        ref.watch(notificationSuggestionsRepositoryProvider),
      ),
    );

/// Acesso a notificações concedido? (sempre false fora do Android).
/// Invalide após voltar das configurações do sistema.
final notificationAccessProvider = FutureProvider<bool>(
  (ref) => ref.watch(notificationCaptureProvider).isPermissionGranted(),
);

/// Sugestões pendentes de revisão vindas de notificações bancárias.
final notificationSuggestionsProvider = StreamProvider(
  (ref) => ref.watch(notificationSuggestionsRepositoryProvider).watchPending(),
);

final notificationSuggestionsCountProvider = StreamProvider(
  (ref) =>
      ref.watch(notificationSuggestionsRepositoryProvider).watchPendingCount(),
);

/// Entradas do filtro "previstos" (orçamentos + transações avulsas) para o
/// mês YYYY-MM. Recalcula quando transações ou itens de orçamento mudam.
final plannedEntriesProvider =
    FutureProvider.family<List<PlannedEntry>, String>((ref, month) {
      ref.watch(transactionsProvider);
      ref.watch(allBudgetItemsProvider);
      ref.watch(categoriesProvider);
      ref.watch(subcategoriesProvider);
      ref.watch(accountsProvider);
      ref.watch(creditCardsProvider);
      ref.watch(debtsProvider);
      return ref.watch(financeRepositoryProvider).plannedEntriesForMonth(month);
    });

/// Indicadores do dashboard, recalculados a cada mudança nas transações e no
/// mês selecionado (fluxo e categorias respeitam o período em exibição).
final dashboardProvider = FutureProvider<DashboardSummary>((ref) async {
  ref.watch(transactionsProvider); // invalida quando o banco local muda
  ref.watch(accountsProvider);
  ref.watch(creditCardsProvider);
  ref.watch(categoriesProvider);
  ref.watch(subcategoriesProvider);
  ref.watch(debtsProvider);
  ref.watch(allBudgetItemsProvider); // previsões compõem o saldo futuro
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(financeRepositoryProvider).dashboardSummary(forMonth: month);
});

/// Janela móvel de seis meses usada pelo card de fluxo de caixa.
///
/// [endMonth] representa o último mês visível; a tela impede que ele avance
/// além do mês corrente.
final cashFlowWindowProvider =
    FutureProvider.family<List<CashFlowMonthPoint>, DateTime>((ref, endMonth) {
      ref.watch(transactionsProvider);
      return ref
          .watch(financeRepositoryProvider)
          .cashFlowForWindow(endMonth, months: 6);
    });
