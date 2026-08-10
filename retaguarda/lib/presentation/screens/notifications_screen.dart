import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_user.dart';
import '../../data/models/push_campaign.dart';
import '../components/hope_components.dart';

const _categoryLabels = {
  'general': 'Geral',
  'tips': 'Dicas',
  'insights': 'Insights financeiros',
  'maintenance': 'Manutenção',
  'promo': 'Promoção',
};

const _statusLabels = {
  'draft': 'Rascunho',
  'scheduled': 'Agendada',
  'processing': 'Processando',
  'sent': 'Enviada',
  'partially_sent': 'Parc. enviada',
  'canceled': 'Cancelada',
  'failed': 'Falhou',
};

const _statusColors = {
  'draft': AppTheme.gray600,
  'scheduled': AppTheme.skyBlue,
  'processing': AppTheme.warning,
  'sent': AppTheme.success,
  'partially_sent': AppTheme.warning,
  'canceled': AppTheme.gray600,
  'failed': AppTheme.danger,
};

const _deliveryModeLabels = {
  'push': 'Push',
  'email': 'E-mail',
  'both': 'Push + E-mail',
  'none': 'Sem entrega',
};

// Espelha backend/src/modules/push/deepLinks.js — só destinos conhecidos do app.
const _allowedDeepLinks = {
  null: 'Nenhum',
  '/': 'Início',
  '/transactions': 'Lançamentos',
  '/accounts': 'Contas',
  '/more': 'Mais',
  '/more/credit-cards': 'Cartões de crédito',
  '/more/budget': 'Orçamento',
  '/more/goals': 'Metas',
  '/more/debts': 'Dívidas',
  '/more/investments': 'Investimentos',
  '/ai-chat': 'Chat com a Hope',
};

