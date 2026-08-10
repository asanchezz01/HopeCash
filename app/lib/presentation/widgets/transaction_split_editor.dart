import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/local/database.dart';
import '../components/hope_components.dart';
import 'quick_create_category.dart';
import 'searchable_category_field.dart';

/// Editor reutilizável do rateio. Ele não cria lançamentos: apenas descreve as
/// categorias que somam o valor único a ser conciliado.
///
/// O editor mostra o quanto falta a cada tecla digitada. Antes o usuário
/// somava de cabeça e só descobria que errou depois de tocar em Salvar, num
/// aviso que não dizia por quanto tinha passado.
class TransactionSplitEditor extends ConsumerStatefulWidget {
  const TransactionSplitEditor({
    super.key,
    required this.type,
    required this.initialSplits,
    required this.onChanged,
    required this.totalAmount,
  });

  final String type;
  final List<TransactionSplit> initialSplits;
  final ValueChanged<List<TransactionSplit>> onChanged;

  /// Valor total do lançamento que as partes precisam somar. Zero enquanto o
  /// usuário ainda não digitou o valor.
  final double totalAmount;

  @override
  ConsumerState<TransactionSplitEditor> createState() =>
      _TransactionSplitEditorState();
}

class _Draft {
  _Draft({this.categoryId, this.subcategoryId, String? amount})
    : amount = TextEditingController(text: amount ?? '');

  String? categoryId;
  String? subcategoryId;
  final TextEditingController amount;

  double get value => parseMoney(amount.text) ?? 0;

  void dispose() => amount.dispose();
}

