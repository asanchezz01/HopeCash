import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/build_info.dart';
import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_user.dart';
import '../components/hope_components.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    final stats = ref.watch(statsProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(statsProvider);
          ref.invalidate(dashboardUsersProvider);
          ref.invalidate(aiHealthProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(HopeSpacing.xl),
          children: [
            PageHeader(
              title: 'Olá, ${user?.name.split(' ').first ?? 'admin'}',
              subtitle: 'Visão geral da administração do HopeCash.',
              actions: [
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: () => ref.invalidate(statsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: HopeSpacing.xl),
            stats.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(HopeSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBox(
                message: e.toString(),
                onRetry: () => ref.invalidate(statsProvider),
              ),
              data: (s) => _DashboardStats(stats: s),
            ),
            const SizedBox(height: HopeSpacing.xl),
            Text(
              'Ações rápidas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: HopeSpacing.md),
            Wrap(
              spacing: HopeSpacing.md,
              runSpacing: HopeSpacing.md,
              children: [
                _QuickAction(
                  icon: Icons.group_rounded,
                  title: 'Gerenciar usuários do app',
                  subtitle: 'Buscar, bloquear e redefinir senhas',
                  onTap: () => context.go('/app-users'),
                ),
                _QuickAction(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'Equipe da retaguarda',
                  subtitle: 'Adicionar e gerenciar administradores',
                  onTap: () => context.go('/retaguarda-users'),
                ),
                _QuickAction(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Cadastrar equipe',
                  subtitle: 'Criar acesso para um novo administrador',
                  onTap: () => context.go('/retaguarda-users/new'),
                ),
                _QuickAction(
                  icon: Icons.notifications_rounded,
                  title: 'Notificações push',
                  subtitle: 'Criar, agendar e acompanhar campanhas',
                  onTap: () => context.go('/notifications'),
                ),
              ],
            ),
            const SizedBox(height: HopeSpacing.xl),
            Text(
              'Servidor de IA',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: HopeSpacing.md),
            const _AiHealthCard(),
            const SizedBox(height: HopeSpacing.xl),
            const _VersionFooter(),
          ],
        ),
      ),
    );
  }
}

class _DashboardStats extends ConsumerWidget {
  const _DashboardStats({required this.stats});

