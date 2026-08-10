import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/session.dart';
import '../widgets/brand_logo.dart';

/// Sessão salva no aparelho + biometria: confirma a identidade antes de
/// liberar o app. A biometria dispara sozinha ao abrir; se falhar ou for
/// cancelada, dá para tentar de novo ou entrar com e-mail e senha (encerra
/// a sessão salva).
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  bool _authenticating = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_authenticating || _starting) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final ok = await ref
        .read(biometricAuthServiceProvider)
        .authenticate(reason: 'Confirme sua identidade para entrar no HopeCash');
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _authenticating = false;
        _error = 'Não foi possível confirmar sua identidade. Tente novamente.';
      });
      return;
    }
    setState(() {
      _authenticating = false;
      _starting = true;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final user = ref.read(authStateProvider);
    if (user != null) await startUserSession(container, user);
    if (!mounted) return;
    ref.read(appLockedProvider.notifier).state = false;
  }

  /// Abre mão da sessão salva para autenticar com e-mail e senha (por
  /// exemplo, para entrar com outra conta).
  Future<void> _usePassword() async {
    if (_authenticating || _starting) return;
    setState(() => _starting = true);
    try {
      // O backend precisa do token ainda válido para desativar o push.
      await ref.read(pushNotificationsServiceProvider).deactivateCurrentDevice();
      await ref.read(authRepositoryProvider).logout();
    } finally {
      if (mounted) {
        // Ordem importa: sem usuário o router já cai no /login; só então a
        // trava é solta (evita passar pelo dashboard no caminho).
        ref.read(authStateProvider.notifier).state = null;
        ref.read(appLockedProvider.notifier).state = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authStateProvider);
    final busy = _authenticating || _starting;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HopeCashLogo(iconSize: 58, showTagline: true),
                const SizedBox(height: 32),
                if (user != null) ...[
                  Text(
                    'Olá, ${user.name}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
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
                  onPressed: busy ? null : _unlock,
                  icon: _starting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(
                    _starting ? 'Abrindo sua carteira...' : 'Entrar com biometria',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: busy ? null : _usePassword,
                  child: const Text('Entrar com e-mail e senha'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
