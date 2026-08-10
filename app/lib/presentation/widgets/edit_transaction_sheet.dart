import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import 'form_kit.dart';
import 'money_field.dart';
import 'quick_create_category.dart';
import 'searchable_category_field.dart';
import 'transaction_split_editor.dart';

/// Edição de um lançamento existente, no mesmo estilo do formulário de
/// orçamento (folha inferior com campos, Salvar e Excluir).
Future<void> showEditTransactionSheet(
  BuildContext context,
  LocalTransaction tx,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditTransactionSheet(tx: tx),
  );
}

Future<void> showEditDebtPaymentSheet(
  BuildContext context,
  LocalTransaction tx,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditDebtPaymentSheet(tx: tx),
  );
}

class _EditDebtPaymentSheet extends ConsumerStatefulWidget {
  const _EditDebtPaymentSheet({required this.tx});

  final LocalTransaction tx;

  @override
  ConsumerState<_EditDebtPaymentSheet> createState() =>
      _EditDebtPaymentSheetState();
}

class _EditDebtPaymentSheetState extends ConsumerState<_EditDebtPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String _paymentDate;
  String? _categoryId;
  String? _subcategoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.tx.amount ?? widget.tx.amountPlanned ?? 0;
    _amount.text = value.toStringAsFixed(2).replaceAll('.', ',');
    _paymentDate = widget.tx.paymentDate ?? widget.tx.competenceDate;
    _categoryId = widget.tx.categoryId;
    _subcategoryId = widget.tx.subcategoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_paymentDate),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _paymentDate = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(financeRepositoryProvider)
        .updateDebtPayment(
          transaction: widget.tx,
          amount: parseMoney(_amount.text)!,
          paymentDate: _paymentDate,
          categoryId: _categoryId!,
          subcategoryId: _subcategoryId,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Baixa atualizada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((category) => category.type == 'expense')
        .toList();
    final selectedCategoryId =
        categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                HopeSpacing.lg,
                HopeSpacing.xs,
                HopeSpacing.lg,
                MediaQuery.viewInsetsOf(context).bottom + HopeSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Editar baixa da dívida',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: HopeSpacing.xxs),
                  Text(
                    widget.tx.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(widget.tx.competenceDate)} · ${formatMoney(widget.tx.amount ?? widget.tx.amountPlanned)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: HopeSpacing.md),
                  MoneyField(
                    controller: _amount,
                    accent: context.hopeColors.expense,
                    label: 'Valor pago',
                    enabled: !_saving,
                  ),
                  const SizedBox(height: HopeSpacing.sm),
                  DateField(
                    date: _paymentDate,
                    label: 'Pago em',
                    enabled: !_saving,
                    onPressed: _pickDate,
                  ),
                  const SizedBox(height: HopeSpacing.sm),
                  SearchableCategoryField(
                    key: ValueKey(
                      'debt-payment-category-${categories.length}-${selectedCategoryId ?? 'none'}',
                    ),
                    categories: categories,
                    value: selectedCategoryId,
                    labelText: 'Categoria da despesa',
                    placeholder: 'Escolha a categoria da despesa',
                    allowEmpty: false,
                    enabled: !_saving,
                    quickCreateType: 'expense',
                    onChanged: (value) => setState(() {
                      _categoryId = value;
                      _subcategoryId = null;
                    }),
                    validator: (value) =>
                        value == null ? 'Escolha a categoria da despesa' : null,
                  ),
                  if (selectedCategoryId != null) ...[
                    const SizedBox(height: HopeSpacing.sm),
                    SubcategorySelector(
                      categoryId: selectedCategoryId,
                      value: _subcategoryId,
                      enabled: !_saving,
                      onChanged: (value) =>
                          setState(() => _subcategoryId = value),
                    ),
                  ],
                  const SizedBox(height: HopeSpacing.lg),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Salvando…' : 'Salvar baixa'),
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

class _EditTransactionSheet extends ConsumerStatefulWidget {
  const _EditTransactionSheet({required this.tx});

  final LocalTransaction tx;

  @override
  ConsumerState<_EditTransactionSheet> createState() =>
      _EditTransactionSheetState();
}

class _EditTransactionSheetState extends ConsumerState<_EditTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();

  late String _type;
  late bool _isPaid;
  late String _date;

  /// Meio: `account:<id>` ou `card:<id>`.
  String? _paymentKey;
  String? _categoryId;
  String? _subcategoryId;
  bool _saving = false;
  bool _splitEnabled = false;
  List<TransactionSplit> _splits = const [];

  bool get _isCardPayment => _paymentKey?.startsWith('card:') ?? false;

  @override
  void initState() {
    super.initState();
    final tx = widget.tx;
    _type = tx.type == 'income' ? 'income' : 'expense';
    _isPaid = tx.status == 'paid';
    _date = tx.competenceDate;
    final value = tx.amountPlanned ?? tx.amount;
    if (value != null) {
      _amount.text = value.toStringAsFixed(2).replaceAll('.', ',');
    }
    _description.text = tx.description;
    if (tx.cardId != null && tx.cardId!.isNotEmpty) {
      _paymentKey = 'card:${tx.cardId}';
    } else if (tx.accountId != null && tx.accountId!.isNotEmpty) {
      _paymentKey = 'account:${tx.accountId}';
    }
    _categoryId = tx.categoryId;
    _subcategoryId = tx.subcategoryId;
    _splits = TransactionSplit.fromJson(tx.categorySplits);
    _splitEnabled = _splits.isNotEmpty;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final key = _paymentKey;
    final accountId = (key?.startsWith('account:') ?? false)
        ? key!.substring('account:'.length)
        : null;
    final cardId = (key?.startsWith('card:') ?? false)
        ? key!.substring('card:'.length)
        : null;
    try {
      await ref
          .read(financeRepositoryProvider)
          .updateTransaction(
            original: widget.tx,
            type: _type,
            description: _description.text.trim(),
            amount: parseMoney(_amount.text)!,
            date: _date,
            isPaid: _isPaid,
            accountId: accountId,
            cardId: cardId,
            categoryId: _categoryId,
            subcategoryId: _subcategoryId,
            categorySplits: _splitEnabled ? _splits : null,
          );
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Revise o rateio'),
          ),
        );
      }
      return;
    }
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lançamento atualizado')));
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await ref.read(financeRepositoryProvider).deleteTransaction(widget.tx);
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lançamento excluído')));
    }
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

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final cards = (ref.watch(creditCardsProvider).valueOrNull ?? [])
        .where((c) => c.isActive || 'card:${c.id}' == _paymentKey)
        .toList();
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == _type)
        .toList();
    final isExpense = _type == 'expense';

    final accent = isExpense
        ? context.hopeColors.expense
        : context.hopeColors.income;

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                HopeSpacing.lg,
                HopeSpacing.xs,
                HopeSpacing.lg,
                MediaQuery.viewInsetsOf(context).bottom + HopeSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Editar lançamento',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.tx.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: HopeSpacing.md),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text('Despesa'),
                        icon: Icon(Icons.arrow_downward_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text('Receita'),
                        icon: Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _categoryId = null;
                      _subcategoryId = null;
                    }),
                  ),
                  const SizedBox(height: HopeSpacing.md),
                  MoneyField(
                    controller: _amount,
                    accent: accent,
                    enabled: !_saving,
                    onChanged: _splitEnabled ? (_) => setState(() {}) : null,
                  ),
                  const SizedBox(height: HopeSpacing.sm),
                  TextFormField(
                    controller: _description,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      prefixIcon: Icon(Icons.edit_note_outlined),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Descreva o lançamento'
                        : null,
                  ),
                  const SizedBox(height: HopeSpacing.sm),
                  ResponsiveFieldPair(
                    first: DropdownButtonFormField<String>(
                      key: ValueKey('payment-$_type'),
                      initialValue: _paymentKey,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: isExpense ? 'Pagar com' : 'Receber em',
                        prefixIcon: Icon(
                          _isCardPayment
                              ? Icons.credit_card_outlined
                              : Icons.account_balance_outlined,
                        ),
                      ),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                            value: 'account:${a.id}',
                            child: Text(
                              a.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final c in cards)
                          DropdownMenuItem(
                            value: 'card:${c.id}',
                            child: Text(
                              '💳 ${c.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      // Só é exigido quando o lançamento é dado como pago: aí
                      // ele precisa movimentar alguma conta ou fatura. Previsto
                      // pode ficar sem origem até a baixa (mesma regra do
                      // backend, em core/transactionDestination.js).
                      validator: (value) =>
                          _isPaid && (value == null || value.isEmpty)
                          ? (isExpense
                                ? 'Escolha de onde sai o dinheiro'
                                : 'Escolha onde o dinheiro entra')
                          : null,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _paymentKey = v),
                    ),
                    second: _splitEnabled
                        ? null
                        : SearchableCategoryField(
                            key: ValueKey('category-$_type'),
                            categories: categories,
                            value: _categoryId,
                            quickCreateType: _type,
                            enabled: !_saving,
                            onChanged: (value) => setState(() {
                              _categoryId = value;
                              _subcategoryId = null;
                            }),
                          ),
                  ),
                  if (_categoryId != null && !_splitEnabled) ...[
                    const SizedBox(height: HopeSpacing.sm),
                    SubcategorySelector(
                      categoryId: _categoryId,
                      value: _subcategoryId,
                      enabled: !_saving,
                      onChanged: (v) => setState(() => _subcategoryId = v),
                    ),
                  ],
                  const SizedBox(height: HopeSpacing.sm),
                  FormSwitchRow(
                    icon: Icons.call_split_rounded,
                    title: 'Ratear por categorias',
                    subtitle: 'Um lançamento só, dividido entre categorias',
                    value: _splitEnabled,
                    onChanged: (value) => setState(() {
                      _splitEnabled = value;
                      if (value) {
                        _categoryId = null;
                        _subcategoryId = null;
                      }
                    }),
                  ),
                  if (_splitEnabled) ...[
                    const SizedBox(height: HopeSpacing.sm),
                    TransactionSplitEditor(
                      type: _type,
                      initialSplits: _splits,
                      totalAmount: parseMoney(_amount.text) ?? 0,
                      onChanged: (splits) => _splits = splits,
                    ),
                  ],
                  const SizedBox(height: HopeSpacing.sm),
                  ResponsiveFieldPair(
                    first: DateField(
                      date: _date,
                      enabled: !_saving,
                      onPressed: _pickDate,
                    ),
                    second: TransactionStatusField(
                      isPaid: _isPaid,
                      isExpense: isExpense,
                      onChanged: (v) => setState(() => _isPaid = v),
                    ),
                  ),
                  const SizedBox(height: HopeSpacing.lg),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Salvando…' : 'Salvar alterações'),
                  ),
                  const SizedBox(height: HopeSpacing.xxs),
                  TextButton.icon(
                    onPressed: _saving ? null : () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    label: const Text('Excluir lançamento'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Exclusão pede confirmação: antes um toque só apagava o lançamento, sem
  /// aviso e sem volta.
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          '"${widget.tx.description}" sai das suas listas e dos totais do mês. '
          'Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _delete();
  }
}