/// Painel de campanhas de notificação multicanal — criar, agendar, enviar,
/// cancelar, reprocessar falhas e acompanhar estatísticas.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(notificationsProvider);
    final statusFilter = ref.watch(notificationsStatusFilterProvider);
    final isSuperuser = ref.watch(authStateProvider)?.isSuperuser ?? false;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(HopeSpacing.xl),
            child: PageHeader(
              title: 'Notificações',
              subtitle:
                  'Campanhas por push e e-mail enviadas ou agendadas pela retaguarda.',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/notifications/automation'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Mensagens automáticas'),
                ),
                const SizedBox(width: HopeSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _openForm(context, ref),
                  icon: const Icon(Icons.add_alert_outlined),
                  label: const Text('Nova campanha'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HopeSpacing.xl),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'Todas',
                    selected: statusFilter == null,
                    onTap: () =>
                        ref
                                .read(
                                  notificationsStatusFilterProvider.notifier,
                                )
                                .state =
                            null,
                  ),
                  for (final entry in _statusLabels.entries)
                    Padding(
                      padding: const EdgeInsets.only(left: HopeSpacing.xs),
                      child: _FilterChip(
                        label: entry.value,
                        selected: statusFilter == entry.key,
                        onTap: () =>
                            ref
                                .read(
                                  notificationsStatusFilterProvider.notifier,
                                )
                                .state = entry
                                .key,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HopeSpacing.sm),
          Expanded(
            child: campaigns.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Não foi possível carregar',
                subtitle: e.toString(),
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(notificationsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ),
              data: (page) {
                if (page.campaigns.isEmpty) {
                  return EmptyState(
                    icon: Icons.notifications_outlined,
                    title: 'Nenhuma campanha ainda',
                    subtitle: 'Crie a primeira campanha de notificação push.',
                    action: FilledButton.icon(
                      onPressed: () => _openForm(context, ref),
                      icon: const Icon(Icons.add_alert_outlined),
                      label: const Text('Nova campanha'),
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
                          for (var i = 0; i < page.campaigns.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _CampaignRow(
                              campaign: page.campaigns[i],
                              isSuperuser: isSuperuser,
                              onEdit: page.campaigns[i].isEditable
                                  ? () => _openForm(
                                      context,
                                      ref,
                                      campaign: page.campaigns[i],
                                    )
                                  : null,
                              onStats: () =>
                                  _openStats(context, ref, page.campaigns[i]),
                              onRecipients: () =>
                                  _openRecipients(context, page.campaigns[i]),
                              onSend: page.campaigns[i].isSendable
                                  ? () => _confirmSend(
                                      context,
                                      ref,
                                      page.campaigns[i],
                                    )
                                  : null,
                              onSchedule: page.campaigns[i].status == 'draft'
                                  ? () => _openSchedule(
                                      context,
                                      ref,
                                      page.campaigns[i],
                                    )
                                  : null,
                              onCancel: page.campaigns[i].isCancelable
                                  ? () => _confirmCancel(
                                      context,
                                      ref,
                                      page.campaigns[i],
                                    )
                                  : null,
                              onResend: page.campaigns[i].canResend
                                  ? () => _confirmResend(
                                      context,
                                      ref,
                                      page.campaigns[i],
                                    )
                                  : null,
                              onDelete: page.campaigns[i].canDelete
                                  ? () => _confirmDelete(
                                      context,
                                      ref,
                                      page.campaigns[i],
                                    )
                                  : null,
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
    WidgetRef ref, {
    PushCampaign? campaign,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CampaignFormDialog(campaign: campaign),
    );
    if (saved == true) ref.invalidate(notificationsProvider);
  }

  Future<void> _openSchedule(
    BuildContext context,
    WidgetRef ref,
    PushCampaign campaign,
  ) async {
    final scheduled = await showDialog<bool>(
      context: context,
      builder: (_) => _ScheduleDialog(campaign: campaign),
    );
    if (scheduled == true) ref.invalidate(notificationsProvider);
  }

  Future<void> _openStats(
    BuildContext context,
    WidgetRef ref,
    PushCampaign campaign,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _StatsDialog(campaignId: campaign.id),
    );
    if (changed == true) ref.invalidate(notificationsProvider);
  }

  Future<void> _openRecipients(
    BuildContext context,
    PushCampaign campaign,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RecipientsDialog(campaign: campaign),
    );
  }

  Future<void> _confirmSend(
    BuildContext context,
    WidgetRef ref,
    PushCampaign campaign,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar agora?'),
        content: Text(
          'A campanha "${campaign.title}" será enviada imediatamente para '
          'os destinatários elegíveis. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(notificationsRepositoryProvider).sendNow(campaign.id);
      ref.invalidate(notificationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Campanha enviada.')));
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    PushCampaign campaign,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar campanha?'),
        content: Text('Cancelar "${campaign.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar campanha'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(notificationsRepositoryProvider).cancel(campaign.id);
      ref.invalidate(notificationsProvider);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _confirmResend(
    BuildContext context,
    WidgetRef ref,
    PushCampaign campaign,
  ) async {
    var selectedChannel = 'both';
    final channel = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reenviar campanha'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Uma nova campanha idêntica a "${campaign.title}" será criada. '
                  'Escolha os canais do reenvio:',
                ),
                const SizedBox(height: HopeSpacing.md),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'both',
                      icon: Icon(Icons.devices_rounded),
                      label: Text('Ambos'),
                    ),
                    ButtonSegment(
                      value: 'push',
                      icon: Icon(Icons.notifications_rounded),
                      label: Text('Push'),
                    ),
                    ButtonSegment(
                      value: 'email',
                      icon: Icon(Icons.email_rounded),
                      label: Text('E-mail'),
                    ),
                  ],
                  selected: {selectedChannel},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => selectedChannel = selection.first),
                ),
                const SizedBox(height: HopeSpacing.sm),
                Text(
                  'As preferências atuais de cada usuário serão respeitadas.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedChannel),
              child: const Text('Reenviar'),
            ),
          ],
        ),
      ),
    );
    if (channel == null) return;
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .resend(campaign.id, channel: channel);
      ref.invalidate(notificationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Campanha reenviada como uma nova campanha.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PushCampaign campaign,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir campanha?'),
        content: Text(
          'Excluir "${campaign.title}" e todo o histórico de entregas dela? '
          'Esta ação não pode ser desfeita.',
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
      await ref.read(notificationsRepositoryProvider).delete(campaign.id);
      ref.invalidate(notificationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Campanha excluída.')));
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }
}

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _CampaignRow extends StatelessWidget {
  const _CampaignRow({
    required this.campaign,
    required this.isSuperuser,
    this.onEdit,
    required this.onStats,
    required this.onRecipients,
    this.onSend,
    this.onSchedule,
    this.onCancel,
    this.onResend,
    this.onDelete,
  });

  final PushCampaign campaign;
  final bool isSuperuser;
  final VoidCallback? onEdit;
  final VoidCallback onStats;
  final VoidCallback onRecipients;
  final VoidCallback? onSend;
  final VoidCallback? onSchedule;
  final VoidCallback? onCancel;
  final VoidCallback? onResend;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.md,
        vertical: HopeSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        campaign.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: HopeSpacing.xs),
                    StatusBadge(
                      label: _statusLabels[campaign.status] ?? campaign.status,
                      color: _statusColors[campaign.status] ?? AppTheme.gray600,
                    ),
                    if (campaign.deliveryMode != 'none') ...[
                      const SizedBox(width: HopeSpacing.xs),
                      _DeliveryModeBadge(mode: campaign.deliveryMode),
                    ],
                  ],
                ),
                Text(
                  campaign.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: HopeSpacing.sm,
                  runSpacing: 4,
                  children: [
                    Text(
                      _categoryLabels[campaign.category] ?? campaign.category,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      campaign.audience == 'selected'
                          ? '${campaign.targetUserIds.length} selecionado(s)'
                          : 'Todos os usuários',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (campaign.scheduledAt != null)
                      Text(
                        'Agendada: ${campaign.scheduledAt} UTC',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (campaign.status != 'draft')
                      Text(
                        'Destinatários: ${campaign.recipientsTotal}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (campaign.pushDelivery.total > 0)
                      Text(
                        'Push: ${campaign.pushDelivery.sent}/${campaign.pushDelivery.total} confirmadas',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (campaign.emailDelivery.total > 0)
                      Text(
                        'E-mail: ${campaign.emailDelivery.sent}/${campaign.emailDelivery.total} confirmadas',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: HopeSpacing.sm),
          Wrap(
            spacing: 0,
            children: [
              IconButton(
                tooltip: 'Estatísticas',
                onPressed: onStats,
                icon: const Icon(Icons.bar_chart_outlined),
              ),
              IconButton(
                tooltip: 'Consultar destinatários',
                onPressed: onRecipients,
                icon: const Icon(Icons.group_outlined),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (onSchedule != null)
                IconButton(
                  tooltip: isSuperuser
                      ? 'Agendar'
                      : 'Somente superusuário pode agendar',
                  onPressed: isSuperuser ? onSchedule : null,
                  icon: const Icon(Icons.schedule_outlined),
                ),
              if (onSend != null)
                IconButton(
                  tooltip: isSuperuser
                      ? 'Enviar agora'
                      : 'Somente superusuário pode enviar',
                  onPressed: isSuperuser ? onSend : null,
                  icon: const Icon(Icons.send_outlined),
                ),
              if (onCancel != null)
                IconButton(
                  tooltip: isSuperuser
                      ? 'Cancelar'
                      : 'Somente superusuário pode cancelar',
                  onPressed: isSuperuser ? onCancel : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              if (onResend != null)
                IconButton(
                  tooltip: isSuperuser
                      ? 'Reenviar (nova campanha)'
                      : 'Somente superusuário pode reenviar',
                  onPressed: isSuperuser ? onResend : null,
                  icon: const Icon(Icons.replay_rounded),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: isSuperuser
                      ? 'Excluir'
                      : 'Somente superusuário pode excluir',
                  onPressed: isSuperuser ? onDelete : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: isSuperuser ? AppTheme.danger : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryModeBadge extends StatelessWidget {
  const _DeliveryModeBadge({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      'push' => Icons.notifications_rounded,
      'email' => Icons.email_rounded,
      _ => Icons.devices_rounded,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 15),
      label: Text(_deliveryModeLabels[mode] ?? mode),
      labelStyle: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _CampaignFormDialog extends ConsumerStatefulWidget {
  const _CampaignFormDialog({this.campaign});

  final PushCampaign? campaign;

  @override
  ConsumerState<_CampaignFormDialog> createState() =>
      _CampaignFormDialogState();
}

class _CampaignFormDialogState extends ConsumerState<_CampaignFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'general';
  String _audience = 'all';
  String? _deepLink;
  final Map<String, AppUser> _selectedUsers = {};
  bool _saving = false;
  bool _previewing = false;
  String? _error;
  PushCampaignPreview? _preview;

  bool get _isEdit => widget.campaign != null;

  @override
  void initState() {
    super.initState();
    final c = widget.campaign;
    _title.text = c?.title ?? '';
    _body.text = c?.body ?? '';
    _category = c?.category ?? 'general';
    _audience = c?.audience ?? 'all';
    _deepLink = c?.deepLink;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickUsers() async {
    final result = await showDialog<Map<String, AppUser>>(
      context: context,
      builder: (_) => _UserPickerDialog(initiallySelected: _selectedUsers),
    );
    if (result != null) {
      setState(
        () => _selectedUsers
          ..clear()
          ..addAll(result),
      );
    }
  }

  /// Id da campanha já persistida nesta sessão do diálogo — a original (modo
  /// edição) ou a que a própria "Prévia" criou como rascunho (modo criação).
  /// Garante que clicar em "Prévia" várias vezes edite a mesma campanha em
  /// vez de criar rascunhos duplicados a cada clique.
  String? _persistedId;

  Future<PushCampaign?> _persist() async {
    if (_audience == 'selected' && _selectedUsers.isEmpty) {
      setState(() => _error = 'Selecione ao menos um usuário.');
      return null;
    }
    final repo = ref.read(notificationsRepositoryProvider);
    final existingId = widget.campaign?.id ?? _persistedId;
    final result = existingId != null
        ? await repo.update(
            existingId,
            title: _title.text.trim(),
            body: _body.text.trim(),
            category: _category,
            audience: _audience,
            targetUserIds: _selectedUsers.keys.toList(),
            deepLink: _deepLink,
          )
        : await repo.create(
            title: _title.text.trim(),
            body: _body.text.trim(),
            category: _category,
            audience: _audience,
            targetUserIds: _selectedUsers.keys.toList(),
            deepLink: _deepLink,
          );
    _persistedId = result.id;
    return result;
  }

  Future<void> _runPreview() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      // A prévia real só existe depois de salvo — salva/atualiza o rascunho
      // primeiro e então consulta a prévia com os dados atuais.
      final saved = await _persist();
      if (saved == null) return;
      final preview = await ref
          .read(notificationsRepositoryProvider)
          .preview(saved.id);
      setState(() => _preview = preview);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _persist();
      if (result == null) return;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Editar campanha' : 'Nova campanha'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o título'
                      : null,
                ),
                TextFormField(
                  controller: _body,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Mensagem'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe a mensagem'
                      : null,
                ),
                const SizedBox(height: HopeSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [
                    for (final entry in _categoryLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'general'),
                ),
                const SizedBox(height: HopeSpacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: _deepLink,
                  decoration: const InputDecoration(
                    labelText: 'Abrir ao tocar (deep link)',
                  ),
                  items: [
                    for (final entry in _allowedDeepLinks.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) => setState(() => _deepLink = v),
                ),
                const SizedBox(height: HopeSpacing.md),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'all',
                      label: Text('Todos os usuários'),
                    ),
                    ButtonSegment(
                      value: 'selected',
                      label: Text('Selecionados'),
                    ),
                  ],
                  selected: {_audience},
                  onSelectionChanged: (s) =>
                      setState(() => _audience = s.first),
                ),
                if (_audience == 'selected') ...[
                  const SizedBox(height: HopeSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _pickUsers,
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(
                      _selectedUsers.isEmpty
                          ? 'Selecionar usuários'
                          : '${_selectedUsers.length} usuário(s) selecionado(s)',
                    ),
                  ),
                ],
                if (_preview != null) ...[
                  const SizedBox(height: HopeSpacing.md),
                  AppSurface(
                    child: Text(
                      '${_preview!.recipientsTotal} destinatário(s) · '
                      '${_preview!.devicesTotal} push · '
                      '${_preview!.emailTotal} e-mail(s) '
                      '(web ${_preview!.byPlatform['web'] ?? 0}, '
                      'pwa ${_preview!.byPlatform['pwa'] ?? 0}, '
                      'android ${_preview!.byPlatform['android'] ?? 0}, '
                      'ios ${_preview!.byPlatform['ios'] ?? 0})',
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: HopeSpacing.md),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        OutlinedButton.icon(
          onPressed: (_saving || _previewing) ? null : _runPreview,
          icon: _previewing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_outlined),
          label: const Text('Prévia'),
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
          label: Text(_persistedId != null ? 'Salvar' : 'Criar rascunho'),
        ),
      ],
    );
  }
}

/// Seleção de usuários (audiência "selected") com busca paginada.
class _UserPickerDialog extends ConsumerStatefulWidget {
  const _UserPickerDialog({required this.initiallySelected});

  final Map<String, AppUser> initiallySelected;

  @override
  ConsumerState<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends ConsumerState<_UserPickerDialog> {
  final _search = TextEditingController();
  late final Map<String, AppUser> _selected = Map.of(widget.initiallySelected);
  List<AppUser> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _query(String search) async {
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(appUsersRepositoryProvider)
          .list(search: search, status: 'active', limit: 50);
      if (mounted) setState(() => _results = page.users);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar usuários'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar por nome ou e-mail',
              ),
              onSubmitted: _query,
            ),
            const SizedBox(height: HopeSpacing.sm),
            if (_selected.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${_selected.length} selecionado(s)'),
              ),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final user in _results)
                          CheckboxListTile(
                            value: _selected.containsKey(user.id),
                            title: Text(user.name),
                            subtitle: Text(user.email),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected[user.id] = user;
                              } else {
                                _selected.remove(user.id);
                              }
                            }),
                          ),
                      ],
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
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

const _timezoneOptions = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Bahia',
  'America/Fortaleza',
  'America/Recife',
  'America/Cuiaba',
  'America/Rio_Branco',
  'America/Belem',
];

class _ScheduleDialog extends ConsumerStatefulWidget {
  const _ScheduleDialog({required this.campaign});

  final PushCampaign campaign;

  @override
  ConsumerState<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  DateTime? _date;
  TimeOfDay? _time;
  String _timezone = 'America/Sao_Paulo';
  bool _saving = false;
  String? _error;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_date == null || _time == null) {
      setState(() => _error = 'Escolha a data e o horário.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final date =
          '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';
      final time =
          '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';
      await ref
          .read(notificationsRepositoryProvider)
          .schedule(
            widget.campaign.id,
            date: date,
            time: time,
            timezone: _timezone,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Agendar "${widget.campaign.title}"'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                _date == null
                    ? 'Escolher data'
                    : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}',
              ),
            ),
            const SizedBox(height: HopeSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time_outlined),
              label: Text(
                _time == null ? 'Escolher horário' : _time!.format(context),
              ),
            ),
            const SizedBox(height: HopeSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _timezone,
              decoration: const InputDecoration(labelText: 'Fuso horário'),
              items: [
                for (final tz in _timezoneOptions)
                  DropdownMenuItem(value: tz, child: Text(tz)),
              ],
              onChanged: (v) => setState(() => _timezone = v ?? _timezone),
            ),
            if (_error != null) ...[
              const SizedBox(height: HopeSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Agendar'),
        ),
      ],
    );
  }
}

