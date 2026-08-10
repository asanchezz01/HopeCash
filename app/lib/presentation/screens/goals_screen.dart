import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/finance_calc.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Metas financeiras',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          AppBarPrimaryAction(
            label: 'Meta',
            icon: Icons.add_rounded,
            tooltip: 'Nova meta',
            onPressed: () => _showGoalSheet(context, ref),
          ),
        ],
      ),
      body: goalsAsync.when(
        loading: () => const HopeSkeleton(rows: 4),
        error: (error, _) => HopeErrorState.load(
          error,
          what: 'suas metas',
          onRetry: () => ref.invalidate(goalsProvider),
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return PremiumEmptyState(
              icon: Icons.flag_outlined,
              title: 'Nenhuma meta ainda',
              subtitle:
                  'Reserva de emergência, viagem, entrada do imóvel: uma meta '
                  'transforma o saldo em progresso visível.',
              action: FilledButton.icon(
                onPressed: () => _showGoalSheet(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Criar primeira meta'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, kHopeMinTapTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: HopeSpacing.lg,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              context.pagePadding,
              HopeSpacing.xs,
              context.pagePadding,
              // Espaço para o botão flutuante de lançamento da casca.
              120,
            ),
            itemCount: goals.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _GoalCard(
              goal: goals[index],
              onEdit: () => _showGoalSheet(context, ref, goal: goals[index]),
              onContribution: () => _showGoalMovementSheet(
                context,
                goal: goals[index],
                initialType: 'contribution',
              ),
              onWithdrawal: () => _showGoalMovementSheet(
                context,
                goal: goals[index],
                initialType: 'withdrawal',
              ),
              onMovements: () =>
                  _showGoalMovementsSheet(context, goal: goals[index]),
            ),
          );
        },
      ),
    );
  }

  void _showGoalSheet(BuildContext context, WidgetRef ref, {LocalGoal? goal}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GoalForm(goal: goal),
    );
  }

  void _showGoalMovementSheet(
    BuildContext context, {
    required LocalGoal goal,
    required String initialType,
    LocalTransaction? transaction,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GoalMovementForm(
        goal: goal,
        initialType: initialType,
        transaction: transaction,
      ),
    );
  }

  void _showGoalMovementsSheet(
    BuildContext context, {
    required LocalGoal goal,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GoalMovementsSheet(
        goal: goal,
        onEdit: (transaction) {
          final movement = FinanceRepository.goalMovementLink(transaction);
          _showGoalMovementSheet(
            context,
            goal: goal,
            initialType: movement?.movementType ?? 'contribution',
            transaction: transaction,
          );
        },
      ),
    );
  }
}


