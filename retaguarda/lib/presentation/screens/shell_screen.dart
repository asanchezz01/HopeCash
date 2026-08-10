import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../components/hope_components.dart';
import '../widgets/brand_logo.dart';

/// Casca da retaguarda: barra de navegação lateral permanente em desktop,
/// barra inferior em telas estreitas.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _destinations = [
    _Destination(
      'Início',
      '/',
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
    ),
    _Destination(
      'Usuários do app',
      '/app-users',
      Icons.group_outlined,
      Icons.group_rounded,
    ),
    _Destination(
      'Retaguarda',
      '/retaguarda-users',
      Icons.admin_panel_settings_outlined,
      Icons.admin_panel_settings_rounded,
    ),
    _Destination(
      'Notificações',
      '/notifications',
      Icons.notifications_outlined,
      Icons.notifications_rounded,
    ),
    _Destination(
      'Perfil',
      '/profile',
      Icons.account_circle_outlined,
      Icons.account_circle_rounded,
    ),
  ];

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).logout();
    ref.read(authStateProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final showRail = width >= HopeBreakpoints.tablet;
    final extended = width >= HopeBreakpoints.desktop;

    if (showRail) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(
              shell: shell,
              extended: extended,
              destinations: _destinations,
              onLogout: () => _logout(context, ref),
            ),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.path, this.icon, this.selectedIcon);
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}

class _SideNav extends ConsumerWidget {
  const _SideNav({
    required this.shell,
    required this.extended,
    required this.destinations,
    required this.onLogout,
  });

  final StatefulNavigationShell shell;
  final bool extended;
  final List<_Destination> destinations;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    final scheme = Theme.of(context).colorScheme;
    final width = extended ? 256.0 : 84.0;

    return Container(
      width: width,
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                extended ? HopeSpacing.lg : HopeSpacing.sm,
                HopeSpacing.lg,
                HopeSpacing.sm,
                HopeSpacing.lg,
              ),
              child: extended
                  ? const HopeCashLogo(iconSize: 34)
                  : const Center(
                      child: HopeCashLogo(compact: true, iconSize: 34),
                    ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? HopeSpacing.sm : 6,
                ),
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _NavItem(
                      destination: destinations[i],
                      selected: shell.currentIndex == i,
                      extended: extended,
                      onTap: () => context.go(destinations[i].path),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(HopeSpacing.sm),
              child: extended
                  ? Row(
                      children: [
                        InitialsAvatar(name: user?.name ?? '?', size: 34),
                        const SizedBox(width: HopeSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              Text(
                                user?.isSuperuser == true
                                    ? 'Superusuário'
                                    : 'Administrador',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sair',
                          onPressed: onLogout,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                      ],
                    )
                  : Center(
                      child: IconButton(
                        tooltip: 'Sair',
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout_rounded),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(HopeRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          onTap: onTap,
          child: Tooltip(
            message: extended ? '' : destination.label,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: extended ? HopeSpacing.md : 0,
                vertical: HopeSpacing.sm,
              ),
              child: extended
                  ? Row(
                      children: [
                        Icon(
                          selected
                              ? destination.selectedIcon
                              : destination.icon,
                          color: color,
                          size: 22,
                        ),
                        const SizedBox(width: HopeSpacing.sm),
                        Expanded(
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: selected
                                      ? scheme.primary
                                      : scheme.onSurface,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: color,
                      size: 24,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
