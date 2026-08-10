import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/finance_calc.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../components/hope_components.dart';

const _investmentTypes = {
  'fixed_income': 'Renda fixa',
  'stocks': 'Ações',
  'funds': 'Fundos',
  'pension': 'Previdência',
  'crypto': 'Cripto',
  'other': 'Outros',
};

enum _InvestmentMovementType { deposit, withdrawal, earnings }

extension on _InvestmentMovementType {
  String get persistedValue => switch (this) {
    _InvestmentMovementType.deposit => 'deposit',
    _InvestmentMovementType.withdrawal => 'withdrawal',
    _InvestmentMovementType.earnings => 'yield',
  };
}

class InvestmentsScreen extends ConsumerWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investmentsAsync = ref.watch(investmentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Investimentos',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          AppBarPrimaryAction(
            label: 'Investimento',
            icon: Icons.add_rounded,
            tooltip: 'Novo investimento',
            onPressed: () => _showInvestmentSheet(context, ref),
          ),
        ],
      ),
      body: investmentsAsync.when(
        loading: () => const HopeSkeleton(rows: 4),
        error: (error, _) => HopeErrorState.load(
          error,
          what: 'seus investimentos',
          onRetry: () => ref.invalidate(investmentsProvider),
        ),
        data: (investments) {
          if (investments.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.show_chart_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum investimento',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Acompanhe sua carteira e a evolução do patrimônio.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final totalApplied = investments.fold<double>(
            0,
            (s, i) => s + i.appliedAmount,
          );
          final totalCurrent = investments.fold<double>(
            0,
            (s, i) => s + i.currentAmount,
          );
          final profit = profitabilityPercent(totalApplied, totalCurrent);

          return ListView(
            padding: EdgeInsets.fromLTRB(
              context.pagePadding,
              HopeSpacing.xs,
              context.pagePadding,
              // Espaço para o botão flutuante de lançamento da casca.
              120,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Summary(
                          label: 'Aplicado',
                          value: formatMoney(totalApplied),
                        ),
                      ),
                      Expanded(
                        child: _Summary(
                          label: 'Atual',
                          value: formatMoney(totalCurrent),
                        ),
                      ),
                      Expanded(
                        child: _Summary(
                          label: 'Rentabilidade',
                          value: profit == null
                              ? '—'
                              : '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2).replaceAll('.', ',')}%',
                          color: profit == null
                              ? null
                              : (profit >= 0
                                    ? context.hopeColors.success
                                    : context.hopeColors.expense),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _InvestmentEvolutionCard(totalCurrent: totalCurrent),
              const SizedBox(height: 10),
              for (final investment in investments) ...[
                _InvestmentTile(
                  investment: investment,
                  onTap: () => _showInvestmentSheet(
                    context,
                    ref,
                    investment: investment,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showInvestmentSheet(
    BuildContext context,
    WidgetRef ref, {
    LocalInvestment? investment,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _InvestmentForm(investment: investment),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _InvestmentTile extends StatelessWidget {
  const _InvestmentTile({required this.investment, required this.onTap});

  final LocalInvestment investment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profit = profitabilityPercent(
      investment.appliedAmount,
      investment.currentAmount,
    );
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: context.hopeColors.card.withValues(alpha: 0.14),
          child: Icon(
            Icons.show_chart_outlined,
            color: context.hopeColors.card,
            size: 20,
          ),
        ),
        title: Text(investment.name),
        subtitle: Text(
          [
            _investmentTypes[investment.type] ?? investment.type,
            if (investment.institution != null &&
                investment.institution!.isNotEmpty)
              investment.institution!,
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(investment.currentAmount),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            if (profit != null)
              Text(
                '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2).replaceAll('.', ',')}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: profit >= 0 ? context.hopeColors.success : context.hopeColors.expense,
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _InvestmentEvolutionCard extends ConsumerWidget {
  const _InvestmentEvolutionCard({required this.totalCurrent});

  final double totalCurrent;

  static final _monthLabel = DateFormat.MMM('pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(allInvestmentMovementsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: movementsAsync.when(
          loading: () => const SizedBox(
            height: 190,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 120,
            child: HopeErrorState.load(
              error,
              what: 'a evolução da carteira',
              compact: true,
            ),
          ),
          data: (movements) {
            final points = investmentValueHistory(
              currentTotal: totalCurrent,
              movements: [
                for (final m in movements)
                  (
                    type: m.type,
                    amount: m.amount,
                    movementDate: m.movementDate,
                  ),
              ],
            );
            final totalDeposits = points.fold<double>(
              0,
              (s, p) => s + p.deposits,
            );
            final totalWithdrawals = points.fold<double>(
              0,
              (s, p) => s + p.withdrawals,
            );
            final totalYields = points.fold<double>(0, (s, p) => s + p.yields);
            final start = points.first.balance;
            final variation = start == 0
                ? null
                : (points.last.balance - start) / start.abs() * 100;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Evolução do patrimônio',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Últimos 6 meses',
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
                    if (variation != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (variation >= 0
                                      ? context.hopeColors.success
                                      : context.hopeColors.expense)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${variation >= 0 ? '+' : ''}${variation.toStringAsFixed(2).replaceAll('.', ',')}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: variation >= 0
                                ? context.hopeColors.success
                                : context.hopeColors.expense,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: _EvolutionLineChart(points: points),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final point in points)
                      Expanded(
                        child: Text(
                          _capitalize(
                            _monthLabel.format(DateTime.parse(point.monthIso)),
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MovementStat(
                        label: 'Aportes',
                        value: totalDeposits,
                        color: context.hopeColors.investment,
                      ),
                    ),
                    Expanded(
                      child: _MovementStat(
                        label: 'Resgates',
                        value: totalWithdrawals,
                        color: context.hopeColors.expense,
                      ),
                    ),
                    Expanded(
                      child: _MovementStat(
                        label: 'Rendimentos',
                        value: totalYields,
                        color: totalYields >= 0
                            ? context.hopeColors.success
                            : context.hopeColors.expense,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _MovementStat extends StatelessWidget {
  const _MovementStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          formatMoney(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _EvolutionLineChart extends StatelessWidget {
  const _EvolutionLineChart({required this.points});

  final List<InvestmentMonthPoint> points;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 300,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 150,
        );
        return CustomPaint(
          size: size,
          painter: _EvolutionLinePainter(
            points: points,
            color: context.hopeColors.card,
            surfaceColor: Theme.of(context).cardColor,
            labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
      },
    );
  }
}

const _chartTopPad = 26.0;
const _chartBottomPad = 6.0;

List<Offset> _evolutionChartLayout(List<double> values, Size size) {
  if (values.isEmpty) return const [];
  if (values.length == 1) {
    return [Offset(size.width / 2, size.height / 2)];
  }
  final minV = values.reduce(math.min);
  final maxV = values.reduce(math.max);
  final range = maxV - minV;
  final usableHeight = math.max(
    0.0,
    size.height - _chartTopPad - _chartBottomPad,
  );
  final step = size.width / (values.length - 1);
  return [
    for (var i = 0; i < values.length; i++)
      Offset(
        i * step,
        _chartTopPad +
            (range <= 0
                ? usableHeight / 2
                : usableHeight - ((values[i] - minV) / range) * usableHeight),
      ),
  ];
}

class _EvolutionLinePainter extends CustomPainter {
  const _EvolutionLinePainter({
    required this.points,
    required this.color,
    required this.surfaceColor,
    required this.labelStyle,
  });

  final List<InvestmentMonthPoint> points;
  final Color color;
  final Color surfaceColor;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) p.balance];
    if (values.isEmpty || size.isEmpty) return;
    final offsets = _evolutionChartLayout(values, size);

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      final prev = offsets[i - 1];
      final curr = offsets[i];
      final midX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    final dotFill = Paint()..color = color;
    final dotRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = surfaceColor;
    for (final offset in offsets) {
      canvas.drawCircle(offset, 4, dotRing);
      canvas.drawCircle(offset, 3, dotFill);
    }

    _drawValueLabel(canvas, size, offsets.first, values.first, false);
    if (offsets.length > 1) {
      _drawValueLabel(canvas, size, offsets.last, values.last, true);
    }
  }

  void _drawValueLabel(
    Canvas canvas,
    Size size,
    Offset anchor,
    double value,
    bool alignRight,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: formatMoney(value), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final maxDx = math.max(0.0, size.width - painter.width);
    final dx = (alignRight ? anchor.dx - painter.width : anchor.dx).clamp(
      0.0,
      maxDx,
    );
    final dy = math.max(0.0, anchor.dy - painter.height - 8);
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _EvolutionLinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.surfaceColor != surfaceColor;
}

Future<void> _confirmDeleteInvestmentMovement(
  BuildContext parentContext,
  BuildContext sheetContext,
  WidgetRef ref,
  LocalInvestment investment,
  LocalInvestmentMovement movement,
) async {
  final label = switch (movement.type) {
    'deposit' => 'aporte',
    'withdrawal' => 'resgate',
    _ => 'rendimento',
  };
  final confirmed = await showDialog<bool>(
    context: sheetContext,
    builder: (dialogContext) => AlertDialog(
      title: Text('Excluir $label?'),
      content: Text(
        'A movimentação de ${formatMoney(movement.amount.abs())} será removida e o saldo do investimento será recalculado.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: dialogContext.hopeColors.expense,
          ),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!parentContext.mounted) return;

  final messenger = ScaffoldMessenger.of(parentContext);
  await ref
      .read(financeRepositoryProvider)
      .deleteInvestmentMovement(investment: investment, movement: movement);
  ref.read(syncServiceProvider).syncNow();
  if (sheetContext.mounted) Navigator.pop(sheetContext);
  // O formulário abaixo do extrato contém uma cópia da posição anterior.
  // Fecha-o para impedir que um "Salvar" posterior restaure o saldo antigo.
  if (parentContext.mounted) Navigator.pop(parentContext);
  messenger.showSnackBar(
    SnackBar(
      content: Text('${label[0].toUpperCase()}${label.substring(1)} excluído'),
    ),
  );
}

void _showInvestmentStatement(
  BuildContext parentContext,
  LocalInvestment investment,
) {
  showModalBottomSheet<void>(
    context: parentContext,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.78,
      child: Consumer(
        builder: (context, ref, _) {
          final movements = ref.watch(
            investmentMovementsProvider(investment.id),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: context.hopeColors.card.withValues(alpha: 0.14),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: context.hopeColors.card,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Extrato do investimento',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            investment.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Saldo atual',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          formatMoney(investment.currentAmount),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: movements.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => HopeErrorState.load(
                    error,
                    what: 'o extrato do investimento',
                    compact: true,
                  ),
                  data: (items) => items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 44,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Nenhuma movimentação registrada',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Aportes, resgates e rendimentos lançados a partir de agora aparecerão aqui.',
                                  textAlign: TextAlign.center,
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
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(indent: 56),
                          itemBuilder: (context, index) {
                            final movement = items[index];
                            final isWithdrawal = movement.type == 'withdrawal';
                            final signedAmount = isWithdrawal
                                ? -movement.amount
                                : movement.amount;
                            final (
                              label,
                              icon,
                              color,
                            ) = switch (movement.type) {
                              'deposit' => (
                                'Aporte',
                                Icons.add_circle_outline,
                                context.hopeColors.investment,
                              ),
                              'withdrawal' => (
                                'Resgate',
                                Icons.remove_circle_outline,
                                context.hopeColors.expense,
                              ),
                              _ => (
                                'Rendimento',
                                Icons.trending_up_rounded,
                                movement.amount < 0
                                    ? context.hopeColors.expense
                                    : context.hopeColors.success,
                              ),
                            };
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.12),
                                child: Icon(icon, color: color, size: 20),
                              ),
                              title: Text(label),
                              subtitle: Text(formatDate(movement.movementDate)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${signedAmount >= 0 ? '+' : '-'}${formatMoney(signedAmount.abs())}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir $label',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline),
                                    color: context.hopeColors.expense,
                                    onPressed: () =>
                                        _confirmDeleteInvestmentMovement(
                                          parentContext,
                                          sheetContext,
                                          ref,
                                          investment,
                                          movement,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _InvestmentForm extends ConsumerStatefulWidget {
  const _InvestmentForm({this.investment});

  final LocalInvestment? investment;

  @override
  ConsumerState<_InvestmentForm> createState() => _InvestmentFormState();
}

class _InvestmentFormState extends ConsumerState<_InvestmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _institution = TextEditingController();
  final _applied = TextEditingController();
  final _current = TextEditingController();
  String _type = 'fixed_income';
  bool _saving = false;
  bool _updatingCurrent = false;

  bool get _editing => widget.investment != null;

  @override
  void initState() {
    super.initState();
    final investment = widget.investment;
    _name.text = investment?.name ?? '';
    _institution.text = investment?.institution ?? '';
    _applied.text = investment == null
        ? ''
        : investment.appliedAmount.toStringAsFixed(2).replaceAll('.', ',');
    _current.text = investment == null
        ? ''
        : investment.currentAmount.toStringAsFixed(2).replaceAll('.', ',');
    _type = investment?.type ?? 'fixed_income';
    _applied.addListener(_updateCurrentFromApplied);
  }

  void _updateCurrentFromApplied() {
    if (_updatingCurrent) return;
    final applied = parseMoney(_applied.text);
    final investment = widget.investment;
    final calculated = applied == null
        ? null
        : investment == null
        ? applied
        : investment.currentAmount + (applied - investment.appliedAmount);
    final text = calculated == null
        ? ''
        : calculated.toStringAsFixed(2).replaceAll('.', ',');
    if (_current.text == text) return;
    _updatingCurrent = true;
    _current.text = text;
    _updatingCurrent = false;
  }

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _applied.removeListener(_updateCurrentFromApplied);
    _applied.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(financeRepositoryProvider)
        .upsertInvestment(
          id: widget.investment?.id,
          name: _name.text.trim(),
          type: _type,
          institution: _institution.text.trim().isEmpty
              ? null
              : _institution.text.trim(),
          appliedAmount: parseMoney(_applied.text) ?? 0,
          currentAmount: parseMoney(_current.text) ?? 0,
          lastQuoteDate: todayIso(),
          currentVersion: widget.investment?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing ? 'Investimento atualizado' : 'Investimento cadastrado',
          ),
        ),
      );
    }
  }

  /// Alteração rápida da posição: aporte, resgate ou rendimento.
  Future<void> _movement(_InvestmentMovementType movementType) async {
    final investment = widget.investment;
    if (investment == null) return;
    final title = switch (movementType) {
      _InvestmentMovementType.deposit => 'Novo aporte',
      _InvestmentMovementType.withdrawal => 'Resgate',
      _InvestmentMovementType.earnings => 'Lançamento de rendimento',
    };
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(
            decimal: true,
            signed: movementType == _InvestmentMovementType.earnings,
          ),
          decoration: InputDecoration(
            labelText: 'Valor',
            prefixText: 'R\$ ',
            helperText: movementType == _InvestmentMovementType.earnings
                ? 'Use valor negativo para registrar uma perda'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, parseMoney(controller.text)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null ||
        (movementType == _InvestmentMovementType.earnings
            ? amount == 0
            : amount <= 0)) {
      return;
    }
    await ref
        .read(financeRepositoryProvider)
        .registerInvestmentMovement(
          investment: investment,
          movementType: movementType.persistedValue,
          amount: amount,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (movementType) {
            _InvestmentMovementType.deposit => 'Aporte registrado',
            _InvestmentMovementType.withdrawal => 'Resgate registrado',
            _InvestmentMovementType.earnings => 'Rendimento registrado',
          }),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final investment = widget.investment;
    if (investment == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir investimento?'),
        content: Text('"${investment.name}" será removido da carteira.'),
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
    await ref.read(financeRepositoryProvider).deleteInvestment(investment);
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Investimento excluído')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumFormSheet(
      title: _editing ? 'Editar investimento' : 'Novo investimento',
      subtitle: 'Controle posição, instituição e evolução do patrimônio.',
      icon: Icons.show_chart_outlined,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Identificação',
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome',
                prefixIcon: Icon(Icons.show_chart_outlined),
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
                for (final e in _investmentTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'fixed_income'),
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
          title: 'Posição',
          children: [
            TextFormField(
              controller: _applied,
              decoration: const InputDecoration(
                labelText: 'Valor aplicado',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.savings_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextFormField(
              controller: _current,
              readOnly: true,
              enableInteractiveSelection: false,
              showCursor: false,
              decoration: const InputDecoration(
                labelText: 'Valor atual',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.calculate_outlined),
                helperText:
                    'Aplicado (com aportes) − resgates + rendimentos',
              ),
            ),
            if (_editing) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _movement(_InvestmentMovementType.deposit),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Aporte'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _movement(_InvestmentMovementType.withdrawal),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Resgate'),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _movement(_InvestmentMovementType.earnings),
                  icon: const Icon(Icons.trending_up_rounded, size: 18),
                  label: const Text('Lançar rendimento'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () =>
                      _showInvestmentStatement(context, widget.investment!),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Ver extrato do investimento'),
                ),
              ),
            ],
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
      destructiveAction: _editing
          ? TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: context.hopeColors.expense),
              label: const Text('Excluir investimento'),
              style: TextButton.styleFrom(foregroundColor: context.hopeColors.expense),
            )
          : null,
    );
  }
}
