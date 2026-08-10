import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/auth_repository.dart';

class LoginDataScreen extends ConsumerStatefulWidget {
  const LoginDataScreen({super.key});

  @override
  ConsumerState<LoginDataScreen> createState() => _LoginDataScreenState();
}

class _LoginDataScreenState extends ConsumerState<LoginDataScreen> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _profilePassword = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _obscureProfilePassword = true;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  List<GrantedDelegation>? _granted;
  List<DelegatedAccount>? _received;
  String? _delegationsError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider);
    _name.text = user?.name ?? '';
    _email.text = user?.email ?? '';
    if (ref.read(actingAccountProvider) == null) _loadDelegations();
  }

  Future<void> _loadDelegations() async {
    final repo = ref.read(authRepositoryProvider);
    try {
      final granted = await repo.listGrantedDelegations();
      final received = await repo.listReceivedDelegations();
      if (mounted) {
        setState(() {
          _granted = granted;
          _received = received;
          _delegationsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _delegationsError = e.toString());
    }
  }

  Future<void> _grantAccess() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _GrantAccessDialog(),
    );
    if (result == null) return;
    final (email, permission) = result;
    try {
      final (_, emailSent) = await ref
          .read(authRepositoryProvider)
          .grantDelegation(email: email, permission: permission);
      await _loadDelegations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              emailSent
                  ? 'Acesso concedido — $email foi avisado(a) por e-mail'
                  : 'Acesso concedido a $email',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _revokeAccess(GrantedDelegation delegation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revogar acesso?'),
        content: Text(
          '${delegation.delegateName.isEmpty ? delegation.delegateEmail : delegation.delegateName} '
          'perderá imediatamente o acesso à sua conta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(authRepositoryProvider).revokeDelegation(delegation.id);
      await _loadDelegations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso revogado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _viewAccount(DelegatedAccount account) async {
    try {
      final acting = await ref.read(authRepositoryProvider).actAs(account);
      ref.read(actingAccountProvider.notifier).state = acting;
      await ref
          .read(financeRepositoryProvider)
          .prepareLocalStoreForUser(acting.ownerId);
      ref.read(syncServiceProvider).syncNow();
      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Visualizando a conta de ${acting.ownerName}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _profilePassword.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .updateLoginData(
            name: _name.text.trim(),
            email: _email.text.trim(),
            currentPassword: _profilePassword.text,
          );
      ref.read(authStateProvider.notifier).state = user;
      _profilePassword.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados de login atualizados')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .updatePassword(
            currentPassword: _currentPassword.text,
            password: _newPassword.text,
          );
      ref.read(syncServiceProvider).stop();
      ref.read(authStateProvider.notifier).state = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Senha atualizada. Entre novamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acting = ref.watch(actingAccountProvider);

    if (acting != null) {
      // Sessão delegada: perfil e delegações pertencem ao usuário real.
      return Scaffold(
        appBar: AppBar(title: const Text('Meu perfil')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                      icon: Icons.supervisor_account_outlined,
                      title: 'Você está na conta de ${acting.ownerName}',
                      subtitle:
                          'Para editar seu perfil ou gerenciar acessos, '
                          'volte para a sua conta em Mais → Voltar.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _profileKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionTitle(
                      icon: Icons.badge_outlined,
                      title: 'Acesso',
                      subtitle: 'Nome e e-mail usados para entrar no HopeCash.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Informe seu nome'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'E-mail inválido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _profilePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha atual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscureProfilePassword
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                          icon: Icon(
                            _obscureProfilePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureProfilePassword =
                                !_obscureProfilePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscureProfilePassword,
                      onFieldSubmitted: (_) => _saveProfile(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Confirme sua senha atual'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _savingProfile ? null : _saveProfile,
                      icon: _savingProfile
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Salvar dados'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _passwordKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionTitle(
                      icon: Icons.password_outlined,
                      title: 'Senha',
                      subtitle:
                          'Ao alterar a senha, as sessões abertas serão encerradas.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _currentPassword,
                      decoration: InputDecoration(
                        labelText: 'Senha atual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscureCurrentPassword
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                          icon: Icon(
                            _obscureCurrentPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureCurrentPassword =
                                !_obscureCurrentPassword,
                          ),
                        ),
                      ),
                      obscureText: _obscureCurrentPassword,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Informe sua senha atual'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPassword,
                      decoration: InputDecoration(
                        labelText: 'Nova senha',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          tooltip: _obscureNewPassword
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureNewPassword = !_obscureNewPassword,
                          ),
                        ),
                      ),
                      obscureText: _obscureNewPassword,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.length < 8) {
                          return 'Mínimo de 8 caracteres';
                        }
                        if (!RegExp(r'[A-Za-z]').hasMatch(v) ||
                            !RegExp(r'[0-9]').hasMatch(v)) {
                          return 'Use letras e números';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirmar nova senha',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        suffixIcon: IconButton(
                          tooltip: _obscureConfirmPassword
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                      obscureText: _obscureConfirmPassword,
                      onFieldSubmitted: (_) => _savePassword(),
                      validator: (v) => v != _newPassword.text
                          ? 'As senhas não conferem'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.deepBlue,
                      ),
                      onPressed: _savingPassword ? null : _savePassword,
                      icon: _savingPassword
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_reset_outlined),
                      label: const Text('Alterar senha'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Depois da troca, faça login novamente com a nova senha.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionTitle(
                    icon: Icons.group_add_outlined,
                    title: 'Acesso compartilhado',
                    subtitle:
                        'Delegue o acesso à sua conta para outra pessoa do '
                        'HopeCash — somente leitura ou total. Ela será '
                        'avisada por e-mail e você pode revogar quando quiser.',
                  ),
                  const SizedBox(height: 8),
                  if (_delegationsError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _delegationsError!,
                        style: TextStyle(color: scheme.error),
                      ),
                    )
                  else if (_granted == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_granted!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Ninguém tem acesso à sua conta.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final d in _granted!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            d.permission == 'read'
                                ? Icons.visibility_outlined
                                : Icons.edit_outlined,
                            color: scheme.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          d.delegateName.isEmpty
                              ? d.delegateEmail
                              : d.delegateName,
                        ),
                        subtitle: Text(
                          '${d.delegateEmail} · '
                          '${d.permission == 'read' ? 'somente leitura' : 'acesso total'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Revogar acesso',
                          icon: Icon(
                            Icons.link_off_rounded,
                            color: scheme.error,
                          ),
                          onPressed: () => _revokeAccess(d),
                        ),
                      ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _delegationsError != null
                        ? _loadDelegations
                        : _grantAccess,
                    icon: Icon(
                      _delegationsError != null
                          ? Icons.refresh
                          : Icons.person_add_alt_outlined,
                    ),
                    label: Text(
                      _delegationsError != null
                          ? 'Tentar novamente'
                          : 'Conceder acesso',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_received != null && _received!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionTitle(
                      icon: Icons.supervisor_account_outlined,
                      title: 'Contas compartilhadas comigo',
                      subtitle:
                          'Contas de outras pessoas que você pode visualizar. '
                          'A troca também está disponível ao entrar no app.',
                    ),
                    const SizedBox(height: 8),
                    for (final d in _received!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: scheme.secondary.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            Icons.account_circle_outlined,
                            color: scheme.secondary,
                            size: 22,
                          ),
                        ),
                        title: Text(d.ownerName),
                        subtitle: Text(
                          '${d.ownerEmail} · '
                          '${d.readOnly ? 'somente leitura' : 'acesso total'}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _viewAccount(d),
                          child: const Text('Visualizar'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Diálogo para conceder acesso: e-mail do usuário + nível de permissão.
class _GrantAccessDialog extends StatefulWidget {
  const _GrantAccessDialog();

  @override
  State<_GrantAccessDialog> createState() => _GrantAccessDialogState();
}

class _GrantAccessDialogState extends State<_GrantAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String _permission = 'read';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conceder acesso'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'E-mail do usuário',
                prefixIcon: Icon(Icons.mail_outline),
                helperText: 'A pessoa precisa ter conta no HopeCash',
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'E-mail inválido' : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'read',
                  label: Text('Somente leitura'),
                  icon: Icon(Icons.visibility_outlined),
                ),
                ButtonSegment(
                  value: 'full',
                  label: Text('Total'),
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
              selected: {_permission},
              onSelectionChanged: (s) => setState(() => _permission = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _permission == 'read'
                  ? 'Poderá ver seus dados, sem alterar nada.'
                  : 'Poderá ver e lançar/editar como você.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              _email.text.trim().toLowerCase(),
              _permission,
            ));
          },
          child: const Text('Conceder'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