  final RetaguardaStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedUserId = ref.watch(dashboardUserFilterProvider);
    final users = ref.watch(dashboardUsersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatsGrid(
          cards: [
            StatCard(
              label: 'Usuários do app',
              value: '${stats.appUsersTotal}',
              icon: Icons.group_rounded,
              color: AppTheme.skyBlue,
            ),
            StatCard(
              label: 'Ativos',
              value: '${stats.appUsersActive}',
              icon: Icons.verified_user_rounded,
              color: AppTheme.success,
            ),
            StatCard(
              label: 'Bloqueados',
              value: '${stats.appUsersBlocked}',
              icon: Icons.block_rounded,
              color: AppTheme.danger,
            ),
            StatCard(
              label: 'Equipe retaguarda',
              value: '${stats.retaguardaUsersTotal}',
              icon: Icons.admin_panel_settings_rounded,
              color: AppTheme.purple,
            ),
          ],
        ),
        const SizedBox(height: HopeSpacing.xl),
        Wrap(
          spacing: HopeSpacing.lg,
          runSpacing: HopeSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dados financeiros',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selectedUserId == null
                        ? 'Indicadores de todos os usuários'
                        : 'Indicadores do usuário selecionado',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 360,
              child: users.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => OutlinedButton.icon(
                  onPressed: () => ref.invalidate(dashboardUsersProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Recarregar usuários'),
                ),
                data: (items) => DropdownButtonFormField<String>(
                  key: ValueKey(selectedUserId),
                  initialValue: selectedUserId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por usuário',
                    prefixIcon: Icon(Icons.person_search_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos os usuários'),
                    ),
                    for (final user in items)
                      DropdownMenuItem(
                        value: user.id,
                        child: Text(
                          '${user.name} — ${user.email}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    ref.read(dashboardUserFilterProvider.notifier).state =
                        value == null || value.isEmpty ? null : value;
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: HopeSpacing.md),
        _StatsGrid(
          cards: [
            StatCard(
              label: 'Contas',
              value: '${stats.accountsTotal}',
              icon: Icons.account_balance_rounded,
              color: AppTheme.skyBlue,
            ),
            StatCard(
              label: 'Cartões de crédito',
              value: '${stats.creditCardsTotal}',
              icon: Icons.credit_card_rounded,
              color: AppTheme.purple,
            ),
            StatCard(
              label: 'Dívidas',
              value: '${stats.debtsTotal}',
              icon: Icons.trending_down_rounded,
              color: AppTheme.warning,
            ),
            StatCard(
              label: 'Orçamentos',
              value: '${stats.budgetsTotal}',
              icon: Icons.pie_chart_rounded,
              color: AppTheme.hopeGreen,
            ),
            StatCard(
              label: 'Lançamentos de receita',
              value: '${stats.incomeTransactionsTotal}',
              icon: Icons.arrow_upward_rounded,
              color: AppTheme.income,
            ),
            StatCard(
              label: 'Lançamentos de despesa',
              value: '${stats.expenseTransactionsTotal}',
              icon: Icons.arrow_downward_rounded,
              color: AppTheme.expense,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: HopeSpacing.md,
          crossAxisSpacing: HopeSpacing.md,
          childAspectRatio: 1.7,
          children: cards,
        );
      },
    );
  }
}

/// Estado do servidor Ollama: online/offline, versão, modelos configurados ×
/// instalados. Alerta quando um modelo configurado não existe no servidor.
class _AiHealthCard extends ConsumerWidget {
  const _AiHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final health = ref.watch(aiHealthProvider);

    return AppSurface(
      child: health.when(
        loading: () => const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: HopeSpacing.md),
            Text('Consultando servidor de IA…'),
          ],
        ),
        error: (e, _) => Row(
          children: [
            Icon(Icons.smart_toy_outlined, color: AppTheme.danger),
            const SizedBox(width: HopeSpacing.md),
            const Expanded(
              child: Text('Não foi possível consultar o estado da IA.'),
            ),
            IconButton(
              tooltip: 'Tentar novamente',
              onPressed: () => ref.invalidate(aiHealthProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        data: (h) {
          final statusColor = h.ok ? AppTheme.success : AppTheme.danger;
          final missing = h.ok ? h.missingModels : const <String>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy_outlined, color: statusColor),
                  const SizedBox(width: HopeSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.ok
                              ? 'Ollama ${h.version ?? ''} online'
                              : 'Ollama indisponível',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          h.ok
                              ? h.url
                              : '${h.url} — ${h.error ?? 'sem resposta'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (h.ok && h.installedModels.isNotEmpty) ...[
                const SizedBox(height: HopeSpacing.md),
                Wrap(
                  spacing: HopeSpacing.sm,
                  runSpacing: HopeSpacing.xs,
                  children: [
                    for (final m in h.installedModels)
                      Chip(
                        label: Text(m.label),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: HopeSpacing.sm),
                Text(
                  'Configurados — padrão: ${h.configuredModels['default'] ?? '—'} · '
                  'chat: ${h.configuredModels['chat'] ?? '—'} · '
                  'rápido: ${h.configuredModels['fast'] ?? '—'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: HopeSpacing.sm),
                Text(
                  'Atenção: modelo(s) configurado(s) não instalado(s) no servidor: '
                  '${missing.join(', ')}. Os recursos de IA vão falhar até ajustar '
                  'OLLAMA_MODEL* ou instalar o modelo.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Rodapé do dashboard com a versão publicada da retaguarda (build local) e do
/// app/API (consultado em /version). Refs divergentes indicam container defasado.
class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final apiVersion = ref.watch(apiVersionProvider);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final apiLabel = apiVersion.when(
      loading: () => 'App: …',
      error: (_, _) => 'App: indisponível',
      data: (v) => 'App: ${v.label}',
    );
    final mismatch = apiVersion.maybeWhen(
      data: (v) =>
          v.ref != 'local' &&
          BuildInfo.ref != 'local' &&
          v.ref != BuildInfo.ref,
      orElse: () => false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Divider(),
        const SizedBox(height: HopeSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: HopeSpacing.md,
          runSpacing: HopeSpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text('Retaguarda: ${BuildInfo.label}', style: style),
              ],
            ),
            Text(apiLabel, style: style),
          ],
        ),
        if (BuildInfo.buildTime.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('Publicado em ${BuildInfo.buildTime}', style: style),
        ],
        if (mismatch) ...[
          const SizedBox(height: HopeSpacing.xs),
          Text(
            'Atenção: versões da retaguarda e do app divergem — um container pode estar desatualizado.',
            textAlign: TextAlign.center,
            style: style?.copyWith(
              color: AppTheme.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 320,
      child: AppSurface(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(HopeRadius.sm),
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(width: HopeSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 32,
          ),
          const SizedBox(height: HopeSpacing.sm),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: HopeSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
