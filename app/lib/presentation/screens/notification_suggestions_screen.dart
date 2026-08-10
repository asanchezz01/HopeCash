import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../components/hope_components.dart';
import '../widgets/quick_add_sheet.dart';

/// Revisão das sugestões de lançamento geradas a partir de notificações
/// bancárias capturadas no Android. Nada é lançado sem aprovação do usuário.
class NotificationSuggestionsScreen extends ConsumerStatefulWidget {
  const NotificationSuggestionsScreen({super.key});

  @override
  ConsumerState<NotificationSuggestionsScreen> createState() =>
      _NotificationSuggestionsScreenState();
}

class _NotificationSuggestionsScreenState
    extends ConsumerState<NotificationSuggestionsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ingest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou das configurações do Android: reavalia a permissão e busca
    // notificações que o serviço capturou enquanto o app estava fora.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationAccessProvider);
      _ingest();
    }
  }

  Future<void> _ingest() =>
      ref.read(notificationIngestionServiceProvider).ingestPending();

  Future<void> _approve(LocalNotificationSuggestion s) async {
    final repo = ref.read(financeRepositoryProvider);
    final date = s.receivedAt.length >= 10
        ? s.receivedAt.substring(0, 10)
        : todayIso();
    final isCard =
        s.eventType == 'card_purchase' || s.eventType == 'card_refund';

    if (isCard) {
      final cards = ref.read(creditCardsProvider).valueOrNull ?? [];
      final card = cards
          .where((c) => c.id == s.suggestedCardId)
          .firstOrNull;
      if (card == null) {
        // Sem cartão identificado não dá para aprovar direto —
        // abre a edição para o usuário escolher.
        await _edit(s);
        return;
      }
      if (s.eventType == 'card_purchase') {
        await repo.addCardExpense(
          card: card,
          description: s.description,
          totalAmount: s.amount,
          purchaseDate: date,
        );
      } else {
        await repo.addCardCredit(
          card: card,
          description: s.description,
          amount: s.amount,
          date: date,
        );
      }
    } else {
      await repo.addTransaction(
        type: s.transactionType,
        description: s.description,
        amount: s.amount,
        date: date,
        isPaid: true,
        accountId: s.suggestedAccountId,
        categoryId: s.suggestedCategoryId,
      );
    }

    await ref
        .read(notificationSuggestionsRepositoryProvider)
        .setStatus(s.id, 'approved');
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lançamento criado: ${s.description}')),
      );
    }
  }

  Future<void> _edit(LocalNotificationSuggestion s) async {
    final isCard =
        s.eventType == 'card_purchase' || s.eventType == 'card_refund';
    final saved = await showQuickAddSheet(
      context,
      prefill: QuickAddPrefill(
        type: s.transactionType,
        amount: s.amount,
        description: s.description,
        date: s.receivedAt.length >= 10
            ? s.receivedAt.substring(0, 10)
            : todayIso(),
        categoryId: s.suggestedCategoryId,
        accountId: isCard ? null : s.suggestedAccountId,
        cardId: isCard ? s.suggestedCardId : null,
      ),
    );
    if (saved == true) {
      await ref
          .read(notificationSuggestionsRepositoryProvider)
          .setStatus(s.id, 'approved');
    }
  }

  Future<void> _ignore(LocalNotificationSuggestion s) async {
    await ref
        .read(notificationSuggestionsRepositoryProvider)
        .setStatus(s.id, 'ignored');
  }

  Future<void> _cleanUp() async {
    final removed = await ref
        .read(notificationSuggestionsRepositoryProvider)
        .cleanUp();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed > 0
                ? '$removed sugestões antigas/ignoradas apagadas'
                : 'Nada para limpar',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final capture = ref.watch(notificationCaptureProvider);
    final access = ref.watch(notificationAccessProvider);
    final suggestions = ref.watch(notificationSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestões de notificações'),
        actions: [
          IconButton(
            tooltip: 'Apagar ignoradas e antigas',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _cleanUp,
          ),
        ],
      ),
      body: !capture.isSupported
          ? const PremiumEmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'Indisponível nesta plataforma',
              subtitle:
                  'A leitura de notificações bancárias está disponível '
                  'apenas no aplicativo Android.',
            )
          : RefreshIndicator(
              onRefresh: _ingest,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _PermissionCard(
                    granted: access.valueOrNull ?? false,
                    onOpenSettings: () async {
                      await capture.openSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  const _PrivacyCard(),
                  const SizedBox(height: HopeSpacing.sm),
                  const SectionTitle(title: 'Pendentes de revisão'),
                  ...switch (suggestions) {
                    AsyncData(:final value) when value.isEmpty => [
                      const PremiumEmptyState(
                        icon: Icons.mark_email_read_outlined,
                        title: 'Nenhuma sugestão pendente',
                        subtitle:
                            'Quando chegar uma notificação do seu banco '
                            'com débito ou crédito, ela aparece aqui para '
                            'você revisar e aprovar.',
                      ),
                    ],
                    AsyncData(:final value) => [
                      for (final s in value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SuggestionCard(
                            suggestion: s,
                            onApprove: () => _approve(s),
                            onEdit: () => _edit(s),
                            onIgnore: () => _ignore(s),
                          ),
                        ),
                    ],
                    _ => [const HopeSkeleton(rows: 3)],
                  },
                ],
              ),
            ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.granted, required this.onOpenSettings});

  final bool granted;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FinanceIconBadge(
                icon: granted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_paused_outlined,
                color: granted
                    ? context.hopeColors.success
                    : context.hopeColors.warning,
              ),
              const SizedBox(width: HopeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      granted ? 'Leitura ativa' : 'Leitura desativada',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      granted
                          ? 'O HopeCash está lendo notificações dos seus '
                                'apps de banco para sugerir lançamentos.'
                          : 'Conceda o acesso às notificações para o '
                                'HopeCash sugerir lançamentos automaticamente.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: granted
                ? TextButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Gerenciar/desativar'),
                  )
                : FilledButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.lock_open_outlined, size: 18),
                    label: const Text('Ativar acesso'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      color: context.hopeColors.infoSurface,
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: HopeSpacing.sm),
          Expanded(
            child: Text(
              'Tudo é processado no seu aparelho: o texto das notificações '
              'não é enviado a servidores. Nada vira lançamento sem a sua '
              'aprovação.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onApprove,
    required this.onEdit,
    required this.onIgnore,
  });

  final LocalNotificationSuggestion suggestion;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onIgnore;

  String get _eventLabel => switch (suggestion.eventType) {
    'card_purchase' => 'Compra no cartão',
    'card_refund' => 'Estorno no cartão',
    'account_credit' => 'Crédito em conta',
    _ => 'Débito em conta',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = suggestion;
    final isIncome = s.transactionType == 'income';
    final color = isIncome
        ? context.hopeColors.income
        : context.hopeColors.expense;
    final isCard =
        s.eventType == 'card_purchase' || s.eventType == 'card_refund';

    String? sourceName;
    if (isCard && s.suggestedCardId != null) {
      final cards = ref.watch(creditCardsProvider).valueOrNull ?? [];
      sourceName = cards.where((c) => c.id == s.suggestedCardId).firstOrNull?.name;
    } else if (s.suggestedAccountId != null) {
      final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
      sourceName =
          accounts.where((a) => a.id == s.suggestedAccountId).firstOrNull?.name;
    }

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FinanceIconBadge(
                icon: isCard
                    ? Icons.credit_card_outlined
                    : isIncome
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: color,
              ),
              const SizedBox(width: HopeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        s.sourceAppName.isEmpty
                            ? s.sourcePackage
                            : s.sourceAppName,
                        formatDate(s.receivedAt),
                        ?sourceName,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HopeSpacing.xs),
              Text(
                '${isIncome ? '+' : '-'}${formatMoney(s.amount)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.sm),
          Wrap(
            spacing: HopeSpacing.xs,
            runSpacing: HopeSpacing.xs,
            children: [
              MetricPill(label: _eventLabel, value: '', color: color),
              MetricPill(
                label: 'Confiança',
                value: '${(s.confidence * 100).round()}%',
                color: s.confidence >= 0.7
                    ? context.hopeColors.success
                    : context.hopeColors.warning,
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onIgnore,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('Ignorar'),
              ),
              const SizedBox(width: HopeSpacing.xs),
              OutlinedButton(onPressed: onEdit, child: const Text('Editar')),
              const SizedBox(width: HopeSpacing.xs),
              FilledButton(
                onPressed: onApprove,
                child: const Text('Aprovar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
