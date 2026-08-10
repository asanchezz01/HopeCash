import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../components/hope_components.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changeOwnPassword(
            currentPassword: _current.text,
            password: _password.text,
          );
      // A troca de senha encerra a sessão → volta ao login.
      ref.read(authStateProvider.notifier).state = null;
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(HopeSpacing.xl),
        children: [
          const PageHeader(
            title: 'Meu perfil',
            subtitle: 'Sua conta de acesso à retaguarda.',
          ),
          const SizedBox(height: HopeSpacing.xl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSurface(
                  child: Row(
                    children: [
                      InitialsAvatar(
                        name: user?.name ?? '?',
                        size: 56,
                        color: user?.isSuperuser == true ? AppTheme.purple : null,
                      ),
                      const SizedBox(width: HopeSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.name ?? '', style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              user?.email ?? '',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      user?.isSuperuser == true
                          ? const StatusBadge(label: 'Superusuário', color: AppTheme.purple, icon: Icons.shield_rounded)
                          : const StatusBadge(label: 'Admin', color: AppTheme.skyBlue, icon: Icons.person_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: HopeSpacing.xl),
                Text('Alterar senha', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: HopeSpacing.md),
                AppSurface(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _current,
                          decoration: const InputDecoration(
                            labelText: 'Senha atual',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha atual' : null,
                        ),
                        const SizedBox(height: HopeSpacing.md),
                        TextFormField(
                          controller: _password,
                          decoration: const InputDecoration(
                            labelText: 'Nova senha',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          obscureText: true,
                          validator: (v) {
                            if (v == null || v.length < 8) return 'Mínimo de 8 caracteres';
                            if (!RegExp(r'[a-zA-Z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
                              return 'Use letras e números';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: HopeSpacing.md),
                        TextFormField(
                          controller: _confirm,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar nova senha',
                            prefixIcon: Icon(Icons.check_circle_outline),
                          ),
                          obscureText: true,
                          validator: (v) => v != _password.text ? 'As senhas não conferem' : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: HopeSpacing.md),
                          Text(_error!, style: TextStyle(color: scheme.error)),
                        ],
                        const SizedBox(height: HopeSpacing.lg),
                        Text(
                          'Ao alterar a senha, sua sessão será encerrada e você entrará novamente.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: HopeSpacing.md),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_rounded),
                          label: const Text('Salvar nova senha'),
                        ),
                      ],
                    ),
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
