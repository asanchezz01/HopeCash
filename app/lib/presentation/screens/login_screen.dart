import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillSavedEmail();
  }

  /// Usuário salvo no aparelho: pré-preenche o e-mail para pedir só a senha
  /// (a sessão em si expira apenas por logout ou refresh token vencido).
  Future<void> _prefillSavedEmail() async {
    String? email;
    try {
      email = await ref.read(apiClientProvider).readLastEmail();
    } catch (_) {
      return; // storage indisponível — segue sem pré-preencher
    }
    final saved = email;
    if (!mounted || saved == null || _email.text.isNotEmpty) return;
    setState(() => _email.text = saved);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final user = _isRegister
          ? await repo.register(
              _name.text.trim(),
              _email.text.trim(),
              _password.text,
            )
          : await repo.login(_email.text.trim(), _password.text);

      // Credenciais confirmadas pelo servidor: agora sim é seguro pedir ao
      // navegador/SO para oferecer salvar a senha (autofill com biometria).
      TextInput.finishAutofillContext();

      // Contas compartilhadas comigo: deixo o usuário escolher qual abrir.
      DelegatedAccount? acting;
      if (!_isRegister) {
        final delegations = await repo.listReceivedDelegations();
        if (delegations.isNotEmpty && mounted) {
          final selected = await showDialog<DelegatedAccount>(
            context: context,
            builder: (_) => _AccountPickerDialog(
              userName: user.name,
              delegations: delegations,
            ),
          );
          if (selected != null) {
            acting = await repo.actAs(selected);
          }
        }
      }
      ref.read(actingAccountProvider.notifier).state = acting;
      await ref
          .read(financeRepositoryProvider)
          .prepareLocalStoreForUser(acting?.ownerId ?? user.id);
      ref.read(authStateProvider.notifier).state = user;
      ref.read(syncServiceProvider).start();
      if (mounted) await _maybeAskPushPermission(user.id);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pergunta uma única vez por usuário (guardado no banco local) se ele quer
  /// ativar notificações — pede a permissão do sistema só se aceitar. Em
  /// aberturas seguintes, apenas reconcilia o token silenciosamente.
  Future<void> _maybeAskPushPermission(String userId) async {
    final db = ref.read(databaseProvider);
    final askedKey = 'push_permission_asked_$userId';
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();

    if (await db.stateValue(askedKey) == '1') {
      unawaited(
        ref
            .read(pushNotificationsServiceProvider)
            .ensureRegistered(locale: locale),
      );
      return;
    }
    await db.setStateValue(askedKey, '1');
    if (!mounted) return;

    final accept = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ativar notificações?'),
        content: const Text(
          'Avisamos sobre contas a vencer e novidades da Hope. Você pode '
          'mudar isso depois em Mais > Notificações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ativar'),
          ),
        ],
      ),
    );
    if (accept == true) {
      await ref
          .read(pushNotificationsServiceProvider)
          .requestPermissionAndRegister(locale: locale);
    }
  }

  Future<void> _showPasswordRecovery() async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordRecoveryDialog(initialEmail: _email.text.trim()),
    );
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= HopeBreakpoints.tablet;
    final form = _buildForm(context, scheme);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: wide
          ? Row(
              children: [
                const Expanded(flex: 5, child: _HeroPanel()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(HopeSpacing.xxl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: form,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(HopeSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: form,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildForm(BuildContext context, ColorScheme scheme) {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HopeCashLogo(iconSize: 52, showTagline: true),
            const SizedBox(height: 28),
            Text(
              _isRegister ? 'Crie sua conta' : 'Acesse sua carteira',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              _isRegister
                  ? 'Comece agora a organizar sua vida financeira.'
                  : 'Entre para continuar cuidando dos seus planos.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (_isRegister) ...[
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Informe seu nome'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'E-mail inválido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: [
                _isRegister
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              onFieldSubmitted: (_) => _submit(),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Mínimo de 8 caracteres' : null,
            ),
            if (!_isRegister)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loading ? null : _showPasswordRecovery,
                  icon: const Icon(Icons.lock_reset_outlined),
                  label: const Text('Esqueci minha senha'),
                ),
              ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isRegister
                          ? Icons.person_add_alt_1_outlined
                          : Icons.login,
                    ),
              label: Text(_isRegister ? 'Criar conta' : 'Entrar'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _isRegister = !_isRegister;
                      _error = null;
                    }),
              child: Text(
                _isRegister
                    ? 'Já tenho conta — entrar'
                    : 'Criar uma conta gratuita',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ao criar uma conta, você aceita os termos de uso e a política de privacidade.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.deepBlue, AppTheme.primaryBlue],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Theme(
                    data: theme.copyWith(
                      colorScheme: theme.colorScheme.copyWith(
                        onSurface: Colors.white,
                        onSurfaceVariant: Colors.white70,
                      ),
                    ),
                    child: const HopeCashLogo(iconSize: 64),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Sua vida financeira, mais clara',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Organize o presente, planeje os próximos passos e mantenha suas decisões no controle.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const _HeroBullet(
                    icon: Icons.account_balance_wallet_outlined,
                    text: 'Contas, cartões e lançamentos em um só lugar',
                  ),
                  const _HeroBullet(
                    icon: Icons.calendar_month_outlined,
                    text: 'Planejamento para hoje e para os próximos meses',
                  ),
                  const _HeroBullet(
                    icon: Icons.auto_awesome_outlined,
                    text: 'Hope para entender seus dados e preparar ações',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBullet extends StatelessWidget {
  const _HeroBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.hopeGreenBright, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escolha de conta ao entrar: a própria ou uma compartilhada comigo.
/// Fechar o diálogo (ou escolher a própria) retorna null.
class _AccountPickerDialog extends StatelessWidget {
  const _AccountPickerDialog({
    required this.userName,
    required this.delegations,
  });

  final String userName;
  final List<DelegatedAccount> delegations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SimpleDialog(
      title: const Text('Qual conta você quer abrir?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.person_outline, color: scheme.primary),
            ),
            title: Text(userName),
            subtitle: const Text('Minha conta'),
          ),
        ),
        for (final d in delegations)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, d),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: scheme.secondary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.supervisor_account_outlined,
                  color: scheme.secondary,
                ),
              ),
              title: Text(d.ownerName),
              subtitle: Text(
                d.readOnly
                    ? '${d.ownerEmail} · somente leitura'
                    : '${d.ownerEmail} · acesso total',
              ),
            ),
          ),
      ],
    );
  }
}

