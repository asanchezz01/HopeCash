import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_user.dart';
import '../../data/models/automation_rule.dart';
import '../components/hope_components.dart';

const _typeLabels = {
  'due_reminder': 'Avisos de vencimento',
  'financial_insight': 'Insights financeiros',
  'tip': 'Dicas da Hope',
};

const _typeDescriptions = {
  'due_reminder':
      'Aviso automático quando uma conta a pagar está perto do vencimento, '
      'vence hoje ou ficou em atraso. Enviado por transação — a frequência '
      'abaixo é a antecedência padrão (dias antes do vencimento) para quem '
      'ainda não ajustou isso no próprio app.',
  'financial_insight':
      'Alerta automático quando uma categoria do orçamento do mês se '
      'aproxima do limite planejado. A frequência abaixo é o intervalo '
      'mínimo entre insights para o mesmo usuário.',
  'tip':
      'Dica financeira enviada periodicamente aos usuários que optaram por '
      'recebê-las. A frequência abaixo é o intervalo mínimo entre dicas '
      'para o mesmo usuário.',
};

const _frequencyLabels = {
  'due_reminder': 'Antecedência padrão (dias antes do vencimento)',
  'financial_insight': 'Intervalo mínimo entre envios (dias)',
  'tip': 'Intervalo mínimo entre envios (dias)',
};

/// Ordem de exibição fixa — a API devolve em ordem alfabética de message_type.
const _displayOrder = ['due_reminder', 'financial_insight', 'tip'];

