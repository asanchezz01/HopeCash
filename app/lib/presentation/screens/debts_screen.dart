import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/finance_calc.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import '../widgets/debt_payment_sheet.dart';
import '../widgets/edit_transaction_sheet.dart';
import '../widgets/quick_create_category.dart';
import '../widgets/searchable_category_field.dart';

const _debtTypes = {
  'loan': 'Empréstimo',
  'financing': 'Financiamento',
  'installment_plan': 'Parcelamento',
};

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(debtsProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? [];
    final subcategories = ref.watch(subcategoriesProvider).valueOrNull ?? [];
    final transactions = ref.watch(transactionsProvider).valueOrNull ?? [];
    final repo = ref.watch(financeRepositoryProvider);
    final accountNames = {
      for (final account in accounts) account.id: account.name,
    };
    final categoryNames = {
      for (final category in categories) category.id: category.name,
    };
    final subcategoryNames = {
      for (final subcategory in subcategories) subcategory.id: subcategory.name,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dívidas e financiamentos',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          AppBarPrimaryAction(
            label: 'Dívida',
            icon: Icons.add_rounded,
            tooltip: 'Nova dívida',
            onPressed: () => _showDebtSheet(context, ref),
          ),
        ],
      ),
      body: debtsAsync.when(
        loading: () => const HopeSkeleton(rows: 4),
        error: (error, _) => HopeErrorState.load(
          error,
          what: 'suas dívidas',
          onRetry: () => ref.invalidate(debtsProvider),
        ),
        data: (debts) {
          final active = debts.where((d) => d.status == 'active').toList();
          final totalOutstanding = active.fold<double>(
            0,
            (s, d) => s + d.outstandingBalance,
          );
          final monthlyCommitment = active.fold<double>(
            0,
            (sum, debt) =>
                sum +
                (debt.installmentAmount > 0
                    ? debt.installmentAmount
                    : repo.nextOpenDebtInstallment(debt, transactions)?.amount ??
                        0),
          );
          final linkedBudgetCount = active
              .where(
                (debt) =>
                    debt.budgetItemId != null && debt.budgetItemId!.isNotEmpty,
              )
              .length;
          if (debts.isEmpty) {
            return PremiumEmptyState(
              icon: Icons.trending_down_outlined,
              title: 'Nenhuma dívida cadastrada',
              subtitle:
                  'Acompanhe empréstimos, financiamentos e parcelamentos em um só lugar.',
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
              context.pagePadding,
              HopeSpacing.xs,
              context.pagePadding,
              // Espaço para o botão flutuante de lançamento da casca.
              120,
            ),
            children: [
              _DebtSummaryPanel(
                totalOutstanding: totalOutstanding,
                activeCount: active.length,
                monthlyCommitment: monthlyCommitment,
                linkedBudgetCount: linkedBudgetCount,
              ),
              const SizedBox(height: 14),
              for (final debt in debts) ...[
                _DebtCard(
                  debt: debt,
                  next: repo.nextOpenDebtInstallment(debt, transactions),
                  accountName: accountNames[debt.accountId],
                  categoryName: categoryNames[debt.categoryId],
                  subcategoryName: subcategoryNames[debt.subcategoryId],
                  onEdit: () => _showDebtSheet(context, ref, debt: debt),
                  onPay: () => _showDirectDebtPayment(context, ref, debt),
                  onPayments: () => _showDebtPaymentsSheet(context, ref, debt),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showDebtSheet(BuildContext context, WidgetRef ref, {LocalDebt? debt}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DebtForm(debt: debt),
    );
  }
}

class _DebtSummaryPanel extends StatelessWidget {
  const _DebtSummaryPanel({
    required this.totalOutstanding,
    required this.activeCount,
    required this.monthlyCommitment,
    required this.linkedBudgetCount,
  });

  final double totalOutstanding;
  final int activeCount;
  final double monthlyCommitment;
  final int linkedBudgetCount;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FinanceIconBadge(
                icon: Icons.trending_down_outlined,
                color: context.hopeColors.expense,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo devedor total',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '$activeCount ativas · $linkedBudgetCount no orçamento',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              MoneyText(
                totalOutstanding,
                emphasis: MoneyEmphasis.primary,
                color: context.hopeColors.expense,
                semanticsPrefix: 'Saldo devedor total',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DebtMetricGrid(
            metrics: [
              _DebtMetricData(
                label: 'Compromisso mensal',
                value: formatMoney(monthlyCommitment),
                icon: Icons.event_repeat_outlined,
              ),
              _DebtMetricData(
                label: 'Dívidas ativas',
                value: '$activeCount',
                icon: Icons.format_list_numbered_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.debt,
    required this.next,
    required this.onEdit,
    required this.onPay,
    required this.onPayments,
    this.accountName,
    this.categoryName,
    this.subcategoryName,
  });

  final LocalDebt debt;
  final DebtInstallmentPreview? next;
  final VoidCallback onEdit;
  final VoidCallback onPay;
  final VoidCallback onPayments;
  final String? accountName;
  final String? categoryName;
  final String? subcategoryName;

  @override
  Widget build(BuildContext context) {
    final paidOff = debt.status == 'paid_off';
    final nextInstallment = next;
    final progress = debt.totalInstallments > 0
        ? clampProgress(
            debt.paidInstallments.toDouble(),
            debt.totalInstallments.toDouble(),
          )
        : 0.0;
    final linkedBudget =
        debt.budgetItemId != null && debt.budgetItemId!.isNotEmpty;
    final classification = [?categoryName, ?subcategoryName].join(' · ');

    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FinanceIconBadge(
                icon: _debtIcon(debt.type),
                color: paidOff ? context.hopeColors.success : context.hopeColors.warning,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _debtTypes[debt.type] ?? debt.type,
                        if (debt.institution != null &&
                            debt.institution!.isNotEmpty)
                          debt.institution!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DebtStatusPill(paidOff: paidOff),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: paidOff ? context.hopeColors.success : context.hopeColors.warning,
          ),
          const SizedBox(height: 12),
          _DebtMetricGrid(
            metrics: [
              _DebtMetricData(
                label: 'Saldo devedor',
                value: formatMoney(debt.outstandingBalance),
                icon: Icons.account_balance_wallet_outlined,
                color: paidOff ? context.hopeColors.success : context.hopeColors.expense,
              ),
              _DebtMetricData(
                label: 'Parcelas',
                value: '${debt.paidInstallments}/${debt.totalInstallments}',
                icon: Icons.format_list_numbered_outlined,
              ),
              _DebtMetricData(
                label: 'Próxima',
                value: nextInstallment == null
                    ? 'Quitada'
                    : '${formatDate(nextInstallment.dueDate)} · '
                          '${formatMoney(nextInstallment.amount)}',
                icon: Icons.event_available_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (classification.isNotEmpty)
                _DebtChip(icon: Icons.category_outlined, label: classification),
              if (accountName != null)
                _DebtChip(
                  icon: Icons.account_balance_outlined,
                  label: accountName!,
                ),
              _DebtChip(
                icon: Icons.pie_chart_outline,
                label: linkedBudget ? 'Orçamento vinculado' : 'Sem orçamento',
                muted: !linkedBudget,
              ),
              if (debt.interestRateMonthly > 0)
                _DebtChip(
                  icon: Icons.percent_outlined,
                  label:
                      '${debt.interestRateMonthly.toStringAsFixed(2).replaceAll('.', ',')}% a.m.',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: next == null ? null : onPay,
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('Lançar parcela'),
              ),
              OutlinedButton.icon(
                onPressed: onPayments,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Lançamentos'),
              ),
              IconButton.outlined(
                tooltip: 'Editar dívida',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtMetricData {
  const _DebtMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
}

class _DebtMetricGrid extends StatelessWidget {
  const _DebtMetricGrid({required this.metrics});

  final List<_DebtMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? metrics.length : 1;
        final spacing = 8.0;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 62),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.hopeColors.softBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        metric.icon,
                        size: 18,
                        color:
                            metric.color ??
                            Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              metric.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Text(
                              metric.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: metric.color,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DebtStatusPill extends StatelessWidget {
  const _DebtStatusPill({required this.paidOff});

  final bool paidOff;

  @override
  Widget build(BuildContext context) {
    final color = paidOff ? context.hopeColors.success : context.hopeColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        paidOff ? 'Quitada' : 'Ativa',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DebtChip extends StatelessWidget {
  const _DebtChip({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _debtIcon(String type) {
  return switch (type) {
    'financing' => Icons.home_work_outlined,
    'installment_plan' => Icons.shopping_bag_outlined,
    _ => Icons.account_balance_outlined,
  };
}

void _showDirectDebtPayment(
  BuildContext context,
  WidgetRef ref,
  LocalDebt debt,
) {
  final transactions = ref.read(transactionsProvider).valueOrNull ?? [];
  final next = ref
      .read(financeRepositoryProvider)
      .nextOpenDebtInstallment(debt, transactions);
  if (next == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Dívida já quitada.')));
    return;
  }
  showDebtPaymentSheet(
    context,
    debt: debt,
    plannedAmount: next.amount,
    dueDate: next.dueDate,
    installmentNumber: next.installmentNumber,
  );
}

void _showDebtPaymentsSheet(
  BuildContext context,
  WidgetRef ref,
  LocalDebt debt,
) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final async = ref.watch(debtPaymentsProvider(debt.id));
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => HopeErrorState.load(
                error,
                what: 'os lançamentos desta dívida',
                compact: true,
              ),
              data: (payments) => ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  Row(
                    children: [
                      FinanceIconBadge(
                        icon: Icons.receipt_long_outlined,
                        color: context.hopeColors.warning,
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lançamentos da dívida',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              debt.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Lançar parcela',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showDirectDebtPayment(context, ref, debt);
                        },
                        icon: const Icon(Icons.add_task_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (payments.isEmpty)
                    const PremiumEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Nenhum lançamento efetivo',
                      subtitle:
                          'As baixas realizadas por esta dívida aparecerão aqui.',
                    )
                  else
                    for (final tx in payments)
                      _DebtPaymentTile(
                        tx: tx,
                        onEdit: () {
                          Navigator.pop(sheetContext);
                          showEditDebtPaymentSheet(context, tx);
                        },
                        onDelete: () async {
                          final confirmed = await _confirmDeletePayment(
                            context,
                            tx,
                          );
                          if (confirmed != true) return;
                          await ref
                              .read(financeRepositoryProvider)
                              .deleteTransaction(tx);
                          ref.read(syncServiceProvider).syncNow();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Baixa excluída da dívida'),
                              ),
                            );
                          }
                        },
                      ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<bool?> _confirmDeletePayment(BuildContext context, LocalTransaction tx) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir baixa?'),
      content: Text(
        'O lançamento "${tx.description}" será removido e o saldo da dívida será restaurado.',
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
}

class _DebtPaymentTile extends StatelessWidget {
  const _DebtPaymentTile({
    required this.tx,
    required this.onEdit,
    required this.onDelete,
  });

  final LocalTransaction tx;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final link = FinanceRepository.debtPaymentLink(tx);
    final amount = tx.amount ?? tx.amountPlanned ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurface(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            FinanceIconBadge(
              icon: Icons.check_circle_outline,
              color: context.hopeColors.success,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (link != null) 'Parcela ${link.installmentNumber}',
                      'Pago em ${formatDate(tx.paymentDate ?? tx.competenceDate)}',
                      if (link != null) 'vence ${formatDate(link.dueDate)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(amount),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.hopeColors.expense,
                fontWeight: FontWeight.w800,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ações',
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Editar'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Excluir'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtForm extends ConsumerStatefulWidget {
  const _DebtForm({this.debt});

  final LocalDebt? debt;

  @override
  ConsumerState<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends ConsumerState<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _institution = TextEditingController();
  final _original = TextEditingController();
  final _outstanding = TextEditingController();
  final _interest = TextEditingController();
  final _totalInstallments = TextEditingController();
  final _paidInstallments = TextEditingController();
  final _installmentAmount = TextEditingController();
  final _firstDueDate = TextEditingController();
  final _dueDay = TextEditingController();
  String _type = 'loan';
  String? _accountId;
  String? _categoryId;
  String? _subcategoryId;
  bool _linkBudget = true;
  String? _lastDueDate;
  bool _saving = false;

  bool get _editing => widget.debt != null;

  @override
  void initState() {
    super.initState();
    final debt = widget.debt;
    _name.text = debt?.name ?? '';
    _institution.text = debt?.institution ?? '';
    _original.text = debt == null
        ? ''
        : debt.originalAmount.toStringAsFixed(2).replaceAll('.', ',');
    _outstanding.text = debt == null
        ? ''
        : debt.outstandingBalance.toStringAsFixed(2).replaceAll('.', ',');
    _interest.text = debt == null
        ? ''
        : debt.interestRateMonthly.toStringAsFixed(2).replaceAll('.', ',');
    _totalInstallments.text = '${debt?.totalInstallments ?? 1}';
    _paidInstallments.text = '${debt?.paidInstallments ?? 0}';
    _installmentAmount.text = debt == null
        ? ''
        : debt.installmentAmount.toStringAsFixed(2).replaceAll('.', ',');
    _firstDueDate.text = _formatIsoDateBr(debt?.firstDueDate) ?? '';
    _dueDay.text = debt?.dueDay?.toString() ?? '';
    _accountId = debt?.accountId;
    _categoryId = debt?.categoryId;
    _subcategoryId = debt?.subcategoryId;
    _linkBudget = debt == null || (debt.budgetItemId?.isNotEmpty ?? false);
    _type = debt?.type ?? 'loan';
  }

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _original.dispose();
    _outstanding.dispose();
    _interest.dispose();
    _totalInstallments.dispose();
    _paidInstallments.dispose();
    _installmentAmount.dispose();
    _firstDueDate.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final outstanding = parseMoney(_outstanding.text) ?? 0;
    final total = int.tryParse(_totalInstallments.text) ?? 1;
    final paid = int.tryParse(_paidInstallments.text) ?? 0;
    final selectedMonth = ref.read(selectedMonthProvider);
    await ref
        .read(financeRepositoryProvider)
        .upsertDebt(
          id: widget.debt?.id,
          name: _name.text.trim(),
          type: _type,
          institution: _institution.text.trim().isEmpty
              ? null
              : _institution.text.trim(),
          originalAmount: parseMoney(_original.text)!,
          outstandingBalance: outstanding,
          interestRateMonthly: parseMoney(_interest.text) ?? 0,
          totalInstallments: total,
          paidInstallments: paid > total ? total : paid,
          installmentAmount: parseMoney(_installmentAmount.text) ?? 0,
          firstDueDate: _firstDueDate.text.trim().isEmpty
              ? null
              : _brDateToIso(_firstDueDate.text.trim()),
          dueDay: int.tryParse(_dueDay.text.trim()),
          accountId: _accountId,
          categoryId: _categoryId,
          subcategoryId: _subcategoryId,
          budgetItemId: widget.debt?.budgetItemId,
          budgetReferenceMonth: _linkBudget && _categoryId != null
              ? _referenceMonthIso(selectedMonth)
              : null,
          unlinkBudget: !_linkBudget && widget.debt?.budgetItemId != null,
          status: outstanding <= 0 ? 'paid_off' : 'active',
          currentVersion: widget.debt?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Dívida atualizada' : 'Dívida cadastrada'),
        ),
      );
    }
  }

  Future<void> _pickFirstDueDate() async {
    final current = _parseBrDate(_firstDueDate.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _firstDueDate.text = _formatBrDate(picked);
        _lastDueDate = null;
      });
    }
  }

  void _calculateLastDueDate() {
    final firstIso = _brDateToIso(_firstDueDate.text.trim());
    final total = int.tryParse(_totalInstallments.text.trim());
    if (firstIso == null || total == null || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o primeiro vencimento e o total de parcelas'),
        ),
      );
      return;
    }
    final lastIso = addMonthsIso(firstIso, total - 1);
    setState(() => _lastDueDate = _formatIsoDateBr(lastIso));
  }

  Future<void> _delete() async {
    final debt = widget.debt;
    if (debt == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir dívida?'),
        content: Text('A dívida "${debt.name}" será removida.'),
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
    await ref.read(financeRepositoryProvider).deleteDebt(debt);
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dívida excluída')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = (ref.watch(accountsProvider).valueOrNull ?? [])
        .where((a) => a.isActive)
        .toList();
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((category) => category.type == 'expense')
        .toList();
    final selectedCategoryId =
        categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;
    return PremiumFormSheet(
      title: _editing ? 'Editar dívida' : 'Nova dívida',
      subtitle: 'Classifique, vincule ao orçamento e acompanhe cada baixa.',
      icon: Icons.trending_down_outlined,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Identificação',
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final e in _debtTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'loan'),
            ),
            TextFormField(
              controller: _institution,
              decoration: const InputDecoration(
                labelText: 'Instituição',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Vínculos',
          subtitle:
              'Esses vínculos serão usados automaticamente nas baixas da dívida.',
          children: [
            SearchableCategoryField(
              key: ValueKey(
                'debt-category-${categories.length}-${selectedCategoryId ?? 'none'}',
              ),
              categories: categories,
              value: selectedCategoryId,
              placeholder: 'Escolha a categoria',
              enabled: !_saving,
              quickCreateType: 'expense',
              onChanged: (value) => setState(() {
                _categoryId = value;
                _subcategoryId = null;
              }),
              validator: (value) => _linkBudget && value == null
                  ? 'Escolha a categoria para vincular ao orçamento'
                  : null,
            ),
            if (selectedCategoryId != null)
              SubcategorySelector(
                categoryId: selectedCategoryId,
                value: _subcategoryId,
                enabled: !_saving,
                emptyOptionLabel: 'Toda a categoria',
                prefixIcon: Icons.subdirectory_arrow_right,
                onChanged: (value) => setState(() => _subcategoryId = value),
              ),
            DropdownButtonFormField<String?>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Conta de débito',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sem conta vinculada'),
                ),
                for (final account in accounts)
                  DropdownMenuItem<String?>(
                    value: account.id,
                    child: Text(account.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _accountId = value),
            ),
            FormSwitchRow(
              icon: Icons.pie_chart_outline,
              title: 'Vincular ao orçamento',
              subtitle:
                  'Cria ou atualiza uma despesa fixa no orçamento do mês selecionado.',
              value: _linkBudget,
              onChanged: (value) => setState(() => _linkBudget = value),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Valores',
          children: [
            TextFormField(
              controller: _original,
              decoration: const InputDecoration(
                labelText: 'Valor original',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final parsed = v == null ? null : parseMoney(v);
                return (parsed == null || parsed <= 0) ? 'Obrigatório' : null;
              },
            ),
            TextFormField(
              controller: _outstanding,
              decoration: const InputDecoration(
                labelText: 'Saldo devedor',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final parsed = v == null ? null : parseMoney(v);
                return parsed == null ? 'Obrigatório' : null;
              },
            ),
            TextFormField(
              controller: _interest,
              decoration: const InputDecoration(
                labelText: 'Juros mensais',
                suffixText: '% a.m.',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Parcelas',
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _totalInstallments,
                    decoration: const InputDecoration(
                      labelText: 'Total',
                      prefixIcon: Icon(Icons.format_list_numbered_outlined),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _paidInstallments,
                    decoration: const InputDecoration(
                      labelText: 'Pagas',
                      prefixIcon: Icon(Icons.check_circle_outline),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _installmentAmount,
              decoration: const InputDecoration(
                labelText: 'Valor da parcela',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.event_repeat_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextFormField(
              controller: _firstDueDate,
              decoration: InputDecoration(
                labelText: 'Primeiro vencimento',
                helperText: 'dd/mm/aaaa',
                prefixIcon: const Icon(Icons.event_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Selecionar data',
                  onPressed: _pickFirstDueDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ),
              keyboardType: TextInputType.datetime,
              inputFormatters: [_DateInputFormatter()],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                return _brDateToIso(v.trim()) != null ? null : 'Use dd/mm/aaaa';
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _calculateLastDueDate,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Calcular último vencimento'),
              ),
            ),
            if (_lastDueDate != null)
              Text(
                'Último vencimento: $_lastDueDate',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            TextFormField(
              controller: _dueDay,
              decoration: const InputDecoration(
                labelText: 'Dia de vencimento',
                helperText: 'Usado quando não houver primeiro vencimento',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final day = int.tryParse(v.trim());
                return (day == null || day < 1 || day > 31)
                    ? 'Informe um dia entre 1 e 31'
                    : null;
              },
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
        label: const Text('Salvar dívida'),
      ),
      destructiveAction: _editing
          ? TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: context.hopeColors.expense),
              label: const Text('Excluir dívida'),
              style: TextButton.styleFrom(foregroundColor: context.hopeColors.expense),
            )
          : null,
    );
  }
}

String? _formatIsoDateBr(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final date = DateTime.tryParse(iso);
  if (date == null) return null;
  return _formatBrDate(date);
}

String _referenceMonthIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-01';

String _formatBrDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.year.toString().padLeft(4, '0')}';

String? _brDateToIso(String value) {
  final date = _parseBrDate(value);
  if (date == null) return null;
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime? _parseBrDate(String value) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  final date = DateTime(year, month, day);
  if (date.day != day || date.month != month || date.year != year) {
    return null;
  }
  return date;
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(limited[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
