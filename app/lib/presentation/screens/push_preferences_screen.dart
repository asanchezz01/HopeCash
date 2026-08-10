import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/push_preferences.dart';
import '../../data/repositories/push_notifications_repository.dart';
import '../components/hope_components.dart';

const _advanceDayOptions = [1, 2, 3, 5, 7];

/// Preferências de notificação push do usuário — chave geral, categorias
/// (vencimentos/insights/dicas) e antecedência do aviso de vencimento.
class PushPreferencesScreen extends ConsumerStatefulWidget {
  const PushPreferencesScreen({super.key});

  @override
  ConsumerState<PushPreferencesScreen> createState() =>
      _PushPreferencesScreenState();
}

class _PushPreferencesScreenState extends ConsumerState<PushPreferencesScreen> {
  bool _saving = false;

  Future<void> _update(Map<String, dynamic> patch) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(pushNotificationsRepositoryProvider)
          .updatePreferences(patch);
      ref.invalidate(pushPreferencesProvider);
    } on PushNotificationsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _enableSystemNotifications() async {
    final granted = await ref
        .read(pushNotificationsServiceProvider)
        .requestPermissionAndRegister();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Notificações ativadas neste dispositivo.'
              : 'Permissão negada. Ative pelas configurações do sistema para receber avisos.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(pushPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: prefsAsync.when(
        loading: () => const HopeSkeleton(rows: 4),
        error: (error, _) => HopeErrorState.load(
          error,
          what: 'suas preferências de notificação',
          onRetry: () => ref.invalidate(pushPreferencesProvider),
        ),
        data: (prefs) => _PreferencesForm(
          prefs: prefs,
          saving: _saving,
          onChange: _update,
          onEnableSystem: _enableSystemNotifications,
        ),
      ),
    );
  }
}

class _PreferencesForm extends StatelessWidget {
  const _PreferencesForm({
    required this.prefs,
    required this.saving,
    required this.onChange,
    required this.onEnableSystem,
  });

  final PushPreferences prefs;
  final bool saving;
  final void Function(Map<String, dynamic> patch) onChange;
  final VoidCallback onEnableSystem;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppSurface(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Permissão do sistema',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Se o Android/iOS pediu permissão e você negou, use este '
                      'botão para tentar novamente.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onEnableSystem,
                child: const Text('Ativar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Ativar notificações'),
        const SizedBox(height: 8),
        FormSwitchRow(
          icon: Icons.notifications_active_outlined,
          title: 'Notificações push',
          subtitle: 'Chave geral — desligue para não receber nenhum aviso',
          value: prefs.pushEnabled,
          onChanged: saving ? (_) {} : (v) => onChange({'push_enabled': v}),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'O que você quer receber'),
        const SizedBox(height: 8),
        FormSwitchRow(
          icon: Icons.event_available_outlined,
          title: 'Avisos de vencimento',
          subtitle: 'Contas a pagar próximas do vencimento, no dia e em atraso',
          value: prefs.dueRemindersEnabled,
          onChanged: saving
              ? (_) {}
              : (v) => onChange({'due_reminders_enabled': v}),
        ),
        const SizedBox(height: 8),
        FormSwitchRow(
          icon: Icons.insights_outlined,
          title: 'Insights financeiros',
          subtitle: 'Análises e alertas sobre seus gastos',
          value: prefs.financialInsightsEnabled,
          onChanged: saving
              ? (_) {}
              : (v) => onChange({'financial_insights_enabled': v}),
        ),
        const SizedBox(height: 8),
        FormSwitchRow(
          icon: Icons.lightbulb_outline,
          title: 'Dicas da Hope',
          subtitle: 'Sugestões e novidades do app',
          value: prefs.tipsEnabled,
          onChanged: saving ? (_) {} : (v) => onChange({'tips_enabled': v}),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Canal por e-mail'),
        const SizedBox(height: 8),
        FormSwitchRow(
          icon: Icons.mail_outline,
          title: 'Notificações por e-mail',
          subtitle:
              'Receba também por e-mail as notificações autorizadas acima, '
              'mesmo quando o push estiver ativo',
          value: prefs.emailNotificationsEnabled,
          onChanged: saving
              ? (_) {}
              : (v) => onChange({'email_notifications_enabled': v}),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Antecedência do aviso de vencimento'),
        const SizedBox(height: 8),
        AppSurface(
          child: Row(
            children: [
              const Expanded(
                child: Text('Avisar com quantos dias de antecedência'),
              ),
              DropdownButton<int>(
                value: prefs.reminderAdvanceDays,
                items:
                    (<int>{
                          ..._advanceDayOptions,
                          prefs.reminderAdvanceDays,
                        }.toList()..sort())
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text('$d dia${d == 1 ? '' : 's'}'),
                          ),
                        )
                        .toList(),
                onChanged: saving
                    ? null
                    : (v) {
                        if (v != null) onChange({'reminder_advance_days': v});
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