enum _PasswordRecoveryStep { request, reset }

class _PasswordRecoveryDialog extends ConsumerStatefulWidget {
  const _PasswordRecoveryDialog({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_PasswordRecoveryDialog> createState() =>
      _PasswordRecoveryDialogState();
}

class _PasswordRecoveryDialogState
    extends ConsumerState<_PasswordRecoveryDialog> {
  final _requestKey = GlobalKey<FormState>();
  final _resetKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _PasswordRecoveryStep _step = _PasswordRecoveryStep.request;
  bool _loading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (!_requestKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _notice = message;
        _step = _PasswordRecoveryStep.reset;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_resetKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(authRepositoryProvider)
          .resetPassword(
            token: _token.text.trim(),
            password: _newPassword.text,
          );
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.pop(context, message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showResetStep() {
    setState(() {
      _step = _PasswordRecoveryStep.reset;
      _error = null;
    });
  }

  void _showRequestStep() {
    setState(() {
      _step = _PasswordRecoveryStep.request;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRequestStep = _step == _PasswordRecoveryStep.request;
    return AlertDialog(
      title: Text(isRequestStep ? 'Recuperar senha' : 'Redefinir senha'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isRequestStep ? _buildRequestForm() : _buildResetForm(),
          ),
        ),
      ),
      actions: [
        if (isRequestStep)
          TextButton(
            onPressed: _loading ? null : _showResetStep,
            child: const Text('Já tenho token'),
          )
        else
          TextButton(
            onPressed: _loading ? null : _showRequestStep,
            child: const Text('Reenviar'),
          ),
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _loading
              ? null
              : (isRequestStep ? _requestReset : _resetPassword),
          icon: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isRequestStep
                      ? Icons.mark_email_read_outlined
                      : Icons.lock_reset_outlined,
                ),
          label: Text(isRequestStep ? 'Enviar' : 'Redefinir'),
        ),
      ],
    );
  }

  Widget _buildRequestForm() {
    return Form(
      key: _requestKey,
      child: Column(
        key: const ValueKey('request-password-reset'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Informe o e-mail cadastrado para receber o token de recuperação.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _loading ? null : _requestReset(),
            validator: _validateEmail,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResetForm() {
    return Form(
      key: _resetKey,
      child: AutofillGroup(
        child: Column(
          key: const ValueKey('confirm-password-reset'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_notice != null) ...[
              Text(
                _notice!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _token,
              decoration: const InputDecoration(
                labelText: 'Token recebido',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Informe o token de recuperação'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newPassword,
              decoration: InputDecoration(
                labelText: 'Nova senha',
                prefixIcon: const Icon(Icons.lock_outline),
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
              autofillHints: const [AutofillHints.newPassword],
              validator: _validateStrongPassword,
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
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
              obscureText: _obscureConfirmPassword,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _loading ? null : _resetPassword(),
              validator: (value) =>
                  value != _newPassword.text ? 'As senhas não conferem' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  return (value == null || !value.contains('@')) ? 'E-mail inválido' : null;
}

String? _validateStrongPassword(String? value) {
  if (value == null || value.length < 8) return 'Mínimo de 8 caracteres';
  if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value)) {
    return 'Use letras e números';
  }
  return null;
}