class _RecipientsDialog extends ConsumerStatefulWidget {
  const _RecipientsDialog({required this.campaign});

  final PushCampaign campaign;

  @override
  ConsumerState<_RecipientsDialog> createState() => _RecipientsDialogState();
}

class _RecipientsDialogState extends ConsumerState<_RecipientsDialog> {
  static const _pageSize = 100;

  final List<PushCampaignRecipient> _recipients = [];
  int _total = 0;
  int _nextPage = 1;
  String _source = 'current_eligibility';
  bool _loading = true;
  Object? _error;

  bool get _hasMore => _recipients.length < _total;

  @override
  void initState() {
    super.initState();
    _loadMore(initial: true);
  }

  Future<void> _loadMore({bool initial = false}) async {
    if (!initial && _loading) return;
    if (!initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await ref
          .read(notificationsRepositoryProvider)
          .recipients(widget.campaign.id, page: _nextPage, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _recipients.addAll(page.recipients);
        _total = page.total;
        _source = page.source;
        _nextPage += 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _source == 'delivery_history'
        ? 'Nomes registrados no histórico de entregas desta campanha.'
        : 'Destinatários elegíveis agora. A lista pode mudar até o envio.';
    return AlertDialog(
      title: Text('Destinatários — ${widget.campaign.title}'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HopeSpacing.sm),
            Text(
              '$_total destinatário(s)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: HopeSpacing.sm),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading && _recipients.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _recipients.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Não foi possível carregar os destinatários.\n$_error'),
            const SizedBox(height: HopeSpacing.sm),
            OutlinedButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (_recipients.isEmpty) {
      return const Center(child: Text('Nenhum destinatário encontrado.'));
    }
    return ListView.separated(
      itemCount: _recipients.length + (_hasMore || _error != null ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == _recipients.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: HopeSpacing.sm),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: Icon(
                        _error == null
                            ? Icons.expand_more_rounded
                            : Icons.refresh_rounded,
                      ),
                      label: Text(
                        _error == null ? 'Carregar mais' : 'Tentar novamente',
                      ),
                    ),
            ),
          );
        }
        final recipient = _recipients[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.person_outline_rounded),
          title: Text(recipient.name),
        );
      },
    );
  }
}

