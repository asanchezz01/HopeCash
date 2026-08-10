import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/retaguarda_user.dart';
import '../components/hope_components.dart';

class RetaguardaUsersScreen extends ConsumerStatefulWidget {
  const RetaguardaUsersScreen({super.key, this.openCreateOnLoad = false});

  final bool openCreateOnLoad;

  @override
  ConsumerState<RetaguardaUsersScreen> createState() =>
      _RetaguardaUsersScreenState();
}

class _RetaguardaUsersScreenState extends ConsumerState<RetaguardaUsersScreen> {
  bool _handledInitialCreate = false;

  @override
  void initState() {
    super.initState();
    _scheduleInitialCreate();
  }

  @override
  void didUpdateWidget(covariant RetaguardaUsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openCreateOnLoad && !oldWidget.openCreateOnLoad) {
      _handledInitialCreate = false;
      _scheduleInitialCreate();
    }
  }

  void _scheduleInitialCreate() {
    if (!widget.openCreateOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialCreate());
  }

  Future<void> _openInitialCreate() async {
    if (!mounted || _handledInitialCreate) return;
    _handledInitialCreate = true;
    await _openForm(context, ref, ref.read(authStateProvider));
    if (mounted) context.go('/retaguarda-users');
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(retaguardaUsersProvider);
    final current = ref.watch(authStateProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(HopeSpacing.xl),
            child: PageHeader(
              title: 'Equipe da retaguarda',
              subtitle: 'Administradores com acesso a este painel.',
              actions: [
                FilledButton.icon(
                  onPressed: () => _openForm(context, ref, current),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Cadastrar equipe'),
                ),
              ],
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Não foi possível carregar',
                subtitle: e.toString(),
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(retaguardaUsersProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Nenhum membro cadastrado',
                    subtitle: 'Crie o primeiro acesso da equipe da retaguarda.',
                    action: FilledButton.icon(
                      onPressed: () => _openForm(context, ref, current),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Cadastrar equipe'),
                    ),
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
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _RetaguardaUserRow(
                              user: list[i],
                              isSelf: list[i].id == current?.id,
                              onEdit: () => _openForm(
                                context,
                                ref,
                                current,
                                user: list[i],
                              ),
                              onDelete: () =>
                                  _confirmDelete(context, ref, list[i]),
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

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    RetaguardaUser? current, {
    RetaguardaUser? user,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(
        user: user,
        canManageSuperuser: current?.isSuperuser ?? false,
      ),
    );
    if (saved == true) {
      ref.invalidate(retaguardaUsersProvider);
      ref.invalidate(statsProvider);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    RetaguardaUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir usuário?'),
        content: Text(
          'Remover o acesso de ${user.name} (${user.email}) à retaguarda?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(retaguardaUsersRepositoryProvider).delete(user.id);
      ref.invalidate(retaguardaUsersProvider);
      ref.invalidate(statsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Usuário excluído.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }
}

class _RetaguardaUserRow extends StatelessWidget {
  const _RetaguardaUserRow({
    required this.user,
    required this.isSelf,
    required this.onEdit,
    required this.onDelete,
  });

  final RetaguardaUser user;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.md,
        vertical: HopeSpacing.sm,
      ),
      child: Row(
        children: [
          InitialsAvatar(
            name: user.name,
            size: 40,
            color: user.isSuperuser ? AppTheme.purple : null,
          ),
          const SizedBox(width: HopeSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: HopeSpacing.xs),
                      const StatusBadge(label: 'você', color: AppTheme.skyBlue),
                    ],
                  ],
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
          user.isSuperuser
              ? const StatusBadge(
                  label: 'Superusuário',
                  color: AppTheme.purple,
                  icon: Icons.shield_rounded,
                )
              : const StatusBadge(
                  label: 'Admin',
                  color: AppTheme.skyBlue,
                  icon: Icons.person_rounded,
                ),
          const SizedBox(width: HopeSpacing.sm),
          user.isActive
              ? const StatusBadge(label: 'Ativo', color: AppTheme.success)
              : const StatusBadge(label: 'Bloqueado', color: AppTheme.danger),
          const SizedBox(width: HopeSpacing.sm),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: isSelf
                ? 'Você não pode excluir a própria conta'
                : 'Excluir',
            onPressed: isSelf ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _UserFormDialog extends ConsumerStatefulWidget {
  const _UserFormDialog({this.user, required this.canManageSuperuser});

  final RetaguardaUser? user;
  final bool canManageSuperuser;

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'admin';
  String _status = 'active';
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name.text = u?.name ?? '';
    _email.text = u?.email ?? '';
    _role = u?.role ?? 'admin';
    _status = u?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(retaguardaUsersRepositoryProvider);
      if (_isEdit) {
        await repo.update(
          widget.user!.id,
          name: _name.text.trim(),
          role: _role,
          status: _status,
          password: _password.text,
        );
      } else {
        await repo.create(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          role: _role,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSuperuser = widget.canManageSuperuser;
    return AlertDialog(
      title: Text(_isEdit ? 'Editar usuário' : 'Novo usuário'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Informe o nome'
                    : null,
              ),
              const SizedBox(height: HopeSpacing.md),
              TextFormField(
                controller: _email,
                enabled: !_isEdit,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'E-mail inválido' : null,
              ),
              const SizedBox(height: HopeSpacing.md),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: _isEdit ? 'Nova senha (opcional)' : 'Senha',
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                validator: (v) {
                  if (_isEdit && (v == null || v.isEmpty)) return null;
                  if (v == null || v.length < 8) {
                    return 'Mínimo de 8 caracteres';
                  }
                  if (!RegExp(r'[a-zA-Z]').hasMatch(v) ||
                      !RegExp(r'[0-9]').hasMatch(v)) {
                    return 'Use letras e números';
                  }
                  return null;
                },
              ),
              const SizedBox(height: HopeSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(labelText: 'Papel'),
                      items: [
                        const DropdownMenuItem(
                          value: 'admin',
                          child: Text('Administrador'),
                        ),
                        if (canSuperuser || _role == 'superuser')
                          const DropdownMenuItem(
                            value: 'superuser',
                            child: Text('Superusuário'),
                          ),
                      ],
                      onChanged: canSuperuser
                          ? (v) => setState(() => _role = v ?? 'admin')
                          : null,
                    ),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(width: HopeSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Ativo'),
                          ),
                          DropdownMenuItem(
                            value: 'blocked',
                            child: Text('Bloqueado'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _status = v ?? 'active'),
                      ),
                    ),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: HopeSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}
