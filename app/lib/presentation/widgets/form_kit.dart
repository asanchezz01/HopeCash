import 'package:flutter/material.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/utils/money.dart';

/// Peças compartilhadas pelos formulários de lançamento.
///
/// Estavam duplicadas entre o lançamento rápido e a edição, com pequenas
/// diferenças de rótulo e altura que apareciam quando as duas telas ficavam
/// lado a lado.

/// Dois campos lado a lado no tablet, empilhados no celular.
///
/// Dois `Expanded` numa `Row` fixa deixavam cada campo com ~150px num celular
/// pequeno, cortando nomes de conta e rótulos.
class ResponsiveFieldPair extends StatelessWidget {
  const ResponsiveFieldPair({super.key, required this.first, this.second});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) {
    if (second == null) return first;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: HopeSpacing.sm),
              second!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: HopeSpacing.sm),
            Expanded(child: second!),
          ],
        );
      },
    );
  }
}

/// Seletor de data no formato de campo, para alinhar com os vizinhos.
///
/// Antes era um `OutlinedButton` ao lado de campos com moldura: alturas e
/// rótulos diferentes na mesma linha.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.date,
    required this.onPressed,
    this.enabled = true,
    this.label = 'Data',
  });

  final String date;
  final VoidCallback onPressed;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.xs,
        ),
      ),
      child: Semantics(
        button: true,
        label: '$label: ${formatDate(date)}',
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(HopeRadius.xs),
          child: SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                formatDate(date),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pago × Previsto como par de opções.
///
/// O interruptor anterior mudava o próprio rótulo ("Pago" ↔ "Previsto"), então
/// não dava para saber o que ele faria antes de tocar.
class TransactionStatusField extends StatelessWidget {
  const TransactionStatusField({
    super.key,
    required this.isPaid,
    required this.isExpense,
    required this.onChanged,
  });

  final bool isPaid;
  final bool isExpense;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Situação',
        contentPadding: EdgeInsets.symmetric(
          horizontal: HopeSpacing.xs,
          vertical: HopeSpacing.xxs,
        ),
      ),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            label: Text(isExpense ? 'Pago' : 'Recebido'),
          ),
          const ButtonSegment(value: false, label: Text('Previsto')),
        ],
        selected: {isPaid},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Explicação curta abaixo de um campo, quando a regra do negócio precisa ser
/// dita antes de o usuário salvar.
class FieldHint extends StatelessWidget {
  const FieldHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