class _StatsDialog extends ConsumerWidget {
  const _StatsDialog({required this.campaignId});

  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Estatísticas da campanha'),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<PushCampaignStats>(
          future: ref.read(notificationsRepositoryProvider).stats(campaignId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text('${snapshot.error}');
            }
            final stats = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: HopeSpacing.sm,
                    runSpacing: HopeSpacing.sm,
                    children: [
                      _StatChip(label: 'Pendentes', value: stats.pending),
                      _StatChip(label: 'Enviando', value: stats.sending),
                      _StatChip(
                        label: 'Confirmadas',
                        value: stats.sent,
                        color: AppTheme.success,
                      ),
                      _StatChip(
                        label: 'Falhas',
                        value: stats.failed,
                        color: AppTheme.danger,
                      ),
                    ],
                  ),
                  if (stats.campaign.pushDelivery.total > 0 ||
                      stats.campaign.emailDelivery.total > 0) ...[
                    const SizedBox(height: HopeSpacing.md),
                    Text(
                      'Confirmação por canal',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: HopeSpacing.xs),
                    Wrap(
                      spacing: HopeSpacing.sm,
                      runSpacing: HopeSpacing.sm,
                      children: [
                        if (stats.campaign.pushDelivery.total > 0)
                          _ChannelStatChip(
                            label: 'Push',
                            icon: Icons.notifications_rounded,
                            stats: stats.campaign.pushDelivery,
                          ),
                        if (stats.campaign.emailDelivery.total > 0)
                          _ChannelStatChip(
                            label: 'E-mail',
                            icon: Icons.email_rounded,
                            stats: stats.campaign.emailDelivery,
                          ),
                      ],
                    ),
                  ],
                  if (stats.failures.isNotEmpty) ...[
                    const SizedBox(height: HopeSpacing.md),
                    Text(
                      'Falhas recentes',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: HopeSpacing.xs),
                    for (final f in stats.failures.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${_deliveryModeLabels[f.channel] ?? f.channel}: '
                          '${f.error ?? "erro desconhecido"} '
                          '(tentativas: ${f.attempts})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              final reset = await ref
                  .read(notificationsRepositoryProvider)
                  .reprocess(campaignId);
              if (context.mounted) {
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$reset entrega(s) reprocessada(s).')),
                );
              }
            } catch (e) {
              if (context.mounted) _showError(context, e);
            }
          },
          child: const Text('Reprocessar falhas'),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: color?.withValues(alpha: 0.12),
      labelStyle: color != null ? TextStyle(color: color) : null,
    );
  }
}

class _ChannelStatChip extends StatelessWidget {
  const _ChannelStatChip({
    required this.label,
    required this.icon,
    required this.stats,
  });

  final String label;
  final IconData icon;
  final DeliveryChannelStats stats;

  @override
  Widget build(BuildContext context) {
    final complete = stats.total > 0 && stats.sent == stats.total;
    final color = complete ? AppTheme.success : AppTheme.warning;
    return Chip(
      avatar: Icon(icon, size: 17, color: color),
      label: Text('$label: ${stats.sent}/${stats.total} confirmadas'),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color),
    );
  }
}
