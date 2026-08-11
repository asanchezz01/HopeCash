import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/voice_add_sheet.dart';

/// Casca com navegação adaptativa e ações de lançamento integradas.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  StatefulNavigationShell get shell => widget.shell;

  bool _railExtended = false;

  @override
  void initState() {
    super.initState();
    // Primeiro acesso deste usuário (em qualquer aparelho)? Abre o tutorial
    // uma vez — a marca de visto vem do servidor, com cache local.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  Future<void> _maybeShowOnboarding() async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    // Em conta delegada o foco é visualizar os dados do titular.
    if (ref.read(actingAccountProvider) != null) return;
    final seen = await ref.read(onboardingSeenProvider.future);
    if (!seen && mounted) context.push('/onboarding');
  }

  Future<void> _voiceAdd(BuildContext context) async {
    final prefill = await showVoiceAddSheet(context);
    if (prefill != null && context.mounted) {
      await showQuickAddSheet(context, prefill: prefill);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showRail = width >= HopeBreakpoints.tablet;
    // Conta compartilhada somente leitura: sem botões de lançamento.
    final readOnly = ref.watch(actingAccountProvider)?.readOnly ?? false;

    if (showRail) {
      return Scaffold(
        body: Row(
          children: [
            _AdaptiveRail(
              shell: shell,
              readOnly: readOnly,
              extended: _railExtended,
              onToggleExtended: () =>
                  setState(() => _railExtended = !_railExtended),
              onVoice: () => _voiceAdd(context),
              onQuick: () => showQuickAddSheet(context),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: HopeMotion.normal,
                switchInCurve: HopeMotion.standard,
                switchOutCurve: HopeMotion.standard,
                child: shell,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: AnimatedSwitcher(
        duration: context.motion(HopeMotion.normal),
        switchInCurve: HopeMotion.standard,
        switchOutCurve: HopeMotion.standard,
        child: shell,
      ),
      // Lançar é ação, não destino: sai da barra de navegação (que agora leva
      // às quatro seções reais) e vira botão flutuante, com a voz como ação
      // secundária logo acima.
      floatingActionButton: readOnly
          ? null
          : _QuickActionCluster(
              onVoice: () => _voiceAdd(context),
              onQuick: () => showQuickAddSheet(context),
            ),
      bottomNavigationBar: _BottomNav(shell: shell),
    );
  }
}

class _QuickActionCluster extends StatelessWidget {
  const _QuickActionCluster({required this.onVoice, required this.onQuick});

  final VoidCallback onVoice;
  final VoidCallback onQuick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'hope-voice-fab',
          tooltip: 'Lançar por voz',
          onPressed: onVoice,
          elevation: 1,
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurfaceVariant,
          shape: CircleBorder(
            side: BorderSide(color: context.hopeColors.softBorder),
          ),
          child: const Icon(Icons.mic_none_rounded),
        ),
        const SizedBox(height: HopeSpacing.sm),
        FloatingActionButton(
          heroTag: 'hope-quick-fab',
          tooltip: 'Novo lançamento',
          onPressed: onQuick,
          child: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _AdaptiveRail extends ConsumerWidget {
  const _AdaptiveRail({
    required this.shell,
    required this.readOnly,
    required this.extended,
    required this.onToggleExtended,
    required this.onVoice,
    required this.onQuick,
  });

  final StatefulNavigationShell shell;
  final bool readOnly;
  final bool extended;
  final VoidCallback onToggleExtended;
  final VoidCallback onVoice;
  final VoidCallback onQuick;

  static const _collapsedWidth = 88.0;
  static const _expandedWidth = 288.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    const destinations = _desktopRailDestinations;
    final themeMode = ref.watch(themeModeProvider);
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final darkModeEnabled =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && systemIsDark);
    final selectedIndex = _selectedRailIndex(location, destinations);
    final colorScheme = Theme.of(context).colorScheme;

    void navigateTo(_DesktopRailDestination destination) {
      if (destination.branchIndex != null) {
        shell.goBranch(
          destination.branchIndex!,
          initialLocation: destination.branchIndex == shell.currentIndex,
        );
        return;
      }
      context.go(destination.path);
    }

    final navigationItems = <Widget>[];
    String? currentSection;
    for (var index = 0; index < destinations.length; index++) {
      final destination = destinations[index];
      if (destination.section != currentSection) {
        if (navigationItems.isNotEmpty) {
          navigationItems.add(const SizedBox(height: HopeSpacing.sm));
        }
        navigationItems.add(
          _SidebarSectionLabel(label: destination.section, extended: extended),
        );
        currentSection = destination.section;
      }
      navigationItems.add(
        _SidebarNavItem(
          destination: destination,
          selected: index == selectedIndex,
          extended: extended,
          onTap: () => navigateTo(destination),
        ),
      );
    }

    return AnimatedContainer(
      duration: HopeMotion.normal,
      curve: HopeMotion.emphasized,
      width: extended ? _expandedWidth : _collapsedWidth,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: extended ? _expandedWidth : _collapsedWidth,
          maxWidth: extended ? _expandedWidth : _collapsedWidth,
          child: SafeArea(
            child: Column(
              children: [
                _SidebarHeader(
                  extended: extended,
                  onToggleExtended: onToggleExtended,
                ),
                if (!readOnly)
                  _SidebarQuickActions(
                    extended: extended,
                    onQuick: onQuick,
                    onVoice: onVoice,
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    HopeSpacing.md,
                    readOnly ? HopeSpacing.sm : HopeSpacing.md,
                    HopeSpacing.md,
                    HopeSpacing.xs,
                  ),
                  child: Divider(color: colorScheme.outlineVariant),
                ),
                Expanded(
                  child: Scrollbar(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        HopeSpacing.sm,
                        HopeSpacing.xs,
                        HopeSpacing.sm,
                        HopeSpacing.md,
                      ),
                      children: navigationItems,
                    ),
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                _SidebarUtilities(
                  extended: extended,
                  darkModeEnabled: darkModeEnabled,
                  onToggleTheme: () => ref
                      .read(themeModeProvider.notifier)
                      .setDarkMode(!darkModeEnabled),
                  onLogout: () => _confirmLogout(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.extended,
    required this.onToggleExtended,
  });

  final bool extended;
  final VoidCallback onToggleExtended;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HopeRadius.sm),
      ),
      child: Icon(Icons.auto_graph_rounded, color: colorScheme.primary),
    );

    return SizedBox(
      height: extended ? 78 : 132,
      child: Padding(
        padding: const EdgeInsets.all(HopeSpacing.md),
        child: extended
            ? Row(
                children: [
                  mark,
                  const SizedBox(width: HopeSpacing.sm),
                  Expanded(
                    child: Text(
                      'HopeCash',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onToggleExtended,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: HopeSpacing.xs,
                      ),
                    ),
                    icon: const Icon(
                      Icons.keyboard_double_arrow_left,
                      size: 18,
                    ),
                    label: const Text('Recolher'),
                  ),
                ],
              )
            : Column(
                children: [
                  mark,
                  const SizedBox(height: HopeSpacing.xs),
                  IconButton(
                    tooltip: 'Expandir menu',
                    onPressed: onToggleExtended,
                    icon: const Icon(Icons.keyboard_double_arrow_right),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SidebarQuickActions extends StatelessWidget {
  const _SidebarQuickActions({
    required this.extended,
    required this.onQuick,
    required this.onVoice,
  });

  final bool extended;
  final VoidCallback onQuick;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!extended) {
      return Column(
        children: [
          IconButton.filled(
            tooltip: 'Adicionar lançamento',
            onPressed: onQuick,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(height: HopeSpacing.xs),
          IconButton(
            tooltip: 'Lançar por voz',
            onPressed: onVoice,
            icon: const Icon(Icons.mic_none_rounded),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        HopeSpacing.sm,
        HopeSpacing.xs,
        HopeSpacing.sm,
        0,
      ),
      padding: const EdgeInsets.all(HopeSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(HopeRadius.md),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AÇÕES RÁPIDAS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: HopeSpacing.xs),
          FilledButton.icon(
            onPressed: onQuick,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Novo lançamento'),
          ),
          const SizedBox(height: HopeSpacing.xs),
          TextButton.icon(
            onPressed: onVoice,
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Lançar por voz'),
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label, required this.extended});

  final String label;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: HopeSpacing.xs),
        child: Divider(indent: HopeSpacing.sm, endIndent: HopeSpacing.sm),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HopeSpacing.sm,
        HopeSpacing.xs,
        HopeSpacing.sm,
        HopeSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _DesktopRailDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final item = Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: Material(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.11)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(HopeRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: foreground,
                    size: 22,
                  ),
                ),
                if (extended)
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                if (extended && selected)
                  Container(
                    width: 4,
                    height: 20,
                    margin: const EdgeInsets.only(right: HopeSpacing.sm),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(HopeRadius.pill),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HopeSpacing.xxs / 2),
      child: extended ? item : Tooltip(message: destination.label, child: item),
    );
  }
}

class _SidebarUtilities extends StatelessWidget {
  const _SidebarUtilities({
    required this.extended,
    required this.darkModeEnabled,
    required this.onToggleTheme,
    required this.onLogout,
  });

  final bool extended;
  final bool darkModeEnabled;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(HopeSpacing.sm),
        child: Column(
          children: [
            _SidebarUtilityButton(
              extended: extended,
              tooltip: darkModeEnabled ? 'Modo claro' : 'Modo escuro',
              label: darkModeEnabled
                  ? 'Ativar modo claro'
                  : 'Ativar modo escuro',
              icon: darkModeEnabled
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              onPressed: onToggleTheme,
            ),
            const SizedBox(height: HopeSpacing.xs),
            _SidebarUtilityButton(
              extended: extended,
              tooltip: 'Sair',
              label: 'Sair',
              icon: Icons.logout_rounded,
              onPressed: onLogout,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarUtilityButton extends StatelessWidget {
  const _SidebarUtilityButton({
    required this.extended,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final bool extended;
  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = destructive
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    if (!extended) {
      return IconButton(
        tooltip: tooltip,
        color: foreground,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: HopeSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HopeRadius.sm),
          ),
        ),
        icon: Icon(icon),
        label: Text(label),
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
  if (confirmed == true) {
    ref.read(syncServiceProvider).stop();
    // Antes de limpar a sessão: o backend precisa do token de acesso ainda
    // válido para desativar o dispositivo.
    await ref.read(pushNotificationsServiceProvider).deactivateCurrentDevice();
    await ref.read(authRepositoryProvider).logout();
    ref.read(authStateProvider.notifier).state = null;
  }
}

class _DesktopRailDestination {
  const _DesktopRailDestination({
    required this.section,
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    this.branchIndex,
  });

  final String section;
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final int? branchIndex;
}

const _desktopRailDestinations = [
  _DesktopRailDestination(
    section: 'Principal',
    label: 'Início',
    path: '/',
    branchIndex: 0,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  _DesktopRailDestination(
    section: 'Principal',
    label: 'Hope',
    path: '/ai-chat',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome_rounded,
  ),
  _DesktopRailDestination(
    section: 'Principal',
    label: 'Lançamentos',
    path: '/transactions',
    branchIndex: 1,
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
  ),
  _DesktopRailDestination(
    section: 'Principal',
    label: 'Contas',
    path: '/accounts',
    branchIndex: 2,
    icon: Icons.account_balance_outlined,
    selectedIcon: Icons.account_balance_rounded,
  ),
  _DesktopRailDestination(
    section: 'Principal',
    label: 'Cartões',
    path: '/more/credit-cards',
    icon: Icons.credit_card_outlined,
    selectedIcon: Icons.credit_card_rounded,
  ),
  _DesktopRailDestination(
    section: 'Planejamento',
    label: 'Orçamento',
    path: '/more/budget',
    icon: Icons.pie_chart_outline,
    selectedIcon: Icons.pie_chart_rounded,
  ),
  _DesktopRailDestination(
    section: 'Planejamento',
    label: 'Metas',
    path: '/more/goals',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag_rounded,
  ),
  _DesktopRailDestination(
    section: 'Planejamento',
    label: 'Dívidas',
    path: '/more/debts',
    icon: Icons.trending_down_outlined,
    selectedIcon: Icons.trending_down_rounded,
  ),
  _DesktopRailDestination(
    section: 'Planejamento',
    label: 'Investimentos',
    path: '/more/investments',
    icon: Icons.show_chart_outlined,
    selectedIcon: Icons.show_chart_rounded,
  ),
  _DesktopRailDestination(
    section: 'Organização',
    label: 'Categorias',
    path: '/more/categories',
    icon: Icons.category_outlined,
    selectedIcon: Icons.category_rounded,
  ),
  _DesktopRailDestination(
    section: 'Organização',
    label: 'Importar',
    path: '/more/import',
    icon: Icons.upload_file_outlined,
    selectedIcon: Icons.upload_file_rounded,
  ),
  _DesktopRailDestination(
    section: 'Organização',
    label: 'Notificações bancárias',
    path: '/more/notification-suggestions',
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications_rounded,
  ),
  _DesktopRailDestination(
    section: 'Preferências',
    label: 'Notificações',
    path: '/more/push-preferences',
    icon: Icons.notifications_active_outlined,
    selectedIcon: Icons.notifications_active_rounded,
  ),
  _DesktopRailDestination(
    section: 'Preferências',
    label: 'Perfil',
    path: '/more/login-data',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts_rounded,
  ),
  _DesktopRailDestination(
    section: 'Preferências',
    label: 'Apps conectados',
    path: '/more/api-tokens',
    icon: Icons.hub_outlined,
    selectedIcon: Icons.hub_rounded,
  ),
];

int _selectedRailIndex(
  String location,
  List<_DesktopRailDestination> destinations,
) {
  final exact = destinations.indexWhere(
    (destination) => destination.path == location,
  );
  if (exact >= 0) return exact;

  final nested = destinations.indexWhere(
    (destination) =>
        destination.branchIndex == null &&
        location.startsWith('${destination.path}/'),
  );
  if (nested >= 0) return nested;

  return 0;
}

/// Barra inferior com os quatro destinos reais do app.
///
/// Antes ela misturava destinos e ações (Voz, Lançar), o que deixava dois dos
/// ramos de navegação — Lançamentos e Contas — sem entrada nenhuma no celular:
/// só dava para chegar neles pela tela "Mais" ou por um atalho do painel.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) => shell.goBranch(
        index,
        // Tocar no destino já ativo volta para a raiz daquele ramo.
        initialLocation: index == shell.currentIndex,
      ),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Início',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Histórico',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_outlined),
          selectedIcon: Icon(Icons.account_balance_rounded),
          label: 'Contas',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more_rounded),
          label: 'Mais',
        ),
      ],
    );
  }
}