class _TransactionSplitEditorState
    extends ConsumerState<TransactionSplitEditor> {
  late final List<_Draft> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialSplits.isEmpty
        ? [_Draft(), _Draft()]
        : widget.initialSplits
              .map(
                (split) => _Draft(
                  categoryId: split.categoryId,
                  subcategoryId: split.subcategoryId,
                  amount: split.amount.toStringAsFixed(2).replaceAll('.', ','),
                ),
              )
              .toList();
    _notify();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<TransactionSplit> get _splits => [
    for (final row in _rows)
      if (row.categoryId != null && parseMoney(row.amount.text) != null)
        TransactionSplit(
          categoryId: row.categoryId!,
          subcategoryId: row.subcategoryId,
          amount: parseMoney(row.amount.text)!,
        ),
  ];

  double get _allocated =>
      _rows.fold<double>(0, (sum, row) => sum + row.value);

  double get _remaining =>
      ((widget.totalAmount - _allocated) * 100).roundToDouble() / 100;

  void _notify() => widget.onChanged(_splits);

  /// Joga o que falta na primeira linha vazia — ou na última, se todas já têm
  /// valor. Tira a conta de cabeça do caminho do usuário.
  void _useRemainder() {
    final remaining = _remaining;
    if (remaining <= 0 || _rows.isEmpty) return;
    final target = _rows.firstWhere(
      (row) => row.value == 0,
      orElse: () => _rows.last,
    );
    final next = target.value + remaining;
    target.amount.text = next.toStringAsFixed(2).replaceAll('.', ',');
    setState(_notify);
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((category) => category.type == widget.type)
        .toList();

    return FormField<List<TransactionSplit>>(
      // A validação vive no formulário: tocar em Salvar com o rateio aberto
      // agora acusa o problema embaixo do editor, e não numa barra que some.
      validator: (_) {
        if (widget.totalAmount <= 0) return null;
        if (_splits.length < 2) {
          return 'Informe pelo menos duas categorias com valor.';
        }
        final remaining = _remaining;
        if (remaining.abs() >= 0.01) {
          return remaining > 0
              ? 'Faltam ${formatMoney(remaining)} para fechar o rateio.'
              : 'O rateio passou ${formatMoney(remaining.abs())} do total.';
        }
        return null;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSurface.flat(
              padding: const EdgeInsets.all(HopeSpacing.sm),
              borderColor: field.hasError
                  ? Theme.of(context).colorScheme.error.withValues(alpha: 0.5)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SplitBalance(
                    total: widget.totalAmount,
                    allocated: _allocated,
                    remaining: _remaining,
                  ),
                  const SizedBox(height: HopeSpacing.sm),
                  for (var index = 0; index < _rows.length; index++) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: HopeSpacing.sm,
                        ),
                        child: Divider(
                          height: 1,
                          color: context.hopeColors.softBorder,
                        ),
                      ),
                    _SplitRow(
                      position: index + 1,
                      row: _rows[index],
                      categories: categories,
                      type: widget.type,
                      canRemove: _rows.length > 2,
                      onChanged: () {
                        setState(_notify);
                        field.didChange(_splits);
                      },
                      onRemove: () {
                        setState(() {
                          _rows.removeAt(index).dispose();
                          _notify();
                        });
                        field.didChange(_splits);
                      },
                    ),
                  ],
                  const SizedBox(height: HopeSpacing.sm),
                  Wrap(
                    spacing: HopeSpacing.xs,
                    runSpacing: HopeSpacing.xxs,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _rows.add(_Draft());
                          _notify();
                        }),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Adicionar categoria'),
                      ),
                      if (_remaining >= 0.01)
                        TextButton.icon(
                          onPressed: _useRemainder,
                          icon: const Icon(
                            Icons.call_split_rounded,
                            size: 18,
                          ),
                          label: Text(
                            'Usar o restante (${formatMoney(_remaining)})',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HopeSpacing.sm,
                  HopeSpacing.xxs,
                  HopeSpacing.sm,
                  0,
                ),
                child: Text(
                  field.errorText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Cabeçalho do rateio: total, barra de preenchimento e o que falta.
class _SplitBalance extends StatelessWidget {
  const _SplitBalance({
    required this.total,
    required this.allocated,
    required this.remaining,
  });

  final double total;
  final double allocated;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.hopeColors;
    final closed = total > 0 && remaining.abs() < 0.01;
    final over = remaining <= -0.01;

    final (Color tone, String status) = total <= 0
        ? (theme.colorScheme.onSurfaceVariant, 'Informe o valor do lançamento')
        : closed
        ? (colors.success, 'Rateio fechado')
        : over
        ? (colors.expense, 'Passou ${formatMoney(remaining.abs())} do total')
        : (colors.warning, 'Faltam ${formatMoney(remaining)}');

    final progress = total <= 0 ? 0.0 : (allocated / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Rateio por categoria',
                style: theme.textTheme.titleSmall,
              ),
            ),
            MoneyText(
              allocated,
              emphasis: MoneyEmphasis.row,
              color: tone,
              semanticsPrefix: 'Distribuído',
            ),
            Text(
              ' / ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            MoneyText(
              total,
              emphasis: MoneyEmphasis.caption,
              color: theme.colorScheme.onSurfaceVariant,
              semanticsPrefix: 'de',
            ),
          ],
        ),
        const SizedBox(height: HopeSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(HopeRadius.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: context.motion(HopeMotion.normal),
            curve: HopeMotion.standard,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              color: tone,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
            ),
          ),
        ),
        const SizedBox(height: HopeSpacing.xxs),
        Row(
          children: [
            Icon(
              closed
                  ? Icons.check_circle_outline_rounded
                  : over
                  ? Icons.error_outline_rounded
                  : Icons.pending_outlined,
              size: 15,
              color: tone,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.position,
    required this.row,
    required this.categories,
    required this.type,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int position;
  final _Draft row;
  final List<LocalCategory> categories;
  final String type;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final categoryField = SearchableCategoryField(
      key: ValueKey('split-category-${row.hashCode}'),
      categories: categories,
      value: row.categoryId,
      quickCreateType: type,
      labelText: 'Categoria $position',
      onChanged: (value) {
        row.categoryId = value;
        row.subcategoryId = null;
        onChanged();
      },
    );

    final amountField = TextFormField(
      controller: row.amount,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.end,
      style: HopeNumerals.style(context, MoneyEmphasis.row),
      decoration: const InputDecoration(
        labelText: 'Valor',
        prefixText: 'R\$ ',
      ),
      onChanged: (_) => onChanged(),
    );

    final removeButton = canRemove
        ? IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remover categoria $position',
            style: IconButton.styleFrom(
              minimumSize: const Size.square(kHopeMinTapTarget),
            ),
          )
        : const SizedBox(width: kHopeMinTapTarget);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Abaixo de 420px a linha lado a lado esmaga o campo de valor em
        // ~110px; aí categoria e valor viram duas linhas.
        final stacked = constraints.maxWidth < 420;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stacked) ...[
              categoryField,
              const SizedBox(height: HopeSpacing.xs),
              Row(
                children: [
                  Expanded(child: amountField),
                  removeButton,
                ],
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: categoryField),
                  const SizedBox(width: HopeSpacing.xs),
                  SizedBox(width: 150, child: amountField),
                  removeButton,
                ],
              ),
            if (row.categoryId != null)
              Padding(
                padding: const EdgeInsets.only(top: HopeSpacing.xs),
                child: SubcategorySelector(
                  categoryId: row.categoryId!,
                  value: row.subcategoryId,
                  onChanged: (value) {
                    row.subcategoryId = value;
                    onChanged();
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
