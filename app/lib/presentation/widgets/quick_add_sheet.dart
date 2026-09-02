import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import 'form_kit.dart';
import 'money_field.dart';
import 'quick_create_category.dart';
import 'searchable_category_field.dart';
import 'transaction_split_editor.dart';

/// Valores iniciais do lançamento rápido (ex.: vindos do comando de voz).
/// Os ids devem ser válidos e coerentes com o tipo — o chamador valida.
class QuickAddPrefill {
  const QuickAddPrefill({
    this.type,
    this.amount,
    this.description,
    this.date,
    this.categoryId,
    this.subcategoryId,
    this.accountId,
    this.cardId,
    this.installments,
    this.isPaid,
    this.categorySplits,
  });

  final String? type;
  final double? amount;
  final String? description;
  final String? date;
  final String? categoryId;
  final String? subcategoryId;
  final String? accountId;
  final String? cardId;
  final int? installments;
  final bool? isPaid;
  final List<TransactionSplit>? categorySplits;
}

/// Lançamento rápido: despesa ou receita em poucos segundos.
/// Retorna true quando o lançamento foi salvo (null se o usuário fechou).
Future<bool?> showQuickAddSheet(
  BuildContext context, {
  QuickAddPrefill? prefill,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _QuickAddSheet(prefill: prefill),
  );
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({this.prefill});

  final QuickAddPrefill? prefill;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _type = 'expense';
  bool _isPaid = true;
  String _date = todayIso();

  /// Meio de pagamento: `account:<id>` ou `card:<id>`.
  String? _paymentKey;
  String? _categoryId;
  String? _subcategoryId;
  int _installments = 1;
  bool _saving = false;
  bool _splitEnabled = false;
  List<TransactionSplit> _splits = const [];

  /// Quitação escolhida: `debt:<id>` ou `card:<id>`; null = despesa comum.
  String? _settlementKey;

  bool get _isCardPayment => _paymentKey?.startsWith('card:') ?? false;

  /// Quitar só faz sentido para despesa saindo de uma conta.
  bool get _canSettle => _type == 'expense' && !_isCardPayment;

  /// Fatura já é o gasto das compras do ciclo: não pede categoria nem rateio.
  bool get _isInvoiceSettlement => _settlementKey?.startsWith('card:') ?? false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p == null) return;
    _type = p.type ?? _type;
    if (p.amount != null) {
      _amount.text = p.amount!.toStringAsFixed(2).replaceAll('.', ',');
    }
    _description.text = p.description ?? '';
    _date = p.date ?? _date;
    _categoryId = p.categoryId;
    if (_categoryId != null) _subcategoryId = p.subcategoryId;
    if (p.cardId != null) {
      _paymentKey = 'card:${p.cardId}';
      if (_type == 'expense') {
        _installments = (p.installments ?? 1).clamp(1, 24).toInt();
      }
    } else if (p.accountId != null) {
      _paymentKey = 'account:${p.accountId}';
    }
    _isPaid = p.isPaid ?? _isPaid;
    _splits = p.categorySplits ?? const [];
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
    final repo = ref.read(financeRepositoryProvider);
    final amount = parseMoney(_amount.text)!;
    final description = _description.text.trim();
    String message;
    try {
      if (_isCardPayment) {
        final cardId = _paymentKey!.substring('card:'.length);
        final cards = ref.read(creditCardsProvider).valueOrNull ?? [];
        final card = cards.firstWhere((c) => c.id == cardId);
        if (_type == 'expense') {
          await repo.addCardExpense(
            card: card,
            description: description,
            totalAmount: amount,
            purchaseDate: _date,
            installments: _installments,
            categoryId: _categoryId,
            subcategoryId: _subcategoryId,
            categorySplits: _splitEnabled ? _splits : null,
          );
          message = _installments > 1
              ? 'Compra lançada em ${_installments}x no ${card.name}'
              : 'Despesa lançada no ${card.name}';
        } else {
          await repo.addCardCredit(
            card: card,
            description: description,
            amount: amount,
            date: _date,
            categoryId: _categoryId,
            subcategoryId: _subcategoryId,
          );
          message = 'Estorno lançado no ${card.name}';
        }
      } else if (_settlementKey != null) {
        message = await _saveSettlement(repo, amount, description);
      } else {
        await repo.addTransaction(
          type: _type,
          description: description,
          amount: amount,
          date: _date,
          isPaid: _isPaid,
          accountId: _paymentKey?.startsWith('account:') ?? false
              ? _paymentKey!.substring('account:'.length)
              : null,
          categoryId: _categoryId,
          subcategoryId: _subcategoryId,
          categorySplits: _splitEnabled ? _splits : null,
        );
        message = _type == 'expense' ? 'Despesa lançada' : 'Receita lançada';
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showHopeSnack(
          context,
          error.message?.toString() ?? 'Revise o rateio antes de salvar.',
          tone: HopeSnackTone.danger,
        );
      }
      return;
    }

    // Sincroniza em segundo plano; a UI já está atualizada pelo banco local.
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.of(context).pop(true);
      showHopeSnack(context, message, tone: HopeSnackTone.success);
    }
  }

  /// Quitação: em vez de uma despesa avulsa, o lançamento dá baixa em uma
  /// dívida (amortiza o saldo devedor) ou em uma fatura (marca as compras do
  /// ciclo como pagas). Mesma escolha oferecida na conciliação de extrato.
  Future<String> _saveSettlement(
    FinanceRepository repo,
    double amount,
    String description,
  ) async {
    final accountId = _paymentKey!.substring('account:'.length);
    final id = _settlementKey!.split(':').last;
    final transactions = ref.read(transactionsProvider).valueOrNull ?? [];
    if (_settlementKey!.startsWith('debt:')) {
      final debt = (ref.read(debtsProvider).valueOrNull ?? []).firstWhere(
        (d) => d.id == id,
      );
      final next = repo.nextOpenDebtInstallment(debt, transactions);
      if (next == null) throw ArgumentError('Esta dívida já está quitada.');
      await repo.payDebtInstallment(
        debt: debt,
        plannedAmount: next.amount,
        amount: amount,
        dueDate: next.dueDate,
        paymentDate: _date,
        installmentNumber: next.installmentNumber,
        categoryId: _categoryId,
        subcategoryId: _subcategoryId,
        accountId: accountId,
        description: description,
      );
      return 'Baixa registrada em ${debt.name}';
    }
    final card = (ref.read(creditCardsProvider).valueOrNull ?? []).firstWhere(
      (c) => c.id == id,
    );
    final cycle = repo.openInvoiceCycle(
      card.id,
      transactions,
      paymentDate: _date,
      amount: amount,
    );
    if (cycle.isEmpty) {
      throw ArgumentError('Não há fatura em aberto no ${card.name}.');
    }
    await repo.payCardInvoice(
      card: card,
      transactions: cycle,
      accountId: accountId,
      paymentDate: _date,
      paidAmount: amount,
      description: description,
    );
    return 'Fatura do ${card.name} quitada';
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
        .where((c) => c.isActive)
        .toList();
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == _type)
        .toList();
    final debts = (ref.watch(debtsProvider).valueOrNull ?? [])
        .where((d) => d.status == 'active')
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    'Novo lançamento',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Valor, descrição e onde entrou ou saiu.',
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
                      // Receita não quita dívida nem fatura.
                      if (_type != 'expense') _settlementKey = null;
                      // Estorno no cartão (receita) não é parcelado.
                      if (_type == 'income') _installments = 1;
                    }),
                  ),
                  const SizedBox(height: HopeSpacing.md),
                  MoneyField(
                    controller: _amount,
                    accent: accent,
                    autofocus: true,
                    enabled: !_saving,
                    // O rateio depende do total: cada tecla recalcula o quanto
                    // ainda falta distribuir.
                    onChanged: _splitEnabled ? (_) => setState(() {}) : null,
                  ),
                  const SizedBox(height: HopeSpacing.sm),
                  TextFormField(
                    controller: _description,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Mercado, aluguel, salário…',
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
                      // A baixa precisa sair de uma conta: é o débito que
                      // paga a dívida ou a fatura.
                      validator: (v) =>
                          _settlementKey != null &&
                              !(v?.startsWith('account:') ?? false)
                          ? 'Escolha a conta que pagou'
                          : null,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() {
                              _paymentKey = v;
                              if (!_isCardPayment) {
                                _installments = 1;
                              } else {
                                _settlementKey = null;
                              }
                            }),
                    ),
                    second: _splitEnabled || _isInvoiceSettlement
                        ? null
                        : SearchableCategoryField(
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
                  if (_categoryId != null &&
                      !_splitEnabled &&
                      !_isInvoiceSettlement) ...[
                    const SizedBox(height: HopeSpacing.sm),
                    SubcategorySelector(
                      categoryId: _categoryId,
                      value: _subcategoryId,
                      enabled: !_saving,
                      onChanged: (v) => setState(() => _subcategoryId = v),
                    ),
                  ],
                  if (_canSettle) ...[
                    const SizedBox(height: HopeSpacing.sm),
                    DropdownButtonFormField<String>(
                      initialValue: _settlementKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Quitação',
                        helperText:
                            'Dá baixa na dívida ou na fatura em vez de '
                            'lançar uma despesa comum',
                        helperMaxLines: 2,
                        prefixIcon: Icon(Icons.price_check_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Despesa comum'),
                        ),
                        for (final d in debts)
                          DropdownMenuItem(
                            value: 'debt:${d.id}',
                            child: Text(
                              'Dívida · ${d.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final c in cards)
                          DropdownMenuItem(
                            value: 'card:${c.id}',
                            child: Text(
                              'Fatura · ${c.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() {
                              _settlementKey = v;
                              if (v != null) {
                                _isPaid = true;
                                _splitEnabled = false;
                                if (_isInvoiceSettlement) {
                                  _categoryId = null;
                                  _subcategoryId = null;
                                }
                              }
                            }),
                    ),
                  ],
                  if (_settlementKey == null) ...[
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
                  ],
                  const SizedBox(height: HopeSpacing.sm),
                  ResponsiveFieldPair(
                    first: DateField(
                      date: _date,
                      enabled: !_saving,
                      onPressed: _pickDate,
                    ),
                    // Parcelamento só para compra (despesa) no cartão; estorno
                    // (receita) é crédito único. Conta mostra Pago/Previsto.
                    second: _isCardPayment && isExpense
                        ? DropdownButtonFormField<int>(
                            initialValue: _installments,
                            decoration: const InputDecoration(
                              labelText: 'Parcelas',
                              prefixIcon: Icon(Icons.splitscreen_outlined),
                            ),
                            items: [
                              for (var i = 1; i <= 24; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(i == 1 ? 'À vista' : '${i}x'),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _installments = v ?? 1),
                          )
                        : _isCardPayment || _settlementKey != null
                        ? null
                        : TransactionStatusField(
                            isPaid: _isPaid,
                            isExpense: isExpense,
                            onChanged: (v) => setState(() => _isPaid = v),
                          ),
                  ),
                  if (_settlementKey != null)
                    Padding(
                      padding: const EdgeInsets.only(top: HopeSpacing.xs),
                      child: FieldHint(
                        text: _isInvoiceSettlement
                            ? 'As compras da fatura escolhida ficam pagas e o '
                                  'débito sai da conta — o gasto já foi contado '
                                  'em cada compra, então não pede categoria.'
                            : 'O saldo devedor da dívida é amortizado e a '
                                  'parcela avança.',
                      ),
                    ),
                  if (_isCardPayment)
                    Padding(
                      padding: const EdgeInsets.only(top: HopeSpacing.xs),
                      child: FieldHint(
                        text: isExpense
                            ? 'A compra entra na fatura e vence conforme o '
                                  'fechamento configurado no cartão.'
                            : 'O estorno entra na fatura como crédito, '
                                  'reduzindo o valor a pagar e o limite usado.',
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
                    label: Text(_saving ? 'Salvando…' : 'Salvar lançamento'),
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