class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onEdit,
    required this.onContribution,
    required this.onWithdrawal,
    required this.onMovements,
  });

  final LocalGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onContribution;
  final VoidCallback onWithdrawal;
  final VoidCallback onMovements;

  @override
  Widget build(BuildContext context) {
    final progress = clampProgress(goal.accumulatedAmount, goal.targetAmount);
    final percent = (progress * 100).round();
    final monthly = monthlyContributionNeeded(
      targetAmount: goal.targetAmount,
      accumulatedAmount: goal.accumulatedAmount,
      targetDateIso: goal.targetDate,
    );
    final done = goal.status == 'done' || progress >= 1;
    final late =
        !done &&
        goal.targetDate != null &&
        goal.targetDate!.compareTo(todayIso()) < 0;

    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        (done ? context.hopeColors.success : context.hopeColors.investment).withValues(
                          alpha: 0.14,
                        ),
                    child: Icon(
                      done ? Icons.emoji_events_outlined : Icons.flag_outlined,
                      color: done ? context.hopeColors.success : context.hopeColors.investment,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (goal.targetDate != null)
                          Text(
                            'Alvo: ${formatDate(goal.targetDate)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (late)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.hopeColors.expense.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Atrasada',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.hopeColors.expense,
                        ),
                      ),
                    )
                  else
                    Text(
                      '$percent%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: done ? context.hopeColors.success : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: done ? context.hopeColors.success : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${formatMoney(goal.accumulatedAmount)} de ${formatMoney(goal.targetAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (monthly != null && !done)
                    Text(
                      '${formatMoney(monthly)}/mês',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.hopeColors.investment,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onContribution,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Aporte'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onWithdrawal,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Saque/Transferir'),
                  ),
                  IconButton.outlined(
                    tooltip: 'Movimentações',
                    onPressed: onMovements,
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                  IconButton.outlined(
                    tooltip: 'Editar meta',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalMovementsSheet extends ConsumerWidget {
  const _GoalMovementsSheet({required this.goal, required this.onEdit});

  final LocalGoal goal;
  final ValueChanged<LocalTransaction> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(goalMovementsProvider(goal.id));
    final accounts = {
      for (final a
          in ref.watch(accountsProvider).valueOrNull ?? <LocalAccount>[])
        a.id: a.name,
    };
    final cards = {
      for (final c
          in ref.watch(creditCardsProvider).valueOrNull ?? <LocalCreditCard>[])
        c.id: c.name,
    };
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 20),
        child: movementsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => HopeErrorState.load(
            error,
            what: 'as movimentações desta meta',
            compact: true,
          ),
          data: (movements) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Movimentações',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                goal.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: PremiumEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sem movimentações',
                    subtitle:
                        'Aportes, saques e transferências aparecerão aqui.',
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: movements.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = movements[index];
                      return _GoalMovementTile(
                        transaction: tx,
                        accountName: accounts[tx.accountId],
                        cardName: cards[tx.cardId],
                        onEdit: () => onEdit(tx),
                        onDelete: () =>
                            _confirmDeleteGoalMovement(context, ref, tx),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteGoalMovement(
    BuildContext context,
    WidgetRef ref,
    LocalTransaction transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir movimentação?'),
        content: const Text(
          'O lançamento será removido e o acumulado da meta será ajustado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(financeRepositoryProvider).deleteGoalMovement(transaction);
    ref.read(syncServiceProvider).syncNow();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Movimentação excluída')));
    }
  }
}

class _GoalMovementTile extends StatelessWidget {
  const _GoalMovementTile({
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
    this.accountName,
    this.cardName,
  });

  final LocalTransaction transaction;
  final String? accountName;
  final String? cardName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final movement = FinanceRepository.goalMovementLink(transaction);
    final type = movement?.movementType ?? 'contribution';
    final isWithdrawal = type == 'withdrawal';
    final amount = transaction.amount ?? transaction.amountPlanned ?? 0;
    final color = isWithdrawal ? context.hopeColors.expense : context.hopeColors.success;
    final source = cardName == null ? accountName : 'Cartão $cardName';
    final date = transaction.paymentDate ?? transaction.competenceDate;
    final status = transaction.status == 'planned' ? 'previsto' : 'realizado';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          isWithdrawal ? Icons.remove_circle_outline : Icons.add_circle_outline,
          color: color,
        ),
      ),
      title: Text(isWithdrawal ? 'Saque/Transferência' : 'Aporte'),
      subtitle: Text([formatDate(date), ?source, status].join(' · ')),
      trailing: Wrap(
        spacing: 2,
        children: [
          Text(
            '${isWithdrawal ? '-' : '+'}${formatMoney(amount)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _GoalMovementForm extends ConsumerStatefulWidget {
  const _GoalMovementForm({
    required this.goal,
    required this.initialType,
    this.transaction,
  });

  final LocalGoal goal;
  final String initialType;
  final LocalTransaction? transaction;

  @override
  ConsumerState<_GoalMovementForm> createState() => _GoalMovementFormState();
}

class _GoalMovementFormState extends ConsumerState<_GoalMovementForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String _movementType;
  late String _date;
  String? _paymentKey;
  bool _saving = false;

  bool get _editing => widget.transaction != null;
  bool get _isWithdrawal => _movementType == 'withdrawal';
  bool get _isCard => _paymentKey?.startsWith('card:') ?? false;
  double get _withdrawalLimit {
    final transaction = widget.transaction;
    final movement = transaction == null
        ? null
        : FinanceRepository.goalMovementLink(transaction);
    final oldAmount = transaction == null
        ? 0.0
        : transaction.amount ?? transaction.amountPlanned ?? 0;
    final available =
        widget.goal.accumulatedAmount -
        (movement?.movementType == 'contribution' ? oldAmount : 0) +
        (movement?.movementType == 'withdrawal' ? oldAmount : 0);
    return available < 0 ? 0 : available;
  }

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    final movement = transaction == null
        ? null
        : FinanceRepository.goalMovementLink(transaction);
    _movementType = movement?.movementType ?? widget.initialType;
    _date =
        transaction?.paymentDate ?? transaction?.competenceDate ?? todayIso();
    final amount = transaction?.amount ?? transaction?.amountPlanned;
    if (amount != null) {
      _amount.text = amount.toStringAsFixed(2).replaceAll('.', ',');
    }
    if (transaction?.cardId != null) {
      _paymentKey = 'card:${transaction!.cardId}';
    } else if (transaction?.accountId != null) {
      _paymentKey = 'account:${transaction!.accountId}';
    } else if (widget.goal.linkedAccountId != null) {
      _paymentKey = 'account:${widget.goal.linkedAccountId}';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final key = _paymentKey;
    if (key == null) return;
    setState(() => _saving = true);
    final cards = ref.read(creditCardsProvider).valueOrNull ?? [];
    final card = key.startsWith('card:')
        ? cards.firstWhere((c) => c.id == key.substring('card:'.length))
        : null;
    await ref
        .read(financeRepositoryProvider)
        .upsertGoalMovement(
          goal: widget.goal,
          transaction: widget.transaction,
          movementType: _movementType,
          amount: parseMoney(_amount.text)!,
          date: _date,
          accountId: key.startsWith('account:')
              ? key.substring('account:'.length)
              : null,
          card: card,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isWithdrawal
                ? 'Saque/transferência registrado'
                : 'Aporte registrado',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = (ref.watch(accountsProvider).valueOrNull ?? [])
        .where(
          (account) =>
              account.isActive || account.id == widget.goal.linkedAccountId,
        )
        .toList();
    final selectedCardId = _paymentKey?.startsWith('card:') ?? false
        ? _paymentKey!.substring('card:'.length)
        : null;
    final cards = (ref.watch(creditCardsProvider).valueOrNull ?? [])
        .where((card) => card.isActive || card.id == selectedCardId)
        .toList();

    return PremiumFormSheet(
      title: _editing
          ? 'Editar movimentação'
          : _isWithdrawal
          ? 'Saque/Transferência'
          : 'Novo aporte',
      subtitle: widget.goal.name,
      icon: _isWithdrawal
          ? Icons.remove_circle_outline
          : Icons.add_circle_outline,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Movimentação',
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'contribution',
                  label: Text('Aporte'),
                  icon: Icon(Icons.add_circle_outline),
                ),
                ButtonSegment(
                  value: 'withdrawal',
                  label: Text('Saque'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
              ],
              selected: {_movementType},
              onSelectionChanged: _saving
                  ? null
                  : (value) => setState(() => _movementType = value.first),
            ),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final parsed = value == null ? null : parseMoney(value);
                if (parsed == null || parsed <= 0) {
                  return 'Informe um valor válido';
                }
                if (_isWithdrawal && parsed > _withdrawalLimit) {
                  return 'Valor maior que o acumulado';
                }
                return null;
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _paymentKey,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _isWithdrawal ? 'Transferir para' : 'Registrar em',
                prefixIcon: Icon(
                  _isCard
                      ? Icons.credit_card_outlined
                      : Icons.account_balance_outlined,
                ),
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: 'account:${account.id}',
                    child: Text(account.name, overflow: TextOverflow.ellipsis),
                  ),
                for (final card in cards)
                  DropdownMenuItem(
                    value: 'card:${card.id}',
                    child: Text(
                      'Cartão ${card.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _paymentKey = value),
              validator: (value) =>
                  value == null ? 'Escolha uma conta ou cartão' : null,
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Data: ${formatDate(_date)}'),
            ),
          ],
        ),
      ],
      secondaryAction: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: const Text('Salvar'),
      ),
    );
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({this.goal});

  final LocalGoal? goal;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _accumulated = TextEditingController();
  String? _targetDate;
  bool _saving = false;

  bool get _editing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _name.text = goal?.name ?? '';
    _target.text = goal == null
        ? ''
        : goal.targetAmount.toStringAsFixed(2).replaceAll('.', ',');
    _accumulated.text = goal == null
        ? ''
        : goal.accumulatedAmount.toStringAsFixed(2).replaceAll('.', ',');
    _targetDate = goal?.targetDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _accumulated.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate != null
          ? DateTime.parse(_targetDate!)
          : DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _targetDate = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final target = parseMoney(_target.text)!;
    final accumulated = parseMoney(_accumulated.text) ?? 0;
    await ref
        .read(financeRepositoryProvider)
        .upsertGoal(
          id: widget.goal?.id,
          name: _name.text.trim(),
          targetAmount: target,
          targetDate: _targetDate,
          accumulatedAmount: accumulated,
          status: accumulated >= target ? 'done' : 'active',
          currentVersion: widget.goal?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editing ? 'Meta atualizada' : 'Meta criada')),
      );
    }
  }

  Future<void> _delete() async {
    final goal = widget.goal;
    if (goal == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir meta?'),
        content: Text('A meta "${goal.name}" será removida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(financeRepositoryProvider).deleteGoal(goal);
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meta excluída')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthly = monthlyContributionNeeded(
      targetAmount: parseMoney(_target.text) ?? 0,
      accumulatedAmount: parseMoney(_accumulated.text) ?? 0,
      targetDateIso: _targetDate,
    );
    return PremiumFormSheet(
      title: _editing ? 'Editar meta' : 'Nova meta',
      subtitle: 'Defina o objetivo, o valor alvo e o ritmo necessário.',
      icon: Icons.flag_outlined,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Objetivo',
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome da meta',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Valores',
          children: [
            TextFormField(
              controller: _target,
              decoration: const InputDecoration(
                labelText: 'Valor objetivo',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final parsed = v == null ? null : parseMoney(v);
                return (parsed == null || parsed <= 0)
                    ? 'Informe um valor válido'
                    : null;
              },
            ),
            TextFormField(
              controller: _accumulated,
              decoration: const InputDecoration(
                labelText: 'Valor já acumulado',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.savings_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Prazo',
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                _targetDate == null
                    ? 'Definir data alvo (opcional)'
                    : 'Data alvo: ${formatDate(_targetDate)}',
              ),
            ),
            if (monthly != null)
              AppSurface(
                color: context.hopeColors.investment.withValues(alpha: 0.10),
                borderColor: context.hopeColors.investment.withValues(alpha: 0.18),
                child: Row(
                  children: [
                    Icon(
                      Icons.calculate_outlined,
                      color: context.hopeColors.investment,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Aporte necessário: ${formatMoney(monthly)} por mês para atingir a meta no prazo.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
      secondaryAction: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: const Text('Salvar meta'),
      ),
      destructiveAction: _editing
          ? TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: context.hopeColors.expense),
              label: const Text('Excluir meta'),
              style: TextButton.styleFrom(foregroundColor: context.hopeColors.expense),
            )
          : null,
    );
  }
}
