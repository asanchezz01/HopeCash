import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import 'quick_create_category.dart';
import 'searchable_category_field.dart';

Future<void> showDebtPaymentSheet(
  BuildContext context, {
  required LocalDebt debt,
  required double plannedAmount,
  required String dueDate,
  required int installmentNumber,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DebtPaymentSheet(
      debt: debt,
      plannedAmount: plannedAmount,
      dueDate: dueDate,
      installmentNumber: installmentNumber,
    ),
  );
}

class _DebtPaymentSheet extends ConsumerStatefulWidget {
  const _DebtPaymentSheet({
    required this.debt,
    required this.plannedAmount,
    required this.dueDate,
    required this.installmentNumber,
  });

  final LocalDebt debt;
  final double plannedAmount;
  final String dueDate;
  final int installmentNumber;

  @override
  ConsumerState<_DebtPaymentSheet> createState() => _DebtPaymentSheetState();
}

class _DebtPaymentSheetState extends ConsumerState<_DebtPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _interest = TextEditingController();
  final _discount = TextEditingController();
  late String _paymentDate;
  String? _categoryId;
  String? _subcategoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.plannedAmount.toStringAsFixed(2).replaceAll('.', ','),
    );
    _paymentDate = todayIso();
    _categoryId = widget.debt.categoryId;
    _subcategoryId = widget.debt.subcategoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _interest.dispose();
    _discount.dispose();
    super.dispose();
  }

  double get _interestValue =>
      _interest.text.trim().isEmpty ? 0 : (parseMoney(_interest.text) ?? 0);

  double get _discountValue =>
      _discount.text.trim().isEmpty ? 0 : (parseMoney(_discount.text) ?? 0);

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
    final amount = parseMoney(_amount.text)!;
    final net = amount - _discountValue;
    await ref
        .read(financeRepositoryProvider)
        .payDebtInstallment(
          debt: widget.debt,
          plannedAmount: widget.plannedAmount,
          amount: amount,
          dueDate: widget.dueDate,
          paymentDate: _paymentDate,
          installmentNumber: widget.installmentNumber,
          interestAmount: _interestValue,
          discountAmount: _discountValue,
          categoryId: _categoryId,
          subcategoryId: _subcategoryId,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento registrado: ${formatMoney(net)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((category) => category.type == 'expense')
        .toList();
    final selectedCategoryId =
        categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Registrar pagamento',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.debt.name} · parcela ${widget.installmentNumber}/${widget.debt.totalInstallments}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Valor da baixa',
                  prefixText: 'R\$ ',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  helperText:
                      'Previsto ${formatMoney(widget.plannedAmount)} · saldo ${formatMoney(widget.debt.outstandingBalance)}',
                ),
                validator: (v) {
                  final parsed = v == null ? null : parseMoney(v);
                  if (parsed == null || parsed <= 0) {
                    return 'Informe um valor válido';
                  }
                  // Só a parte que amortiza (valor da baixa − juros/multa)
                  // é limitada pelo saldo devedor.
                  if (parsed - _interestValue >
                      widget.debt.outstandingBalance + 0.005) {
                    return 'Amortização maior que o saldo devedor';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interest,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Juros e multa (opcional)',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.percent_outlined),
                  helperText:
                      'Acréscimo por atraso incluído no valor pago. Não '
                      'amortiza a dívida e entra na categoria "Juros e Multas".',
                  helperMaxLines: 3,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final parsed = parseMoney(v);
                  if (parsed == null || parsed < 0) {
                    return 'Informe um valor válido';
                  }
                  final total = parseMoney(_amount.text);
                  if (total != null && parsed >= total) {
                    return 'Deve ser menor que o valor pago';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _discount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Desconto de antecipação (opcional)',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.discount_outlined),
                  helperText:
                      'A parcela é quitada pelo valor cheio; só o líquido '
                      '(valor da baixa − desconto) movimenta a conta.',
                  helperMaxLines: 3,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final parsed = parseMoney(v);
                  if (parsed == null || parsed < 0) {
                    return 'Informe um valor válido';
                  }
                  final total = parseMoney(_amount.text) ?? 0;
                  if (parsed >= total - _interestValue) {
                    return 'Deve ser menor que o valor da baixa';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SearchableCategoryField(
                key: ValueKey(
                  'debt-pay-category-${categories.length}-${selectedCategoryId ?? 'none'}',
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
                const SizedBox(height: 12),
                SubcategorySelector(
                  categoryId: selectedCategoryId,
                  value: _subcategoryId,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _subcategoryId = value),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text('Pago em ${formatDate(_paymentDate)}'),
              ),
              const SizedBox(height: 8),
              Text(
                'Vencimento previsto: ${formatDate(widget.dueDate)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Registrar baixa'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
