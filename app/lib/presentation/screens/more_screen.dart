import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../components/hope_components.dart';
import '../widgets/brand_logo.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;
    final sync = ref.watch(syncServiceProvider);
    final suggestionCount =
        ref.watch(notificationSuggestionsCountProvider).valueOrNull ?? 0;
    final acting = ref.watch(actingAccountProvider);
    final hopeAvailability = ref.watch(aiAvailableProvider);
    final hopeAvailable = hopeAvailability.valueOrNull;
    final biometricAvailable =
        ref.watch(biometricAvailableProvider).valueOrNull ?? false;
    final biometricEnabled =
        ref.watch(biometricLockEnabledProvider).valueOrNull ?? true;
    final themeMode = ref.watch(themeModeProvider);
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final darkModeEnabled =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && systemIsDark);
    final colors = context.hopeColors;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          context.pagePadding,
          HopeSpacing.xs,
          context.pagePadding,
          96,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileCard(
                    name: user?.name ?? '',
                    email: user?.email ?? '',
                  ),
                  if (acting != null) ...[
                    const SizedBox(height: HopeSpacing.sm),
                    _DelegatedAccountBanner(
                      ownerName: acting.ownerName,
                      readOnly: acting.readOnly,
                      onReturn: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(authRepositoryProvider).actAsSelf();
                        ref.read(actingAccountProvider.notifier).state = null;
                        if (user != null) {
                          await ref
                              .read(financeRepositoryProvider)
                              .prepareLocalStoreForUser(user.id);
                        }
                        ref.read(syncServiceProvider).syncNow();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('De volta à sua conta')),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: HopeSpacing.sm),
                  ValueListenableBuilder(
                    valueListenable: sync.syncing,
                    builder: (context, syncing, _) => _SyncCard(
                      syncing: syncing,
                      pending: pending,
                      onSync: syncing ? null : sync.syncNow,
                    ),
                  ),

                  const SectionEyebrow('Principal'),
                  _MoreGroup(
                    rows: [
                      _MoreRow(
                        key: const ValueKey('hope-menu-entry'),
                        icon: Icons.auto_awesome_outlined,
                        color: hopeAvailable == false
                            ? colors.warning
                            : colors.card,
                        title: 'Hope, sua assistente',
                        subtitle:
                            hopeAvailability.isLoading &&
                                !hopeAvailability.hasValue
                            ? 'Verificando disponibilidade…'
                            : hopeAvailable == false
                            ? 'Temporariamente indisponível — toque para tentar'
                            : 'Pergunte sobre gastos e peça lançamentos',
                        onTap: () => context.push('/ai-chat'),
                      ),
                      _MoreRow(
                        icon: Icons.receipt_long_outlined,
                        color: scheme.primary,
                        title: 'Lançamentos',
                        subtitle: 'Receitas, despesas e transferências',
                        onTap: () => context.go('/transactions'),
                      ),
                      _MoreRow(
                        icon: Icons.account_balance_outlined,
                        color: colors.investment,
                        title: 'Contas',
                        subtitle: 'Saldos, contas bancárias e carteiras',
                        onTap: () => context.go('/accounts'),
                      ),
                      _MoreRow(
                        icon: Icons.credit_card_outlined,
                        color: colors.card,
                        title: 'Cartões de crédito',
                        subtitle: 'Cadastro, limite e vencimento',
                        onTap: () => context.push('/more/credit-cards'),
                      ),
                    ],
                  ),

                  const SectionEyebrow('Planejamento'),
                  _MoreGroup(
                    rows: [
                      _MoreRow(
                        icon: Icons.pie_chart_outline,
                        color: colors.success,
                        title: 'Orçamento mensal',
                        subtitle: 'Previsto × realizado por categoria',
                        onTap: () => context.push('/more/budget'),
                      ),
                      _MoreRow(
                        icon: Icons.flag_outlined,
                        color: colors.investment,
                        title: 'Metas financeiras',
                        subtitle: 'Objetivos, progresso e aporte mensal',
                        onTap: () => context.push('/more/goals'),
                      ),
                      _MoreRow(
                        icon: Icons.trending_down_outlined,
                        color: colors.warning,
                        title: 'Dívidas e financiamentos',
                        subtitle: 'Saldo devedor e parcelas',
                        onTap: () => context.push('/more/debts'),
                      ),
                      _MoreRow(
                        icon: Icons.show_chart_outlined,
                        color: colors.card,
                        title: 'Investimentos',
                        subtitle: 'Carteira e rentabilidade',
                        onTap: () => context.push('/more/investments'),
                      ),
                    ],
                  ),

                  const SectionEyebrow('Organização'),
                  _MoreGroup(
                    rows: [
                      _MoreRow(
                        icon: Icons.category_outlined,
                        color: scheme.primary,
                        title: 'Categorias',
                        subtitle: 'Receitas, despesas e subcategorias',
                        onTap: () => context.push('/more/categories'),
                      ),
                      _MoreRow(
                        icon: Icons.upload_file_outlined,
                        color: scheme.primary,
                        title: 'Importar extrato',
                        subtitle: 'Traga lançamentos do banco em CSV ou OFX',
                        onTap: () => context.push('/more/import'),
                      ),
                      _MoreRow(
                        icon: Icons.notifications_outlined,
                        color: scheme.primary,
                        title: 'Notificações bancárias',
                        subtitle: suggestionCount > 0
                            ? 'Sugestões de lançamento do seu banco'
                            : 'Sugestões de lançamento a partir do seu banco',
                        badgeCount: suggestionCount,
                        onTap: () =>
                            context.push('/more/notification-suggestions'),
                      ),
                    ],
                  ),

                  const SectionEyebrow('Preferências'),
                  _MoreGroup(
                    rows: [
                      _MoreRow(
                        icon: darkModeEnabled
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        color: colors.investment,
                        title: 'Modo escuro',
                        subtitle: darkModeEnabled ? 'Ativado' : 'Desativado',
                        toggled: darkModeEnabled,
                        onToggle: (enabled) => ref
                            .read(themeModeProvider.notifier)
                            .setDarkMode(enabled),
                      ),
                      // Só aparece com biometria cadastrada no aparelho — sem
                      // sensor, o app abre direto e a preferência não teria
                      // efeito.
                      if (biometricAvailable)
                        _MoreRow(
                          icon: Icons.fingerprint,
                          color: colors.success,
                          title: 'Biometria ao abrir',
                          subtitle: biometricEnabled
                              ? 'Pede digital ou rosto para entrar'
                              : 'Entra direto, sem confirmação',
                          toggled: biometricEnabled,
                          onToggle: (enabled) =>
                              _setBiometricLock(ref, enabled),
                        ),
                      _MoreRow(
                        icon: Icons.notifications_active_outlined,
                        color: colors.card,
                        title: 'Notificações',
                        subtitle: 'Vencimentos, insights e dicas da Hope',
                        onTap: () => context.push('/more/push-preferences'),
                      ),
                      _MoreRow(
                        icon: Icons.manage_accounts_outlined,
                        color: colors.success,
                        title: 'Meu perfil',
                        subtitle: 'Nome, e-mail, senha e acesso compartilhado',
                        onTap: () => context.push('/more/login-data'),
                      ),
                      _MoreRow(
                        icon: Icons.hub_outlined,
                        color: colors.investment,
                        title: 'Apps conectados',
                        subtitle:
                            'Agentes de IA com acesso à sua conta (ChatGPT, Claude e outros)',
                        onTap: () => context.push('/more/api-tokens'),
                      ),
                      _MoreRow(
                        icon: Icons.groups_outlined,
                        color: scheme.onSurfaceVariant,
                        title: 'Família e permissões',
                        subtitle: 'Chega na próxima etapa do app',
                        enabled: false,
                        onTap: () => showHopeSnack(
                          context,
                          'Família e permissões chega na próxima etapa do app.',
                        ),
                      ),
                    ],
                  ),

                  const SectionEyebrow('Ajuda e conta'),
                  _MoreGroup(
                    rows: [
                      _MoreRow(
                        icon: Icons.auto_stories_outlined,
                        color: colors.investment,
                        title: 'Tutorial do HopeCash',
                        subtitle: 'Reveja o passo a passo de boas-vindas',
                        onTap: () => context.push('/onboarding'),
                      ),
                      _MoreRow(
                        icon: Icons.logout_rounded,
                        color: colors.expense,
                        title: 'Sair',
                        subtitle: 'Encerrar sessão neste dispositivo',
                        showChevron: false,
                        destructive: true,
                        onTap: () => _confirmLogout(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sair da conta?'),
      content: const Text(
        'Alterações pendentes serão sincronizadas no próximo login.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sair'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  ref.read(syncServiceProvider).stop();
  // Antes de limpar a sessão: o backend precisa do token de acesso ainda
  // válido para desativar o dispositivo.
  await ref.read(pushNotificationsServiceProvider).deactivateCurrentDevice();
  await ref.read(authRepositoryProvider).logout();
  ref.read(authStateProvider.notifier).state = null;
}

Future<void> _setBiometricLock(WidgetRef ref, bool enabled) async {
  await ref
      .read(databaseProvider)
      .setStateValue(biometricLockStateKey, enabled ? '1' : '0');
  ref.invalidate(biometricLockEnabledProvider);
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final colors = context.hopeColors;
    return Container(
      padding: const EdgeInsets.all(HopeSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HopeRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.heroStart, colors.heroEnd],
        ),
      ),
      child: Row(
        children: [
          const HopeCashLogo(compact: true, iconSize: 42),
          const SizedBox(width: HopeSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.heroOnSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.heroOnSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DelegatedAccountBanner extends StatelessWidget {
  const _DelegatedAccountBanner({
    required this.ownerName,
    required this.readOnly,
    required this.onReturn,
  });

  final String ownerName;
  final bool readOnly;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final colors = context.hopeColors;
    return AppSurface(
      borderColor: colors.warning.withValues(alpha: 0.45),
      child: Row(
        children: [
          FinanceIconBadge(
            icon: Icons.supervisor_account_outlined,
            color: colors.warning,
          ),
          const SizedBox(width: HopeSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Você está na conta de $ownerName',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  readOnly ? 'Acesso somente leitura' : 'Acesso total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onReturn, child: const Text('Voltar')),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.syncing,
    required this.pending,
    required this.onSync,
  });

  final bool syncing;
  final int pending;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final colors = context.hopeColors;
    return AppSurface(
      child: Row(
        children: [
          if (syncing)
            const SizedBox.square(
              dimension: 40,
              child: Padding(
                padding: EdgeInsets.all(HopeSpacing.xs),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            FinanceIconBadge(
              icon: pending > 0
                  ? Icons.cloud_upload_outlined
                  : Icons.cloud_done_outlined,
              color: pending > 0 ? colors.warning : colors.success,
            ),
          const SizedBox(width: HopeSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sincronização',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  syncing
                      ? 'Enviando alterações'
                      : pending > 0
                      ? '$pending ${pending == 1 ? 'alteração pendente' : 'alterações pendentes'}'
                      : 'Tudo sincronizado',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onSync, child: const Text('Sincronizar')),
        ],
      ),
    );
  }
}

/// Bloco de linhas relacionadas dentro de um único cartão.
///
/// Antes cada item era um cartão elevado próprio: quinze sombras empilhadas
/// numa tela só. Agrupar mantém a leitura e devolve o silêncio à página.
class _MoreGroup extends StatelessWidget {
  const _MoreGroup({required this.rows});

  final List<_MoreRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: HopeSpacing.md + 40 + HopeSpacing.sm,
                color: context.hopeColors.softBorder,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.showChevron = true,
    this.destructive = false,
    this.enabled = true,
    this.badgeCount = 0,
    this.toggled,
    this.onToggle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;
  final bool enabled;
  final int badgeCount;

  /// Preenchido quando a linha é um interruptor em vez de um destino.
  final bool? toggled;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSwitch = toggled != null && onToggle != null;
    final titleColor = destructive
        ? theme.colorScheme.error
        : enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: !isSwitch,
      toggled: isSwitch ? toggled : null,
      label: title,
      hint: subtitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSwitch ? () => onToggle!(!toggled!) : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: HopeSpacing.md,
              vertical: HopeSpacing.sm,
            ),
            child: Row(
              children: [
                FinanceIconBadge(icon: icon, color: color),
                const SizedBox(width: HopeSpacing.sm),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: HopeSpacing.xs),
                  _CountBadge(count: badgeCount),
                ],
                if (isSwitch)
                  ExcludeSemantics(
                    child: Switch(value: toggled!, onChanged: onToggle),
                  )
                else if (showChevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(HopeRadius.pill),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
        semanticsLabel: '$count aguardando revisão',
      ),
    );
  }
}
