import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';

/// Navegação entre meses (período fechado) sobre [selectedMonthProvider].
///
/// Mostra o mês em exibição com setas para o anterior/seguinte e, quando o mês
/// selecionado não é o atual, um atalho para voltar ao mês corrente.
///
/// Com [onHero] o controle é desenhado para viver dentro do painel escuro do
/// painel inicial, junto dos números que ele governa.
class MonthNavigator extends ConsumerWidget {
  const MonthNavigator({super.key, this.onHero = false});

  final bool onHero;

  static final _monthLabel = DateFormat.yMMMM('pt_BR');
  static final _monthShort = DateFormat.yMMM('pt_BR');

  DateTime _shift(DateTime month, int delta) =>
      DateTime(month.year, month.month + delta);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final theme = Theme.of(context);
    final colors = context.hopeColors;

    final foreground = onHero ? colors.heroOnSurface : theme.colorScheme.onSurface;
    final muted = onHero
        ? colors.heroOnSurfaceMuted
        : theme.colorScheme.onSurfaceVariant;

    String capitalized(String value) => value.isEmpty
        ? value
        : '${value[0].toUpperCase()}${value.substring(1)}';

    void setMonth(DateTime value) =>
        ref.read(selectedMonthProvider.notifier).state = value;

    return Semantics(
      label: 'Mês em exibição',
      value: capitalized(_monthLabel.format(month)),
      child: Container(
        decoration: BoxDecoration(
          color: onHero
              ? colors.heroOnSurface.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          border: Border.all(
            color: onHero
                ? colors.heroOnSurface.withValues(alpha: 0.14)
                : colors.softBorder,
          ),
        ),
        child: Row(
          children: [
            _ArrowButton(
              tooltip: 'Mês anterior',
              icon: Icons.chevron_left_rounded,
              color: muted,
              onPressed: () => setMonth(_shift(month, -1)),
            ),
            Expanded(
              child: Center(
                child: Text(
                  capitalized(
                    context.isPhone
                        ? _monthShort.format(month)
                        : _monthLabel.format(month),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // O atalho para hoje só existe quando há para onde voltar; antes
            // ele era um texto de 12px sem área de toque própria.
            if (!isCurrent)
              Tooltip(
                message: 'Voltar ao mês atual',
                child: TextButton(
                  onPressed: () => setMonth(DateTime(now.year, now.month)),
                  style: TextButton.styleFrom(
                    foregroundColor: onHero
                        ? colors.heroIncome
                        : theme.colorScheme.primary,
                    minimumSize: const Size(0, kHopeMinTapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: HopeSpacing.xs,
                    ),
                  ),
                  child: const Text('Hoje'),
                ),
              ),
            _ArrowButton(
              tooltip: 'Próximo mês',
              icon: Icons.chevron_right_rounded,
              color: muted,
              onPressed: () => setMonth(_shift(month, 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      color: color,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(kHopeMinTapTarget),
      ),
    );
  }
}
