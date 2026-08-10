import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/app_users_repository.dart';
import '../components/hope_components.dart';

class AppUsersScreen extends ConsumerStatefulWidget {
  const AppUsersScreen({super.key});

  @override
  ConsumerState<AppUsersScreen> createState() => _AppUsersScreenState();
}

class _AppUsersScreenState extends ConsumerState<AppUsersScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(appUsersProvider);
    final status = ref.watch(appUsersStatusProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HopeSpacing.xl,
              HopeSpacing.xl,
              HopeSpacing.xl,
              HopeSpacing.md,
            ),
            child: Column(
              children: [
                PageHeader(
                  title: 'Usuários do app',
                  subtitle:
                      'Gerencie as contas dos usuários do aplicativo HopeCash.',
                  actions: [
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: () => ref.invalidate(appUsersProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: HopeSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou e-mail',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _search.clear();
                                    ref
                                            .read(
                                              appUsersQueryProvider.notifier,
                                            )
                                            .state =
                                        '';
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (v) =>
                            ref.read(appUsersQueryProvider.notifier).state = v
                                .trim(),
                      ),
                    ),
                    const SizedBox(width: HopeSpacing.md),
                    SegmentedButton<String?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('Todos')),
                        ButtonSegment(value: 'active', label: Text('Ativos')),
                        ButtonSegment(
                          value: 'blocked',
                          label: Text('Bloqueados'),
                        ),
                      ],
                      selected: {status},
                      onSelectionChanged: (v) =>
                          ref.read(appUsersStatusProvider.notifier).state =
                              v.first,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: page.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Não foi possível carregar',
                subtitle: e.toString(),
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(appUsersProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ),
              data: (result) {
                if (result.users.isEmpty) {
                  return const EmptyState(
                    icon: Icons.group_outlined,
                    title: 'Nenhum usuário encontrado',
                    subtitle: 'Ajuste a busca ou o filtro de status.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    HopeSpacing.xl,
                    0,
                    HopeSpacing.xl,
                    HopeSpacing.xl,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: HopeSpacing.sm),
                      child: Text(
                        '${result.total} usuário(s)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < result.users.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _UserRow(
                              user: result.users[i],
                              onResetPassword: () =>
                                  _resetPassword(result.users[i]),
                              onToggleStatus: () =>
                                  _toggleStatus(result.users[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStatus(AppUser user) async {
    final block = user.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(block ? 'Bloquear usuário?' : 'Desbloquear usuário?'),
        content: Text(
          block
              ? 'O usuário ${user.name} não conseguirá acessar o app e suas sessões serão encerradas.'
              : 'O usuário ${user.name} voltará a ter acesso ao app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(block ? 'Bloquear' : 'Desbloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(appUsersRepositoryProvider)
          .setStatus(user.id, block ? 'blocked' : 'active');
      ref.invalidate(appUsersProvider);
      ref.invalidate(statsProvider);
      _toast(block ? 'Usuário bloqueado.' : 'Usuário desbloqueado.');
    } catch (e) {
      _toast(e.toString(), error: true);
    }
  }

  Future<void> _resetPassword(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redefinir senha?'),
        content: Text(
          'Será gerada uma senha provisória para ${user.name} (${user.email}) e '
          'enviada por e-mail. As sessões ativas serão encerradas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Redefinir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await ref
          .read(appUsersRepositoryProvider)
          .resetPassword(user.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ResetResultDialog(user: user, result: result),
      );
    } catch (e) {
      _toast(e.toString(), error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.onResetPassword,
    required this.onToggleStatus,
  });

  final AppUser user;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < HopeBreakpoints.tablet;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.md,
        vertical: HopeSpacing.sm,
      ),
      child: Row(
        children: [
          InitialsAvatar(name: user.name, size: 40),
          const SizedBox(width: HopeSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!narrow) ...[
            SizedBox(
              width: 120,
              child: Text(
                _formatDate(user.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: HopeSpacing.sm),
          ],
          _pushTokenIndicator(context, user.hasPushToken),
          const SizedBox(width: HopeSpacing.sm),
          _statusBadge(user.status),
          const SizedBox(width: HopeSpacing.sm),
          IconButton(
            tooltip: 'Redefinir senha',
            onPressed: onResetPassword,
            icon: const Icon(Icons.lock_reset_rounded),
          ),
          IconButton(
            tooltip: user.isActive ? 'Bloquear' : 'Desbloquear',
            onPressed: onToggleStatus,
            icon: Icon(
              user.isActive
                  ? Icons.block_rounded
                  : Icons.check_circle_outline_rounded,
            ),
            color: user.isActive ? scheme.error : AppTheme.success,
          ),
        ],
      ),
    );
  }

  Widget _pushTokenIndicator(BuildContext context, bool hasPushToken) {
    final scheme = Theme.of(context).colorScheme;
    final label = hasPushToken ? 'Push vinculado' : 'Sem token de push';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(
          hasPushToken
              ? Icons.notifications_active_rounded
              : Icons.notifications_off_outlined,
          color: hasPushToken ? AppTheme.success : scheme.outline,
          size: 22,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    switch (status) {
      case 'blocked':
        return const StatusBadge(
          label: 'Bloqueado',
          color: AppTheme.danger,
          icon: Icons.block_rounded,
        );
      case 'pending_deletion':
        return const StatusBadge(
          label: 'Exclusão',
          color: AppTheme.warning,
          icon: Icons.hourglass_bottom_rounded,
        );
      default:
        return const StatusBadge(
          label: 'Ativo',
          color: AppTheme.success,
          icon: Icons.check_rounded,
        );
    }
  }
}

class _ResetResultDialog extends StatelessWidget {
  const _ResetResultDialog({required this.user, required this.result});

  final AppUser user;
  final PasswordResetResult result;

  @override
  Widget build(BuildContext context) {
    final code = result.code;
    final emailSent = result.emailSent;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.success),
          const SizedBox(width: HopeSpacing.sm),
          const Text('Senha redefinida'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emailSent
                ? 'A senha provisória foi enviada para ${user.email}.'
                : 'O envio de e-mail está desabilitado. Repasse a senha provisória abaixo ao usuário:',
          ),
          if (code != null) ...[
            const SizedBox(height: HopeSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(HopeSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(HopeRadius.sm),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      code,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(letterSpacing: 1.5),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Senha provisória copiada.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Concluir'),
        ),
      ],
    );
  }
}

String _formatDate(String? raw) {
  if (raw == null) return '—';
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (parsed == null) return raw;
  return DateFormat('dd/MM/yyyy').format(parsed);
}