/// Gestão das mensagens push automáticas do sistema: liga/desliga cada tipo,
/// ajusta a frequência de envio e (quando aplicável) o conteúdo enviado.
/// Diferente das campanhas manuais — estas mensagens entram na mesma fila de
/// notificações e são processadas sozinhas pelo scheduler.
class AutomationRulesScreen extends ConsumerWidget {
  const AutomationRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(automationRulesProvider);
    final isSuperuser = ref.watch(authStateProvider)?.isSuperuser ?? false;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(HopeSpacing.xl),
            child: PageHeader(
              title: 'Mensagens automáticas',
              subtitle:
                  'Ligue/desligue e ajuste a frequência de cada tipo de '
                  'mensagem push disparada automaticamente pelo sistema.',
            ),
          ),
          Expanded(
            child: rules.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Não foi possível carregar',
                subtitle: e.toString(),
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(automationRulesProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ),
              data: (list) {
                final sorted = [...list]
                  ..sort(
                    (a, b) => _displayOrder
                        .indexOf(a.messageType)
                        .compareTo(_displayOrder.indexOf(b.messageType)),
                  );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    HopeSpacing.xl,
                    0,
                    HopeSpacing.xl,
                    HopeSpacing.xl,
                  ),
                  children: [
                    for (final rule in sorted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: HopeSpacing.md),
                        child: _RuleCard(rule: rule, isSuperuser: isSuperuser),
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
}

class _RuleCard extends ConsumerStatefulWidget {
  const _RuleCard({required this.rule, required this.isSuperuser});

  final AutomationRule rule;
  final bool isSuperuser;

  @override
  ConsumerState<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends ConsumerState<_RuleCard> {
  late bool _enabled = widget.rule.enabled;
  late final _frequency = TextEditingController(
    text: widget.rule.frequencyDays.toString(),
  );
  late final _title = TextEditingController(text: widget.rule.title ?? '');
  late final _body = TextEditingController(text: widget.rule.body ?? '');
  late final _threshold = TextEditingController(
    text: (widget.rule.config['threshold_percent'] ?? 90).toString(),
  );
  bool _saving = false;
  bool _generating = false;
  bool _sending = false;
  bool _dirty = false;
  String? _personalizedUserId;
  String? _personalizedUserLabel;

  bool get _hasContent => widget.rule.messageType != 'due_reminder';
  bool get _hasThreshold => widget.rule.messageType == 'financial_insight';

  @override
  void dispose() {
    _frequency.dispose();
    _title.dispose();
    _body.dispose();
    _threshold.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final frequencyDays = int.tryParse(_frequency.text.trim());
    if (frequencyDays == null || frequencyDays < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Frequência inválida — use um número de dias.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(automationRulesRepositoryProvider)
          .update(
            widget.rule.messageType,
            enabled: _enabled,
            frequencyDays: frequencyDays,
            title: _hasContent ? _title.text.trim() : null,
            body: _hasContent ? _body.text.trim() : null,
            config: _hasThreshold
                ? {
                    'threshold_percent':
                        int.tryParse(_threshold.text.trim()) ?? 90,
                  }
                : null,
          );
      ref.invalidate(automationRulesProvider);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Salvo.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        backgroundColor: AppTheme.danger,
      ),
    );
  }

  Future<void> _generateTip({AppUser? user}) async {
    setState(() => _generating = true);
    try {
      final generated = await ref
          .read(automationRulesRepositoryProvider)
          .generateTip(userId: user?.id);
      if (!mounted) return;
      setState(() {
        _title.text = generated.title;
        _body.text = generated.body;
        _personalizedUserId = generated.targetUserId;
        _personalizedUserLabel = generated.personalized ? user?.name : null;
        _dirty = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            generated.personalized
                ? 'Dica personalizada gerada. Revise antes de enviar.'
                : 'Nova dica gerada. Revise antes de salvar ou enviar.',
          ),
        ),
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generatePersonalizedTip() async {
    List<AppUser> users;
    try {
      users = (await ref.read(
        dashboardUsersProvider.future,
      )).where((user) => user.isActive).toList();
    } catch (e) {
      _showError(e);
      return;
    }
    if (!mounted) return;
    final user = await showDialog<AppUser>(
      context: context,
      builder: (_) => _TipUserPickerDialog(users: users),
    );
    if (user != null) await _generateTip(user: user);
  }

  Future<void> _sendNow() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha o título e o texto da dica.')),
      );
      return;
    }
    final target = _personalizedUserLabel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar dica agora?'),
        content: Text(
          target == null
              ? 'A dica será enviada agora a todos os usuários elegíveis.'
              : 'Esta dica personalizada será enviada somente para $target.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Enviar agora'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final result = await ref
          .read(automationRulesRepositoryProvider)
          .sendTipNow(title: title, body: body, userId: _personalizedUserId);
      if (!mounted) return;
      ref.invalidate(notificationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.recipientsTotal == 0
                ? 'Envio concluído, mas não havia destinatários elegíveis.'
                : 'Dica enviada para ${result.recipientsTotal} destinatário(s).',
          ),
        ),
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _generating || _sending;
    final enabledForEditing = widget.isSuperuser && !busy;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _typeLabels[widget.rule.messageType] ??
                      widget.rule.messageType,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: _enabled ? 'Ativa' : 'Desativada',
                color: _enabled ? AppTheme.success : AppTheme.gray600,
              ),
              const SizedBox(width: HopeSpacing.sm),
              Switch(
                value: _enabled,
                onChanged: enabledForEditing
                    ? (v) {
                        setState(() => _enabled = v);
                        _markDirty();
                      }
                    : null,
              ),
            ],
          ),
          Text(
            _typeDescriptions[widget.rule.messageType] ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HopeSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _frequency,
                  enabled: enabledForEditing,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _frequencyLabels[widget.rule.messageType],
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              if (_hasThreshold) ...[
                const SizedBox(width: HopeSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _threshold,
                    enabled: enabledForEditing,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Limite do orçamento (%)',
                    ),
                    onChanged: (_) => _markDirty(),
                  ),
                ),
              ],
            ],
          ),
          if (_hasContent) ...[
            const SizedBox(height: HopeSpacing.md),
            TextField(
              controller: _title,
              enabled: enabledForEditing,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Título da mensagem',
              ),
              onChanged: (_) => _markDirty(),
            ),
            TextField(
              controller: _body,
              enabled: enabledForEditing,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Texto da mensagem'),
              onChanged: (_) => _markDirty(),
            ),
            if (widget.rule.messageType == 'tip' &&
                _personalizedUserLabel != null) ...[
              const SizedBox(height: HopeSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.person_rounded, size: 18),
                  label: Text('Personalizada para $_personalizedUserLabel'),
                  tooltip: 'Remover personalização e enviar para todos',
                  onDeleted: busy
                      ? null
                      : () => setState(() {
                          _personalizedUserId = null;
                          _personalizedUserLabel = null;
                        }),
                ),
              ),
            ],
          ],
          const SizedBox(height: HopeSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: HopeSpacing.sm,
            runSpacing: HopeSpacing.sm,
            children: [
              if (widget.rule.messageType == 'tip') ...[
                OutlinedButton.icon(
                  onPressed: enabledForEditing ? () => _generateTip() : null,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Gerar nova dica'),
                ),
                OutlinedButton.icon(
                  onPressed: enabledForEditing
                      ? _generatePersonalizedTip
                      : null,
                  icon: const Icon(Icons.person_search_rounded),
                  label: const Text('Dica personalizada'),
                ),
                FilledButton.tonalIcon(
                  onPressed: enabledForEditing ? _sendNow : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Enviar agora'),
                ),
              ],
              FilledButton.icon(
                onPressed:
                    (widget.isSuperuser &&
                        _dirty &&
                        !busy &&
                        _personalizedUserId == null)
                    ? _save
                    : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  !widget.isSuperuser
                      ? 'Somente superusuário pode editar'
                      : _personalizedUserId != null
                      ? 'Personalizada: use Enviar agora'
                      : 'Salvar',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipUserPickerDialog extends StatefulWidget {
  const _TipUserPickerDialog({required this.users});

  final List<AppUser> users;

  @override
  State<_TipUserPickerDialog> createState() => _TipUserPickerDialogState();
}

class _TipUserPickerDialogState extends State<_TipUserPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final filtered = widget.users
        .where((user) {
          if (normalized.isEmpty) return true;
          return user.name.toLowerCase().contains(normalized) ||
              user.email.toLowerCase().contains(normalized);
        })
        .take(50)
        .toList();

    return AlertDialog(
      title: const Text('Personalizar para um usuário'),
      content: SizedBox(
        width: 520,
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar por nome ou e-mail',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: HopeSpacing.sm),
            Text(
              'A IA usará somente um resumo financeiro agregado. A dica será enviada apenas ao usuário escolhido.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HopeSpacing.sm),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Nenhum usuário encontrado.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final user = filtered[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_rounded),
                          ),
                          title: Text(user.name),
                          subtitle: Text(user.email),
                          onTap: () => Navigator.pop(context, user),
                        );
                      },
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
      ],
    );
  }
}
