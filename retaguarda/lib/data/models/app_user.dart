/// Usuário do aplicativo HopeCash (tabela `users`), visto pela retaguarda.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.locale,
    this.currency,
    this.createdAt,
    this.activeSessions,
    this.hasPushToken = false,
  });

  final String id;
  final String name;
  final String email;
  final String status; // active | blocked | pending_deletion
  final String? locale;
  final String? currency;
  final String? createdAt;
  final int? activeSessions;
  final bool hasPushToken;

  bool get isActive => status == 'active';
  bool get isBlocked => status == 'blocked';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    status: json['status'] as String? ?? 'active',
    locale: json['locale'] as String?,
    currency: json['currency'] as String?,
    createdAt: json['created_at'] as String?,
    activeSessions: (json['active_sessions'] as num?)?.toInt(),
    hasPushToken: json['has_push_token'] == true || json['has_push_token'] == 1,
  );
}

/// Página de resultados de usuários do app.
class AppUserPage {
  const AppUserPage({required this.users, required this.total});

  final List<AppUser> users;
  final int total;
}

/// Indicadores do painel inicial da retaguarda.
class RetaguardaStats {
  const RetaguardaStats({
    required this.appUsersTotal,
    required this.appUsersActive,
    required this.appUsersBlocked,
    required this.retaguardaUsersTotal,
    this.accountsTotal = 0,
    this.creditCardsTotal = 0,
    this.debtsTotal = 0,
    this.budgetsTotal = 0,
    this.incomeTransactionsTotal = 0,
    this.expenseTransactionsTotal = 0,
  });

  final int appUsersTotal;
  final int appUsersActive;
  final int appUsersBlocked;
  final int retaguardaUsersTotal;
  final int accountsTotal;
  final int creditCardsTotal;
  final int debtsTotal;
  final int budgetsTotal;
  final int incomeTransactionsTotal;
  final int expenseTransactionsTotal;

  factory RetaguardaStats.fromJson(Map<String, dynamic> json) =>
      RetaguardaStats(
        appUsersTotal: (json['app_users_total'] as num?)?.toInt() ?? 0,
        appUsersActive: (json['app_users_active'] as num?)?.toInt() ?? 0,
        appUsersBlocked: (json['app_users_blocked'] as num?)?.toInt() ?? 0,
        retaguardaUsersTotal:
            (json['retaguarda_users_total'] as num?)?.toInt() ?? 0,
        accountsTotal: (json['accounts_total'] as num?)?.toInt() ?? 0,
        creditCardsTotal: (json['credit_cards_total'] as num?)?.toInt() ?? 0,
        debtsTotal: (json['debts_total'] as num?)?.toInt() ?? 0,
        budgetsTotal: (json['budgets_total'] as num?)?.toInt() ?? 0,
        incomeTransactionsTotal:
            (json['income_transactions_total'] as num?)?.toInt() ?? 0,
        expenseTransactionsTotal:
            (json['expense_transactions_total'] as num?)?.toInt() ?? 0,
      );
}
