import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/utils/money.dart';

/// Campo de valor em reais.
///
/// Num lançamento o valor é a informação principal, então ele é desenhado como
/// informação principal: dígitos grandes e tabulares, símbolo da moeda fixo à
/// esquerda e o acento do tipo (despesa ou receita) tingindo o campo. O
/// teclado abre direto no numérico e só aceita dígitos, vírgula e ponto.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.accent,
    this.label = 'Valor',
    this.helperText,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.validator,
    this.textInputAction,
  });

  final TextEditingController controller;

  /// Cor do tipo do lançamento — o campo inteiro herda dela.
  final Color accent;

  final String label;
  final String? helperText;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberStyle = HopeNumerals.style(context, MoneyEmphasis.primary)
        .copyWith(color: theme.colorScheme.onSurface);

    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      style: numberStyle,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(
            left: HopeSpacing.md,
            right: HopeSpacing.xs,
          ),
          child: Text(
            'R\$',
            style: theme.textTheme.titleMedium?.copyWith(color: accent),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        fillColor: accent.withValues(alpha: 0.05),
      ),
      onChanged: onChanged,
      validator:
          validator ??
          (value) {
            final parsed = value == null ? null : parseMoney(value);
            return (parsed == null || parsed <= 0)
                ? 'Informe um valor maior que zero'
                : null;
          },
    );
  }
}
