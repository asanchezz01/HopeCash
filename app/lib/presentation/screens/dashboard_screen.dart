import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import '../widgets/brand_logo.dart';
import '../widgets/debt_payment_sheet.dart';
import '../widgets/month_navigator.dart';
import 'transactions_screen.dart' show showTransactionActions;

final _dashboardValuesHiddenProvider = StateProvider<bool>((ref) => false);

class _DashboardPrivacy extends InheritedWidget {
  const _DashboardPrivacy({required this.hidden, required super.child});

  final bool hidden;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DashboardPrivacy>()?.hidden ??
      false;

  @override
  bool updateShouldNotify(_DashboardPrivacy oldWidget) =>
      hidden != oldWidget.hidden;
}

String _money(BuildContext context, num? value) =>
    _DashboardPrivacy.of(context) ? 'R\$ ••••' : formatMoney(value);

String _privateText(
  BuildContext context,
  String visible, {
  String hidden = '••••',
}) => _DashboardPrivacy.of(context) ? hidden : visible;

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    final summary = ref.watch(dashboardProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? [];
    final subcategories = ref.watch(subcategoriesProvider).valueOrNull ?? [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final cards = ref.watch(creditCardsProvider).valueOrNull ?? [];
    final goals = ref.watch(goalsProvider).valueOrNull ?? [];
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;
    final valuesHidden = ref.watch(_dashboardValuesHiddenProvider);
    final primaryGoal = _primaryGoal(goals);

    final hopeUnavailable = ref.watch(aiAvailableProvider).valueOrNull == false;
    final firstName = user?.name.split(' ').first ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: context.pagePadding,
        title: Row(
          children: [
            const HopeCashLogo(compact: true, iconSize: 32),
            const SizedBox(width: HopeSpacing.xs),
            Expanded(
              child: Text(
                firstName.isEmpty ? 'HopeCash' : 'Olá, $firstName',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Hope perdeu o lugar na barra inferior (que agora só tem destinos);
          // no celular ela vive aqui e na tela Mais. Uma falha transitória no
          // health-check muda o estado do atalho, mas nunca o remove.
          if (context.isCompact)
            IconButton(
              key: const ValueKey('dashboard-hope-action'),
              tooltip: hopeUnavailable
                  ? 'Hope temporariamente indisponível — toque para tentar'
                  : 'Conversar com a Hope',
              icon: Icon(
                Icons.auto_awesome_outlined,
                color: hopeUnavailable ? context.hopeColors.warning : null,
              ),
              onPressed: () => context.push('/ai-chat'),
            ),
          IconButton(
            tooltip: valuesHidden ? 'Mostrar valores' : 'Ocultar valores',
            icon: Icon(
              valuesHidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () =>
                ref.read(_dashboardValuesHiddenProvider.notifier).state =
                    !valuesHidden,
          ),
          IconButton(
            tooltip: pending > 0
                ? '$pending ${pending == 1 ? 'alteração aguardando' : 'alterações aguardando'} sincronização'
                : 'Tudo sincronizado',
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: Icon(
                pending > 0
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_done_outlined,
              ),
            ),
            onPressed: () => ref.read(syncServiceProvider).syncNow(),
          ),
          SizedBox(width: context.pagePadding - HopeSpacing.sm),
        ],
      ),
      body: summary.when(
        loading: () => const HopeSkeleton(rows: 5),
        error: (error, _) => HopeErrorState.load(
          error,
          what: 'o seu painel',
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
        data: (data) => _DashboardPrivacy(
          hidden: valuesHidden,
          child: RefreshIndicator(
            onRefresh: () {
              ref.invalidate(aiAvailableProvider);
              return ref.read(syncServiceProvider).syncNow();
            },
            child: _DashboardContent(
              summary: data,
              categories: categories,
              subcategories: subcategories,
              accounts: accounts,
              cards: cards,
              primaryGoal: primaryGoal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.summary,
    required this.categories,
    required this.subcategories,
    required this.accounts,
    required this.cards,
    required this.primaryGoal,
  });

  final DashboardSummary summary;
  final List<LocalCategory> categories;
  final List<LocalSubcategory> subcategories;
  final List<LocalAccount> accounts;
  final List<LocalCreditCard> cards;
  final LocalGoal? primaryGoal;

  @override
  Widget build(BuildContext context) {
    final activeCards = cards.where((card) => card.isActive).toList();
    final result = summary.monthEconomy;
    final committedExpense = summary.monthExpense + summary.monthPlannedExpense;
    final committed = summary.monthIncome <= 0
        ? 0.0
        : (committedExpense / summary.monthIncome).clamp(0.0, 1.0);
    final topCategory = _topCategoryName(summary.spentByCategory, categories);
    final overdueEntries = _overdueEntries(summary.financialAgendaEntries);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= HopeBreakpoints.desktop;
        final pageWidth = wide ? kHopeContentMaxWidth : double.infinity;
        final sidePadding = constraints.maxWidth >= HopeBreakpoints.tablet
            ? HopeSpacing.xxl
            : HopeSpacing.md;

        final categoryBudget = _CategoryPanel(
          spentByCategory: summary.spentByCategory,
          plannedByCategory: summary.budgetPlannedByCategory,
          categoryNames: {for (final c in categories) c.id: c.name},
        );
        final categoryDonut = _CategoryDonutPanel(
          spentByCategory: summary.spentByCategory,
          spentBySubcategory: summary.spentBySubcategory,
          expenseTransactions: summary.expenseTransactions,
          categories: categories,
          subcategories: subcategories,
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            sidePadding,
            HopeSpacing.xs,
            sidePadding,
            // Espaço para o botão flutuante de lançamento não cobrir a última
            // linha da lista.
            120,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: pageWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // O seletor de mês vive dentro do painel: ele governa todos
                    // os números mostrados ali, então fica junto deles.
                    _BalancePanel(
                      total: summary.totalBalance,
                      openingBalance: summary.monthOpeningBalance,
                      income: summary.monthIncome,
                      expense: summary.monthExpense,
                      plannedExpense: summary.monthPlannedExpense,
                      result: result,
                    ),
                    const SizedBox(height: HopeSpacing.sm),
                    _InsightStrip(
                      result: result,
                      committed: committed,
                      overdueEntries: overdueEntries,
                      topCategory: topCategory,
                    ),

                    // A agenda responde "o que vence agora?" — a pergunta mais
                    // urgente do painel. No celular ela estava no rodapé.
                    const SectionTitle(
                      title: 'Agenda financeira',
                      subtitle: 'O que vence no mês selecionado',
                    ),
                    _UpcomingPanel(
                      entries: summary.financialAgendaEntries,
                      accounts: accounts,
                      cards: activeCards,
                      accountBalances: summary.accountBalances,
                      cardOpenByCard: summary.cardOpenByCard,
                    ),

                    const SectionTitle(
                      title: 'Fluxo de caixa',
                      subtitle: 'Receitas e despesas dos últimos seis meses',
                    ),
                    const _CashFlowCard(),

                    if (wide) ...[
                      const SizedBox(height: HopeSpacing.lg),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SectionTitle(
                                    title: 'Orçamento por categoria',
                                    action: '${categories.length} categorias',
                                  ),
                                  categoryBudget,
                                ],
                              ),
                            ),
                            const SizedBox(width: HopeSpacing.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SectionTitle(
                                    title: 'Distribuição de despesas',
                                  ),
                                  categoryDonut,
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      SectionTitle(
                        title: 'Orçamento por categoria',
                        action: '${categories.length} categorias',
                      ),
                      categoryBudget,
                      const SectionTitle(title: 'Distribuição de despesas'),
                      categoryDonut,
                    ],

                    SectionTitle(
                      title: 'Meta financeira',
                      action: primaryGoal == null
                          ? null
                          : _privateText(
                              context,
                              _goalProgressLabel(primaryGoal!),
                            ),
                    ),
                    _GoalSpotlight(goal: primaryGoal),
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

class _InsightStrip extends StatelessWidget {
  const _InsightStrip({
    required this.result,
    required this.committed,
    required this.overdueEntries,
    required this.topCategory,
  });

  final double result;
  final double committed;
  final List<FinancialAgendaEntry> overdueEntries;
  final String? topCategory;

  @override
  Widget build(BuildContext context) {
    final colors = context.hopeColors;
    final hidden = _DashboardPrivacy.of(context);
    final commitment = (committed * 100).round();
    final overdueCount = overdueEntries.length;
    // A economia do mês saiu daqui: ela já é a linha de projeção do painel
    // acima, e repetir o mesmo número duas vezes na mesma dobra só dilui.
    return Padding(
      padding: const EdgeInsets.only(top: HopeSpacing.xs),
      child: Wrap(
        spacing: HopeSpacing.xs,
        runSpacing: HopeSpacing.xs,
        children: [
          MetricPill(
            label: 'Renda comprometida',
            value: _privateText(context, '$commitment%', hidden: '••%'),
            color: hidden
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : committed > 0.8
                ? colors.warning
                : colors.investment,
            icon: Icons.speed_rounded,
          ),
          MetricPill(
            label: 'Vencimentos',
            value: overdueCount > 0
                ? _privateText(
                    context,
                    overdueCount == 1 ? '1 atrasado' : '$overdueCount atrasados',
                    hidden: '•• atrasados',
                  )
                : 'em dia',
            color: overdueCount > 0 ? colors.expense : colors.success,
            icon: overdueCount > 0
                ? Icons.error_outline_rounded
                : Icons.event_available_outlined,
            onTap: overdueCount == 0
                ? null
                : () => _showOverdueSheet(context, overdueEntries),
          ),
          if (topCategory != null)
            MetricPill(
              label: 'Maior gasto',
              value: _privateText(context, topCategory!),
              color: colors.card,
              icon: Icons.donut_large_rounded,
            ),
        ],
      ),
    );
  }
}

void _showOverdueSheet(
  BuildContext context,
  List<FinancialAgendaEntry> entries,
) {
  final hidden = _DashboardPrivacy.of(context);
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final sorted = [...entries]
        ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
      return _DashboardPrivacy(
        hidden: hidden,
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              HopeSpacing.lg,
              HopeSpacing.xs,
              HopeSpacing.lg,
              HopeSpacing.lg,
            ),
            children: [
              Text(
                'Vencimentos atrasados',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: HopeSpacing.sm),
              for (final entry in sorted)
                Padding(
                  padding: const EdgeInsets.only(bottom: HopeSpacing.sm),
                  child: AppSurface(
                    child: Row(
                      children: [
                        FinanceIconBadge(
                          icon: entry.type == 'income'
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: entry.type == 'income'
                              ? context.hopeColors.income
                              : context.hopeColors.expense,
                        ),
                        const SizedBox(width: HopeSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                [
                                  if (entry.dueDate != null)
                                    'Venceu em ${formatDate(entry.dueDate)}',
                                  if (entry.isBudget) 'orçamento',
                                  if (entry.isDebt) 'dívida',
                                ].join(' · '),
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
                        Text(
                          _money(context, entry.amount),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _GoalSpotlight extends StatelessWidget {
  const _GoalSpotlight({required this.goal});

  final LocalGoal? goal;

  @override
  Widget build(BuildContext context) {
    if (goal == null) {
      return const AppSurface(
        child: PremiumEmptyState(
          icon: Icons.flag_outlined,
          title: 'Defina a próxima conquista',
          subtitle:
              'Uma meta transforma o saldo em progresso visível e ajuda a decidir o que cortar primeiro.',
        ),
      );
    }

    final g = goal!;
    final progress = g.targetAmount <= 0
        ? 0.0
        : (g.accumulatedAmount / g.targetAmount).clamp(0.0, 1.0);
    final visibleProgress = _DashboardPrivacy.of(context) ? 0.0 : progress;
    final remaining = (g.targetAmount - g.accumulatedAmount).clamp(
      0.0,
      double.infinity,
    );
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FinanceIconBadge(
                icon: Icons.flag_outlined,
                color: context.hopeColors.investment,
              ),
              const SizedBox(width: HopeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Faltam ${_money(context, remaining)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _privateText(
                  context,
                  '${(progress * 100).round()}%',
                  hidden: '••%',
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.hopeColors.investment,
                ),
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.md),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: visibleProgress),
            duration: HopeMotion.slow,
            curve: HopeMotion.emphasized,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              borderRadius: BorderRadius.circular(HopeRadius.pill),
              color: context.hopeColors.investment,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            ),
          ),
        ],
      ),
    );
  }
}

enum _CashFlowChartType { area, line, bar }

const _cashFlowMonthLabels = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

DateTime _monthOnly(DateTime value) => DateTime(value.year, value.month);

String _cashFlowPeriodLabel(DateTime start, DateTime end) {
  final startLabel = _cashFlowMonthLabels[start.month - 1];
  final endLabel = _cashFlowMonthLabels[end.month - 1];
  final label = start.year == end.year
      ? '$startLabel – $endLabel ${end.year}'
      : '$startLabel ${start.year} – $endLabel ${end.year}';
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

class _CashFlowCard extends ConsumerStatefulWidget {
  const _CashFlowCard();

  @override
  ConsumerState<_CashFlowCard> createState() => _CashFlowCardState();
}

class _CashFlowCardState extends ConsumerState<_CashFlowCard> {
  _CashFlowChartType _chartType = _CashFlowChartType.area;
  late DateTime _visibleEndMonth;

  @override
  void initState() {
    super.initState();
    _visibleEndMonth = _monthOnly(DateTime.now());
  }

  void _shiftWindow(int months) {
    final currentMonth = _monthOnly(DateTime.now());
    var next = DateTime(_visibleEndMonth.year, _visibleEndMonth.month + months);
    if (next.isAfter(currentMonth)) next = currentMonth;
    setState(() => _visibleEndMonth = next);
  }

  @override
  Widget build(BuildContext context) {
    final visibleStartMonth = DateTime(
      _visibleEndMonth.year,
      _visibleEndMonth.month - 5,
    );
    final currentMonth = _monthOnly(DateTime.now());
    final isCurrentWindow = _visibleEndMonth == currentMonth;
    final periodLabel = _cashFlowPeriodLabel(
      visibleStartMonth,
      _visibleEndMonth,
    );
    final cashFlow = ref.watch(cashFlowWindowProvider(_visibleEndMonth));

    return AppSurface(
      padding: const EdgeInsets.all(HopeSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          // O título do cartão saiu: o cabeçalho da seção logo acima já diz
          // "Fluxo de caixa". Repetir custava uma linha e, no tablet, o espaço
          // que os controles precisavam.
          final periodNavigator = _CashFlowPeriodNavigator(
            label: periodLabel,
            canAdvance: !isCurrentWindow,
            onPrevious: () => _shiftWindow(-1),
            onNext: () => _shiftWindow(1),
          );
          final typeSelector = _CashFlowTypeSelector(
            value: _chartType,
            onChanged: (value) => setState(() => _chartType = value),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                periodNavigator,
                const SizedBox(height: HopeSpacing.xs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: typeSelector,
                ),
              ] else
                Row(
                  children: [
                    periodNavigator,
                    const Spacer(),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: typeSelector,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: HopeSpacing.sm),
              // Wrap, não Row: com fonte ampliada os dois rótulos passam da
              // largura de um celular e precisam quebrar linha.
              Wrap(
                spacing: HopeSpacing.md,
                runSpacing: HopeSpacing.xxs,
                children: [
                  _CashFlowLegendItem(
                    label: 'Receitas',
                    color: context.hopeColors.income,
                  ),
                  _CashFlowLegendItem(
                    label: 'Despesas',
                    color: context.hopeColors.expense,
                  ),
                ],
              ),
              const SizedBox(height: HopeSpacing.sm),
              SizedBox(
                height: compact ? 220 : 270,
                width: double.infinity,
                child: cashFlow.when(
                  loading: () => const Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                  error: (_, _) => Center(
                    child: Text(
                      'Não foi possível carregar o fluxo de caixa.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  data: (points) => Semantics(
                    label: 'Gráfico de fluxo de caixa de $periodLabel',
                    child: CustomPaint(
                      painter: _CashFlowChartPainter(
                        points: points,
                        type: _chartType,
                        incomeColor: context.hopeColors.income,
                        expenseColor: context.hopeColors.expense,
                        gridColor: context.hopeColors.softBorder,
                        labelColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        hidden: _DashboardPrivacy.of(context),
                        compact: compact,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CashFlowTypeSelector extends StatelessWidget {
  const _CashFlowTypeSelector({required this.value, required this.onChanged});

  final _CashFlowChartType value;
  final ValueChanged<_CashFlowChartType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_CashFlowChartType>(
      segments: const [
        ButtonSegment(value: _CashFlowChartType.area, label: Text('Área')),
        ButtonSegment(value: _CashFlowChartType.line, label: Text('Linha')),
        ButtonSegment(value: _CashFlowChartType.bar, label: Text('Barra')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(
          Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CashFlowPeriodNavigator extends StatelessWidget {
  const _CashFlowPeriodNavigator({
    required this.label,
    required this.canAdvance,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final bool canAdvance;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // As setas respeitam o alvo mínimo de toque e o rótulo do período encolhe
    // antes de qualquer coisa estourar — o período pode virar do ano
    // ("Ago 2025 – Jan 2026") e ficar bem mais largo que o normal.
    Widget arrow(String tooltip, IconData icon, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(kHopeMinTapTarget),
            padding: EdgeInsets.zero,
          ),
        );

    return Semantics(
      label: 'Período do gráfico',
      value: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: kHopeMinTapTarget),
        decoration: BoxDecoration(
          border: Border.all(color: context.hopeColors.softBorder),
          borderRadius: BorderRadius.circular(HopeRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow('Recuar um mês', Icons.chevron_left_rounded, onPrevious),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HopeSpacing.xxs),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            arrow(
              canAdvance ? 'Avançar um mês' : 'Período atual',
              Icons.chevron_right_rounded,
              canAdvance ? onNext : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CashFlowLegendItem extends StatelessWidget {
  const _CashFlowLegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CashFlowChartPainter extends CustomPainter {
  const _CashFlowChartPainter({
    required this.points,
    required this.type,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
    required this.labelColor,
    required this.hidden,
    required this.compact,
  });

  final List<CashFlowMonthPoint> points;
  final _CashFlowChartType type;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;
  final Color labelColor;
  final bool hidden;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.isEmpty) return;
    final values = [
      for (final point in points) hidden ? 0.0 : point.income,
      for (final point in points) hidden ? 0.0 : point.expense,
    ];
    final rawMax = values.fold<double>(0, math.max);
    final chartMax = _niceChartMax(rawMax);
    final left = compact ? 42.0 : 54.0;
    final plot = Rect.fromLTRB(left, 8, size.width - 6, size.height - 30);
    if (plot.width <= 0 || plot.height <= 0) return;

    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = gridColor.withValues(alpha: 0.72)
          ..strokeWidth = 1,
      );
      _paintText(
        canvas,
        hidden ? 'R\$ •' : _shortCurrency(chartMax * i / 4),
        Offset(plot.left - 7, y),
        alignRight: true,
        centerVertically: true,
      );
    }

    final incomeOffsets = _offsets(
      [for (final point in points) hidden ? 0 : point.income],
      plot,
      chartMax,
    );
    final expenseOffsets = _offsets(
      [for (final point in points) hidden ? 0 : point.expense],
      plot,
      chartMax,
    );

    switch (type) {
      case _CashFlowChartType.area:
        _paintArea(canvas, incomeOffsets, plot, incomeColor, 0.34);
        _paintArea(canvas, expenseOffsets, plot, expenseColor, 0.58);
      case _CashFlowChartType.line:
        _paintLine(canvas, incomeOffsets, incomeColor);
        _paintLine(canvas, expenseOffsets, expenseColor);
      case _CashFlowChartType.bar:
        _paintBars(canvas, incomeOffsets, expenseOffsets, plot);
    }

    for (var i = 0; i < points.length; i++) {
      final x = type == _CashFlowChartType.bar
          ? plot.left + (plot.width / points.length) * (i + 0.5)
          : plot.left + plot.width * i / math.max(1, points.length - 1);
      _paintText(
        canvas,
        _cashFlowMonthLabels[points[i].month - 1],
        Offset(x, plot.bottom + 14),
        centered: true,
        centerVertically: true,
      );
    }
  }

  List<Offset> _offsets(List<double> values, Rect plot, double maxValue) {
    return [
      for (var i = 0; i < values.length; i++)
        Offset(
          plot.left + plot.width * i / math.max(1, values.length - 1),
          plot.bottom - (values[i] / maxValue).clamp(0.0, 1.0) * plot.height,
        ),
    ];
  }

  void _paintArea(
    Canvas canvas,
    List<Offset> offsets,
    Rect plot,
    Color color,
    double opacity,
  ) {
    final line = _smoothPath(offsets);
    final fill = Path.from(line)
      ..lineTo(offsets.last.dx, plot.bottom)
      ..lineTo(offsets.first.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.72),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintLine(Canvas canvas, List<Offset> offsets, Color color) {
    canvas.drawPath(
      _smoothPath(offsets),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    for (final offset in offsets) {
      canvas.drawCircle(offset, 3.2, Paint()..color = color);
    }
  }

  void _paintBars(
    Canvas canvas,
    List<Offset> income,
    List<Offset> expense,
    Rect plot,
  ) {
    final groupWidth = plot.width / income.length;
    final barWidth = math.min(13.0, groupWidth * 0.32);
    for (var i = 0; i < income.length; i++) {
      final center = plot.left + groupWidth * (i + 0.5);
      final incomeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          center - barWidth - 1,
          income[i].dy,
          center - 1,
          plot.bottom,
        ),
        const Radius.circular(3),
      );
      final expenseRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          center + 1,
          expense[i].dy,
          center + barWidth + 1,
          plot.bottom,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(incomeRect, Paint()..color = incomeColor);
      canvas.drawRRect(expenseRect, Paint()..color = expenseColor);
    }
  }

  Path _smoothPath(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      final previous = offsets[i - 1];
      final current = offsets[i];
      final middle = (previous.dx + current.dx) / 2;
      path.cubicTo(
        middle,
        previous.dy,
        middle,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    return path;
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool centered = false,
    bool alignRight = false,
    bool centerVertically = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var dx = anchor.dx;
    var dy = anchor.dy;
    if (centered) dx -= painter.width / 2;
    if (alignRight) dx -= painter.width;
    if (centerVertically) dy -= painter.height / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  double _niceChartMax(double value) {
    if (value <= 0) return 1000;
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor());
    final step = magnitude / 2;
    return math.max(step * 4, (value / step).ceil() * step).toDouble();
  }

  String _shortCurrency(double value) {
    if (value >= 1000000) {
      final number = value / 1000000;
      return 'R\$ ${number == number.roundToDouble() ? number.toInt() : number.toStringAsFixed(1)} mi';
    }
    if (value >= 1000) {
      final number = value / 1000;
      return 'R\$ ${number == number.roundToDouble() ? number.toInt() : number.toStringAsFixed(1)}k';
    }
    return 'R\$ ${value.round()}';
  }

  @override
  bool shouldRepaint(covariant _CashFlowChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.type != type ||
      oldDelegate.incomeColor != incomeColor ||
      oldDelegate.expenseColor != expenseColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.hidden != hidden ||
      oldDelegate.compact != compact;
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({
    required this.total,
    required this.openingBalance,
    required this.income,
    required this.expense,
    required this.plannedExpense,
    required this.result,
  });

  final double total;
  final double openingBalance;
  final double income;
  final double expense;
  final double plannedExpense;
  final double result;

  @override
  Widget build(BuildContext context) {
    final positive = result >= 0;
    final colors = context.hopeColors;
    final hidden = _DashboardPrivacy.of(context);
    final theme = Theme.of(context);
    // O painel segue o tema (menta no claro, azul-petróleo no escuro) e os
    // acentos vêm da paleta de herói, verificada contra a ponta mais escura de
    // cada gradiente — os acentos comuns reprovam em contraste em pelo menos
    // um dos dois.
    final resultColor = positive ? colors.heroIncome : colors.heroExpense;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final panelPadding = compact ? HopeSpacing.md : HopeSpacing.xl;
        final metrics = [
          (
            'Saldo inicial',
            openingBalance,
            colors.heroInvestment,
            Icons.account_balance_wallet_outlined,
          ),
          ('Receitas', income, colors.heroIncome, Icons.arrow_upward_rounded),
          (
            'Despesas',
            expense,
            colors.heroExpense,
            Icons.arrow_downward_rounded,
          ),
          (
            'Previstas',
            plannedExpense,
            colors.heroWarning,
            Icons.event_outlined,
          ),
        ];

        return Container(
          padding: EdgeInsets.all(panelPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HopeRadius.xl),
            border: Border.all(color: colors.softBorder),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // O tom mais definido começa onde ficam o seletor e o saldo;
              // assim o conteúdo não se perde no fundo da página.
              colors: [colors.heroEnd, colors.heroStart],
            ),
            boxShadow: [
              BoxShadow(
                // Sombra de 20% foi calibrada para o painel escuro; sobre a
                // página clara ela fica pesada demais e suja o verde-menta.
                color: AppTheme.deepBlue.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.20 : 0.08,
                ),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonthNavigator(onHero: true),
              const SizedBox(height: HopeSpacing.md),
              Text(
                'SALDO EM CONTAS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.heroOnSurfaceMuted,
                ),
              ),
              const SizedBox(height: HopeSpacing.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  total,
                  emphasis: MoneyEmphasis.hero,
                  hidden: hidden,
                  color: colors.heroOnSurface,
                  semanticsPrefix: 'Saldo em contas',
                ),
              ),
              const SizedBox(height: HopeSpacing.xs),
              // Projeção de fechamento: saldo inicial + receitas − despesas
              // realizadas e previstas. É o número que responde "vou fechar o
              // mês no azul?".
              Row(
                children: [
                  Icon(
                    positive
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: resultColor,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      positive
                          ? 'Projeção para o fim do mês'
                          : 'Projeção negativa para o fim do mês',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.heroOnSurfaceMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: HopeSpacing.xs),
                  MoneyText(
                    result,
                    emphasis: MoneyEmphasis.caption,
                    hidden: hidden,
                    color: resultColor,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    semanticsPrefix: 'Projeção para o fim do mês',
                  ),
                ],
              ),
              const SizedBox(height: HopeSpacing.md),
              Divider(
                height: 1,
                color: colors.heroOnSurface.withValues(alpha: 0.14),
              ),
              const SizedBox(height: HopeSpacing.sm),
              // Livro-razão: rótulo em cima, número embaixo, colunas alinhadas.
              // Quatro caixas de vidro viravam quatro cartões dentro de um
              // cartão — aqui o alinhamento faz o trabalho da moldura.
              if (compact)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 2; i++)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var j = i; j < metrics.length; j += 2)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: j > 1 ? HopeSpacing.md : 0,
                                  right: i == 0 ? HopeSpacing.sm : 0,
                                ),
                                child: _HeroMetric(
                                  label: metrics[j].$1,
                                  value: metrics[j].$2,
                                  color: metrics[j].$3,
                                  icon: metrics[j].$4,
                                  hidden: hidden,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0)
                        Container(
                          width: 1,
                          height: 34,
                          margin: const EdgeInsets.symmetric(
                            horizontal: HopeSpacing.md,
                          ),
                          color: colors.heroOnSurface.withValues(alpha: 0.12),
                        ),
                      Expanded(
                        child: _HeroMetric(
                          label: metrics[i].$1,
                          value: metrics[i].$2,
                          color: metrics[i].$3,
                          icon: metrics[i].$4,
                          hidden: hidden,
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.hidden,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.hopeColors.heroOnSurfaceMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            value,
            emphasis: MoneyEmphasis.row,
            hidden: hidden,
            color: color,
            semanticsPrefix: label,
          ),
        ),
      ],
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
    required this.spentByCategory,
    required this.plannedByCategory,
    required this.categoryNames,
  });

  final Map<String, double> spentByCategory;
  final Map<String, double> plannedByCategory;
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context) {
    final entries =
        {...spentByCategory.keys, ...plannedByCategory.keys}.map((categoryId) {
          final planned = plannedByCategory[categoryId] ?? 0;
          final realized = spentByCategory[categoryId] ?? 0;
          return _CategoryBudgetEntry(
            id: categoryId,
            name: categoryNames[categoryId] ?? 'Sem categoria',
            planned: planned,
            realized: realized,
          );
        }).toList()..sort((a, b) {
          final aBase = a.planned > 0 ? a.planned : a.realized;
          final bBase = b.planned > 0 ? b.planned : b.realized;
          return bBase.compareTo(aBase);
        });
    final top = entries.take(6).toList();

    return AppSurface(
      child: top.isEmpty
          ? const InlineEmptyState(
              icon: Icons.donut_large_outlined,
              text: 'Sem orçamento ou gastos categorizados neste mês',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BudgetLegend(
                  realizedColor: context.hopeColors.expense,
                  plannedColor: context.hopeColors.warning,
                ),
                const SizedBox(height: HopeSpacing.sm),
                for (final entry in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: HopeSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.name,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            _ExecutionBadge(entry: entry),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Realizado ${_money(context, entry.realized)}',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            Text(
                              entry.planned > 0
                                  ? 'Previsto ${_money(context, entry.planned)}'
                                  : 'Sem orçamento',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: HopeSpacing.xs),
                        _StackedBudgetBar(entry: entry),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CategoryBudgetEntry {
  const _CategoryBudgetEntry({
    required this.id,
    required this.name,
    required this.planned,
    required this.realized,
  });

  final String id;
  final String name;
  final double planned;
  final double realized;

  double? get execution => planned <= 0 ? null : realized / planned;
}

class _CategoryDonutPanel extends ConsumerWidget {
  const _CategoryDonutPanel({
    required this.spentByCategory,
    required this.spentBySubcategory,
    required this.expenseTransactions,
    required this.categories,
    required this.subcategories,
  });

  final Map<String, double> spentByCategory;
  final Map<String, double> spentBySubcategory;
  final List<LocalTransaction> expenseTransactions;
  final List<LocalCategory> categories;
  final List<LocalSubcategory> subcategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slices = _buildCategorySlices(context, spentByCategory, categories);
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    return AppSurface(
      child: slices.isEmpty
          ? const InlineEmptyState(
              icon: Icons.donut_large_outlined,
              text: 'Sem despesas categorizadas para distribuir neste mês',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 430;
                final chart = _InteractiveDonutChart(
                  slices: slices,
                  onSliceTap: (slice) => _showSubcategoryDrillDown(
                    context,
                    ref,
                    slice,
                    spentBySubcategory,
                    expenseTransactions,
                    subcategories,
                  ),
                );
                final legend = _DonutLegend(slices: slices, total: total);
                if (compact) {
                  return Column(
                    children: [
                      SizedBox(
                        height: 190,
                        width: double.infinity,
                        child: chart,
                      ),
                      const SizedBox(height: HopeSpacing.md),
                      legend,
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 190, height: 190, child: chart),
                    const SizedBox(width: HopeSpacing.lg),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
    );
  }
}

class _InteractiveDonutChart extends StatelessWidget {
  const _InteractiveDonutChart({
    required this.slices,
    required this.onSliceTap,
  });

  final List<_DonutSlice> slices;
  final ValueChanged<_DonutSlice> onSliceTap;

  @override
  Widget build(BuildContext context) {
    final hidden = _DashboardPrivacy.of(context);
    final displaySlices = hidden
        ? [
            for (final slice in slices)
              _DonutSlice(
                id: slice.id,
                label: slice.label,
                value: 1,
                color: slice.color,
              ),
          ]
        : slices;
    final total = displaySlices.fold<double>(
      0,
      (sum, slice) => sum + slice.value,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 190.0;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 190.0;
        final dimension = math.max(120.0, math.min(maxWidth, maxHeight));
        final chartSize = Size.square(dimension);

        return Center(
          child: SizedBox.square(
            dimension: dimension,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final slice = _hitTestDonutSlice(
                  details.localPosition,
                  chartSize,
                  displaySlices,
                  total,
                );
                if (slice != null) onSliceTap(slice);
              },
              child: CustomPaint(
                painter: _DonutPainter(slices: displaySlices),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _money(context, total),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

_DonutSlice? _hitTestDonutSlice(
  Offset local,
  Size size,
  List<_DonutSlice> slices,
  double total,
) {
  if (total <= 0 || size.isEmpty) return null;
  final center = Offset(size.width / 2, size.height / 2);
  final vector = local - center;
  final radius = math.min(size.width, size.height) / 2;
  final distance = vector.distance;
  final stroke = radius * 0.32;
  final outerRadius = radius;
  final innerRadius = radius - stroke;

  if (distance < innerRadius || distance > outerRadius) return null;

  var angle = math.atan2(vector.dy, vector.dx) + math.pi / 2;
  if (angle < 0) angle += math.pi * 2;

  var cursor = 0.0;
  for (final slice in slices) {
    final sweep = (slice.value / total) * math.pi * 2;
    if (angle >= cursor && angle < cursor + sweep) {
      return slice;
    }
    cursor += sweep;
  }

  return slices.isEmpty ? null : slices.last;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices});

  final List<_DonutSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;
    final side = math.min(size.width, size.height);
    final stroke = side * 0.16;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    ).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * math.pi * 2;
      paint.color = slice.color;
      canvas.drawArc(rect, start, math.max(0, sweep - 0.018), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

class _DonutLegend extends StatelessWidget {
  const _DonutLegend({required this.slices, required this.total});

  final List<_DonutSlice> slices;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: HopeSpacing.xs),
                Expanded(
                  child: Text(
                    slice.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  total <= 0
                      ? '0%'
                      : _privateText(
                          context,
                          '${((slice.value / total) * 100).round()}%',
                          hidden: '••%',
                        ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: HopeSpacing.sm),
                Text(
                  _money(context, slice.value),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DonutSlice {
  const _DonutSlice({
    required this.id,
    required this.label,
    required this.value,
    required this.color,
  });

  final String id;
  final String label;
  final double value;
  final Color color;
}

List<_DonutSlice> _buildCategorySlices(
  BuildContext context,
  Map<String, double> spentByCategory,
  List<LocalCategory> categories,
) {
  final byId = {for (final category in categories) category.id: category};
  final palette = [
    context.hopeColors.expense,
    context.hopeColors.card,
    context.hopeColors.investment,
    context.hopeColors.warning,
    context.hopeColors.success,
    Theme.of(context).colorScheme.primary,
  ];
  final entries =
      spentByCategory.entries.where((entry) => entry.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (var i = 0; i < entries.length; i++)
      _DonutSlice(
        id: entries[i].key,
        label: byId[entries[i].key]?.name ?? 'Sem categoria',
        value: entries[i].value,
        color: palette[i % palette.length],
      ),
  ];
}

void _showSubcategoryDrillDown(
  BuildContext context,
  WidgetRef ref,
  _DonutSlice category,
  Map<String, double> spentBySubcategory,
  List<LocalTransaction> expenseTransactions,
  List<LocalSubcategory> subcategories,
) {
  final hidden = _DashboardPrivacy.of(context);
  final subcategoryById = {
    for (final subcategory in subcategories) subcategory.id: subcategory,
  };
  final entries =
      spentBySubcategory.entries
          .where((entry) => entry.key.startsWith('${category.id}|'))
          .map((entry) {
            final subcategoryId = entry.key.split('|').last;
            return _DonutSlice(
              id: subcategoryId,
              label: subcategoryById[subcategoryId]?.name ?? 'Sem subcategoria',
              value: entry.value,
              color: category.color,
            );
          })
          .where((entry) => entry.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final totalWithSubcategories = entries.fold<double>(
    0,
    (sum, entry) => sum + entry.value,
  );
  if (category.value - totalWithSubcategories > 0.005) {
    entries.add(
      _DonutSlice(
        id: 'none',
        label: 'Sem subcategoria',
        value: category.value - totalWithSubcategories,
        color: category.color.withValues(alpha: 0.62),
      ),
    );
  }

  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _DashboardPrivacy(
      hidden: hidden,
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            HopeSpacing.lg,
            HopeSpacing.xs,
            HopeSpacing.lg,
            HopeSpacing.lg,
          ),
          children: [
            Text(category.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Distribuição por subcategoria',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HopeSpacing.lg),
            if (entries.isEmpty)
              const InlineEmptyState(
                icon: Icons.label_outline,
                text: 'Nenhuma subcategoria usada nesta categoria',
              )
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: HopeSpacing.sm),
                  child: AppSurface(
                    onTap: () => _showExpenseTransactionsDrillDown(
                      context,
                      ref,
                      category,
                      entry,
                      expenseTransactions,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: entry.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: HopeSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.label,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Toque para ver os lançamentos',
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
                        Text(
                          _money(context, entry.value),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: HopeSpacing.xs),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

void _showExpenseTransactionsDrillDown(
  BuildContext context,
  WidgetRef ref,
  _DonutSlice category,
  _DonutSlice subcategory,
  List<LocalTransaction> expenseTransactions,
) {
  final hidden = _DashboardPrivacy.of(context);
  final transactions =
      expenseTransactions.where((transaction) {
        if (transaction.categoryId != category.id) return false;
        return subcategory.id == 'none'
            ? transaction.subcategoryId == null
            : transaction.subcategoryId == subcategory.id;
      }).toList()..sort((a, b) {
        final byDate = b.competenceDate.compareTo(a.competenceDate);
        return byDate != 0 ? byDate : a.description.compareTo(b.description);
      });
  final total = transactions.fold<double>(
    0,
    (sum, transaction) =>
        sum +
        ((transaction.status == 'paid'
                ? transaction.amount
                : transaction.amountPlanned) ??
            0),
  );

  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _DashboardPrivacy(
      hidden: hidden,
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: HopeSpacing.md),
          children: [
            ListTile(
              title: Text(
                '${category.label} / ${subcategory.label}',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${transactions.length} ${transactions.length == 1 ? 'lançamento' : 'lançamentos'} no período',
              ),
              trailing: Text(
                _money(sheetContext, total),
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: HopeSpacing.md,
                  vertical: HopeSpacing.lg,
                ),
                child: InlineEmptyState(
                  icon: Icons.receipt_long_outlined,
                  text: 'Nenhum lançamento encontrado nesta subcategoria',
                ),
              )
            else
              for (final transaction in transactions)
                ListTile(
                  leading: Icon(
                    transaction.status == 'paid'
                        ? Icons.check_circle_outline
                        : transaction.status == 'overdue'
                        ? Icons.error_outline
                        : Icons.schedule_outlined,
                    color: transaction.status == 'paid'
                        ? sheetContext.hopeColors.success
                        : transaction.status == 'overdue'
                        ? sheetContext.hopeColors.expense
                        : sheetContext.hopeColors.warning,
                  ),
                  title: Text(
                    transaction.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${formatDate(transaction.competenceDate)} · '
                    '${switch (transaction.status) {
                      'paid' => 'Pago',
                      'overdue' => 'Em atraso',
                      _ => 'Previsto',
                    }}',
                  ),
                  trailing: Text(
                    _money(
                      sheetContext,
                      transaction.status == 'paid'
                          ? transaction.amount
                          : transaction.amountPlanned,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showTransactionActions(context, ref, transaction);
                  },
                ),
          ],
        ),
      ),
    ),
  );
}

class _BudgetLegend extends StatelessWidget {
  const _BudgetLegend({
    required this.realizedColor,
    required this.plannedColor,
  });

  final Color realizedColor;
  final Color plannedColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: HopeSpacing.sm,
      runSpacing: HopeSpacing.xs,
      children: [
        _LegendDot(label: 'Realizado', color: realizedColor),
        _LegendDot(label: 'Restante previsto', color: plannedColor),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: HopeSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ExecutionBadge extends StatelessWidget {
  const _ExecutionBadge({required this.entry});

  final _CategoryBudgetEntry entry;

  @override
  Widget build(BuildContext context) {
    final execution = entry.execution;
    final overBudget = execution != null && execution > 1;
    final color = execution == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : overBudget
        ? context.hopeColors.expense
        : context.hopeColors.success;
    final label = execution == null
        ? 'sem meta'
        : _privateText(context, '${(execution * 100).round()}%', hidden: '••%');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HopeRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StackedBudgetBar extends StatelessWidget {
  const _StackedBudgetBar({required this.entry});

  final _CategoryBudgetEntry entry;

  @override
  Widget build(BuildContext context) {
    if (_DashboardPrivacy.of(context)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(HopeRadius.pill),
        child: Container(
          height: 10,
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      );
    }
    final planned = entry.planned;
    final realized = entry.realized;
    final hasBudget = planned > 0;
    final execution = hasBudget ? (realized / planned).clamp(0.0, 1.0) : 1.0;
    final overBudget = hasBudget && realized > planned;
    final realizedColor = overBudget
        ? context.hopeColors.expense
        : context.hopeColors.expense.withValues(alpha: 0.86);
    final plannedColor = hasBudget
        ? context.hopeColors.warning.withValues(alpha: 0.22)
        : Theme.of(context).colorScheme.surfaceContainerHigh;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: execution),
      duration: HopeMotion.slow,
      curve: HopeMotion.emphasized,
      builder: (context, value, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final realizedWidth = hasBudget
                ? totalWidth * value
                : (realized > 0 ? totalWidth : 0.0);
            final remainingWidth = (totalWidth - realizedWidth).clamp(
              0.0,
              totalWidth,
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(HopeRadius.pill),
              child: Row(
                children: [
                  if (realizedWidth > 0)
                    Container(
                      width: realizedWidth,
                      height: 10,
                      color: realizedColor,
                    ),
                  if (remainingWidth > 0)
                    Container(
                      width: remainingWidth,
                      height: 10,
                      color: plannedColor,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _UpcomingPanel extends StatelessWidget {
  const _UpcomingPanel({
    required this.entries,
    required this.accounts,
    required this.cards,
    required this.accountBalances,
    required this.cardOpenByCard,
  });

  final List<FinancialAgendaEntry> entries;
  final List<LocalAccount> accounts;
  final List<LocalCreditCard> cards;
  final Map<String, double> accountBalances;
  final Map<String, double> cardOpenByCard;

  @override
  Widget build(BuildContext context) {
    final groups = _buildUpcomingGroups(
      context,
      entries,
      accounts,
      cards,
      accountBalances,
      cardOpenByCard,
    );

    return AppSurface(
      padding: const EdgeInsets.symmetric(vertical: HopeSpacing.xs),
      child: groups.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(HopeSpacing.md),
              child: InlineEmptyState(
                icon: Icons.event_available_outlined,
                text: 'Nenhum compromisso em aberto para o mês selecionado',
              ),
            )
          : Column(
              children: [
                for (final group in groups) _UpcomingGroupTile(group: group),
              ],
            ),
    );
  }
}

class _UpcomingGroupTile extends StatefulWidget {
  const _UpcomingGroupTile({required this.group});

  final _UpcomingGroup group;

  @override
  State<_UpcomingGroupTile> createState() => _UpcomingGroupTileState();
}

class _UpcomingGroupTileState extends State<_UpcomingGroupTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = _hasDueTodayExpense(widget.group.entries);
  }

  @override
  void didUpdateWidget(covariant _UpcomingGroupTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && _hasDueTodayExpense(widget.group.entries)) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final dueTodayCount = _dueTodayExpenseCount(group.entries);
    final hasDueToday = dueTodayCount > 0;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = hasDueToday ? context.hopeColors.warning : group.color;
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(14);
    final tintAlpha = isDark ? 0.16 : 0.07;
    final surfaceColor = Color.alphaBlend(
      color.withValues(alpha: tintAlpha),
      scheme.surfaceContainerLowest,
    );
    final borderColor = Color.alphaBlend(
      color.withValues(alpha: isDark ? 0.46 : 0.34),
      scheme.outlineVariant,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: surfaceColor,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor, width: 1.1),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: AppTheme.deepBlue.withValues(alpha: 0.035),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: radius,
                splashColor: color.withValues(alpha: 0.08),
                highlightColor: color.withValues(alpha: 0.06),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: color.withValues(
                        alpha: isDark ? 0.22 : 0.13,
                      ),
                      child: Icon(group.icon, color: color, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            hasDueToday
                                ? '${group.subtitle} · ${_dueTodayLabel(dueTodayCount)}'
                                : group.subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hasDueToday
                                  ? context.hopeColors.warning
                                  : scheme.onSurfaceVariant,
                              fontWeight: hasDueToday ? FontWeight.w800 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Num celular estreito o par de etiquetas empurrava o
                    // título para fora: aqui elas encolhem juntas antes de
                    // qualquer coisa estourar.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasDueToday) ...[
                              _DueTodayBadge(count: dueTodayCount),
                              const SizedBox(width: 6),
                            ],
                            _UpcomingCountBadge(count: group.entries.length),
                          ],
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: context.motion(const Duration(milliseconds: 200)),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _UpcomingMetricStrip(metrics: group.metrics),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: !_expanded
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Divider(height: 1, color: borderColor),
                          ),
                          const SizedBox(height: 4),
                          for (final entry in group.entries)
                            _UpcomingEntryRow(entry: entry),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueTodayBadge extends StatelessWidget {
  const _DueTodayBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.hopeColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.hopeColors.warning.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.today_outlined, size: 14, color: context.hopeColors.warning),
          const SizedBox(width: 4),
          Text(
            count == 1 ? 'hoje' : '$count hoje',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.hopeColors.warning,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingEntryRow extends ConsumerStatefulWidget {
  const _UpcomingEntryRow({required this.entry});

  final FinancialAgendaEntry entry;

  @override
  ConsumerState<_UpcomingEntryRow> createState() => _UpcomingEntryRowState();
}

class _UpcomingEntryRowState extends ConsumerState<_UpcomingEntryRow> {
  bool _settling = false;

  /// Abre a ficha de baixa da parcela de dívida do lançamento, se houver.
  Future<void> _openDebtSheet() async {
    final entry = widget.entry;
    final debt = entry.debt;
    final dueDate = entry.dueDate;
    final installmentNumber = entry.debtInstallmentNumber;
    if (debt == null || dueDate == null || installmentNumber == null) {
      _showAgendaMessage(context, 'Não foi possível abrir a dívida.');
      return;
    }
    await showDebtPaymentSheet(
      context,
      debt: debt,
      plannedAmount: entry.amount,
      dueDate: dueDate,
      installmentNumber: installmentNumber,
    );
  }

  /// Toque no lançamento: abre a ficha de detalhes do item (resumo, botão
  /// para ver os lançamentos já realizados na categoria/subcategoria e a
  /// ação específica do tipo — gerenciar lançamento ou baixar dívida).
  void _openDetails() {
    _showAgendaEntryDetailsSheet(
      context,
      ref,
      widget.entry,
      onOpenDebtSheet: _openDebtSheet,
    );
  }

  Future<void> _settle() async {
    final entry = widget.entry;
    if (!_canSettleAgendaEntry(entry)) return;

    if (entry.isDebt) {
      await _openDebtSheet();
      return;
    }

    final settlement = await _showAgendaSettlementDialog(context, entry);
    if (settlement == null) return;
    if (!mounted) return;

    setState(() => _settling = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      final tx = entry.transaction;
      if (tx != null && settlement.closeDifference) {
        await repo.settleAgendaTransactionDifference(
          tx,
          amount: settlement.amount,
          paymentDate: settlement.paymentDate,
        );
      } else if (tx != null) {
        await repo.settleAgendaTransaction(
          tx,
          amount: settlement.amount,
          paymentDate: settlement.paymentDate,
        );
      } else if (settlement.closeDifference) {
        await repo.settleBudgetAgendaDifference(
          entry,
          amount: settlement.amount,
          paymentDate: settlement.paymentDate,
        );
      } else {
        await repo.launchBudgetAgendaExpense(
          entry,
          amount: settlement.amount,
          paymentDate: settlement.paymentDate,
        );
      }
      ref.read(syncServiceProvider).syncNow();
      if (!mounted) return;
      final partial = settlement.amount < entry.amount - 0.009;
      _showAgendaMessage(
        context,
        settlement.closeDifference
            ? 'Diferença baixada sem movimentar conta.'
            : partial
            ? entry.cardId != null && entry.cardId!.isNotEmpty && entry.isBudget
                  ? 'Baixa parcial lançada na fatura.'
                  : 'Baixa parcial registrada.'
            : entry.cardId != null && entry.cardId!.isNotEmpty && entry.isBudget
            ? 'Despesa lançada na fatura.'
            : 'Despesa baixada.',
      );
    } catch (_) {
      if (mounted) {
        _showAgendaMessage(context, 'Não foi possível registrar a baixa.');
      }
    } finally {
      if (mounted) setState(() => _settling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isIncome = entry.type == 'income';
    final color = isIncome ? context.hopeColors.income : context.hopeColors.expense;
    final icon = entry.isDebt
        ? Icons.trending_down_outlined
        : entry.isBudget
        ? Icons.savings_outlined
        : isIncome
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    final dateLabel = entry.isDebt
        ? 'Parcela em'
        : entry.isBudget
        ? 'Orçado para'
        : 'Vence em';
    final today = todayIso();
    final dueDate = entry.dueDate;
    final isDueToday = dueDate == today;
    final isOverdue = dueDate != null && dueDate.compareTo(today) < 0;
    final sourceLabel = entry.isDebt
        ? 'dívida'
        : entry.isBudget
        ? 'orçamento'
        : 'previsto';
    final dueLabel = isDueToday
        ? 'Vence hoje'
        : isOverdue
        ? 'Venceu em ${formatDate(dueDate)}'
        : '$dateLabel ${formatDate(dueDate)}';
    final dateColor = isDueToday
        ? context.hopeColors.warning
        : isOverdue
        ? context.hopeColors.expense
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final canSettle = _canSettleAgendaEntry(entry);
    final hasDetails =
        entry.transaction != null || entry.isDebt || entry.categoryId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: hasDetails ? _openDetails : null,
          child: AnimatedContainer(
            duration: HopeMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isDueToday
                  ? context.hopeColors.warning.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDueToday
                    ? context.hopeColors.warning.withValues(alpha: 0.34)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isDueToday ? context.hopeColors.warning : color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.description, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        '$dueLabel · $sourceLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: dateColor,
                          fontWeight: isDueToday ? FontWeight.w800 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _money(context, entry.amount),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (canSettle) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Registrar baixa',
                    child: IconButton.filledTonal(
                      onPressed: _settling ? null : _settle,
                      icon: _settling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.task_alt_rounded),
                      iconSize: 19,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        disabledBackgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lançamentos já pagos que casam com a categoria/subcategoria da previsão
/// do item da agenda, dentro do mês em exibição — mostra o que já foi
/// realizado além do que ainda está previsto.
List<LocalTransaction> _realizedForAgendaEntry(
  FinancialAgendaEntry entry,
  List<LocalTransaction> all,
  String monthKey,
) {
  final categoryId = entry.categoryId;
  if (categoryId == null) return const [];
  final realized = all.where((tx) {
    if (tx.status != 'paid') return false;
    if (tx.type != entry.type) return false;
    if (tx.categoryId != categoryId) return false;
    if (entry.subcategoryId != null &&
        tx.subcategoryId != entry.subcategoryId) {
      return false;
    }
    if (!tx.competenceDate.startsWith(monthKey)) return false;
    if (FinanceRepository.isInvoiceSettlement(tx)) return false;
    return true;
  }).toList()..sort((a, b) => b.competenceDate.compareTo(a.competenceDate));
  return realized;
}

/// Lista dos lançamentos já realizados na categoria/subcategoria da previsão
/// do item, no mês em exibição. Tocar num lançamento abre suas ações.
void _showRealizedTransactionsSheet(
  BuildContext context,
  WidgetRef ref,
  FinancialAgendaEntry entry,
) {
  final month = ref.read(selectedMonthProvider);
  final monthKey =
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';
  final all =
      ref.read(transactionsProvider).valueOrNull ?? <LocalTransaction>[];
  final txs = _realizedForAgendaEntry(entry, all, monthKey);
  final categories = {
    for (final c
        in ref.read(categoriesProvider).valueOrNull ?? <LocalCategory>[])
      c.id: c.name,
  };
  final subcategories = {
    for (final s
        in ref.read(subcategoriesProvider).valueOrNull ?? <LocalSubcategory>[])
      s.id: s.name,
  };
  final categoryLabel = [
    categories[entry.categoryId],
    if (entry.subcategoryId != null) subcategories[entry.subcategoryId],
  ].whereType<String>().join(' / ');

  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          ListTile(
            title: Text(
              categoryLabel.isEmpty ? 'Lançamentos realizados' : categoryLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Já realizados no período · toque para editar',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ),
          if (txs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Nenhum lançamento realizado ainda nesta categoria/'
                'subcategoria no período.',
              ),
            ),
          for (final tx in txs)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(tx.description),
              subtitle: Text(formatDate(tx.competenceDate)),
              trailing: Text(
                formatMoney(tx.amount ?? tx.amountPlanned),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showTransactionActions(context, ref, tx);
              },
            ),
        ],
      ),
    ),
  );
}

/// Ficha de detalhes de um item da Agenda financeira: resumo do previsto e
/// acesso ao histórico já realizado da categoria/subcategoria, além das
/// ações específicas do tipo (gerenciar lançamento ou baixar dívida).
void _showAgendaEntryDetailsSheet(
  BuildContext context,
  WidgetRef ref,
  FinancialAgendaEntry entry, {
  required VoidCallback onOpenDebtSheet,
}) {
  final isIncome = entry.type == 'income';
  final color = isIncome ? context.hopeColors.income : context.hopeColors.expense;
  final today = todayIso();
  final dueDate = entry.dueDate;
  final isOverdue = dueDate != null && dueDate.compareTo(today) < 0;
  final dueLabel = dueDate == null
      ? null
      : isOverdue
      ? 'Venceu em ${formatDate(dueDate)}'
      : dueDate == today
      ? 'Vence hoje'
      : 'Vence em ${formatDate(dueDate)}';
  final sourceLabel = entry.isDebt
      ? 'Dívida'
      : entry.isBudget
      ? 'Orçamento'
      : 'Previsto';

  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              entry.description,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text([?dueLabel, sourceLabel].join(' · ')),
            trailing: Text(
              formatMoney(entry.amount),
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ),
          if (entry.categoryId != null)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Ver lançamentos realizados no período'),
              subtitle: const Text(
                'O que já foi pago nesta categoria/subcategoria',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showRealizedTransactionsSheet(context, ref, entry);
              },
            ),
          if (entry.transaction != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Gerenciar lançamento'),
              subtitle: const Text('Editar, marcar pago ou excluir'),
              onTap: () {
                Navigator.pop(sheetContext);
                showTransactionActions(context, ref, entry.transaction!);
              },
            ),
          if (entry.isDebt)
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Registrar baixa da parcela'),
              onTap: () {
                Navigator.pop(sheetContext);
                onOpenDebtSheet();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

bool _canSettleAgendaEntry(FinancialAgendaEntry entry) {
  if (entry.type != 'expense') return false;
  if (entry.isDebt || entry.isBudget) return true;
  final tx = entry.transaction;
  return tx != null && (tx.status == 'planned' || tx.status == 'overdue');
}

bool _canCloseAgendaDifference(FinancialAgendaEntry entry) {
  if (entry.type != 'expense') return false;
  if (entry.isBudget) return true;
  final tx = entry.transaction;
  if (tx == null || (tx.status != 'planned' && tx.status != 'overdue')) {
    return false;
  }
  return !FinanceRepository.isDebtPayment(tx) &&
      FinanceRepository.goalMovementLink(tx) == null;
}

bool _hasDueTodayExpense(List<FinancialAgendaEntry> entries) =>
    _dueTodayExpenseCount(entries) > 0;

int _dueTodayExpenseCount(List<FinancialAgendaEntry> entries) {
  final today = todayIso();
  return entries
      .where((entry) => entry.type == 'expense' && entry.dueDate == today)
      .length;
}

String _dueTodayLabel(int count) =>
    count == 1 ? '1 vence hoje' : '$count vencem hoje';

void _showAgendaMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<_AgendaSettlementResult?> _showAgendaSettlementDialog(
  BuildContext context,
  FinancialAgendaEntry entry,
) {
  return showDialog<_AgendaSettlementResult>(
    context: context,
    builder: (dialogContext) => _AgendaSettlementDialog(entry: entry),
  );
}

class _AgendaSettlementResult {
  const _AgendaSettlementResult({
    required this.amount,
    required this.paymentDate,
    required this.closeDifference,
  });

  final double amount;
  final String paymentDate;
  final bool closeDifference;
}

class _AgendaSettlementDialog extends StatefulWidget {
  const _AgendaSettlementDialog({required this.entry});

  final FinancialAgendaEntry entry;

  @override
  State<_AgendaSettlementDialog> createState() =>
      _AgendaSettlementDialogState();
}

class _AgendaSettlementDialogState extends State<_AgendaSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late String _paymentDate;
  bool _closeDifference = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.entry.amount.toStringAsFixed(2).replaceAll('.', ','),
    );
    _paymentDate = todayIso();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _AgendaSettlementResult(
        amount: parseMoney(_amount.text)!,
        paymentDate: _paymentDate,
        closeDifference: _closeDifference,
      ),
    );
  }

  Future<void> _pickPaymentDate() async {
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

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final canCloseDifference = _canCloseAgendaDifference(entry);
    return AlertDialog(
      title: const Text('Registrar baixa'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Previsto: ${formatMoney(entry.amount)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (canCloseDifference) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Pagamento'),
                    icon: Icon(Icons.payments_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Diferença'),
                    icon: Icon(Icons.rule_folder_outlined),
                  ),
                ],
                selected: {_closeDifference},
                onSelectionChanged: (value) =>
                    setState(() => _closeDifference = value.first),
              ),
              const SizedBox(height: 12),
              Text(
                _closeDifference
                    ? 'Fecha o valor pendente sem alterar conta, cartão ou o orçamento dos próximos meses.'
                    : 'Registra a despesa e movimenta a conta ou fatura vinculada. O valor pode ser maior que o previsto.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor da baixa',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final parsed = value == null ? null : parseMoney(value);
                if (parsed == null || parsed <= 0) {
                  return 'Informe um valor válido';
                }
                // Pagamento aceita valor acima do previsto (previsões são
                // estimadas); a baixa de diferença fecha só o pendente.
                if (_closeDifference && parsed > entry.amount) {
                  return 'Valor maior que o pendente';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickPaymentDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Baixa em ${formatDate(_paymentDate)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Registrar'),
        ),
      ],
    );
  }
}

class _UpcomingCountBadge extends StatelessWidget {
  const _UpcomingCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        count == 1 ? '1 item' : '$count itens',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _UpcomingMetricStrip extends StatelessWidget {
  const _UpcomingMetricStrip({required this.metrics});

  final List<_UpcomingMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        if (compact) {
          return Column(
            children: [
              for (var i = 0; i < metrics.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
                  child: _UpcomingMetricBlock(metric: metrics[i]),
                ),
            ],
          );
        }

        final columns = metrics.length > 3 && constraints.maxWidth < 760
            ? 3
            : metrics.length;
        final spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _UpcomingMetricBlock(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _UpcomingMetricBlock extends StatelessWidget {
  const _UpcomingMetricBlock({required this.metric});

  final _UpcomingMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: metric.color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(context, metric.value),
              style: TextStyle(
                color: metric.color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingMetric {
  const _UpcomingMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _UpcomingGroup {
  const _UpcomingGroup({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.entries,
    required this.metrics,
  });

  final String key;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<FinancialAgendaEntry> entries;
  final List<_UpcomingMetric> metrics;
}

List<_UpcomingGroup> _buildUpcomingGroups(
  BuildContext context,
  List<FinancialAgendaEntry> entries,
  List<LocalAccount> accounts,
  List<LocalCreditCard> cards,
  Map<String, double> accountBalances,
  Map<String, double> cardOpenByCard,
) {
  final accountById = {for (final account in accounts) account.id: account};
  final cardById = {for (final card in cards) card.id: card};
  final grouped = <String, List<FinancialAgendaEntry>>{};

  for (final entry in entries) {
    final key = entry.cardId != null && entry.cardId!.isNotEmpty
        ? 'card:${entry.cardId}'
        : entry.accountId != null && entry.accountId!.isNotEmpty
        ? 'account:${entry.accountId}'
        : 'none';
    grouped.putIfAbsent(key, () => []).add(entry);
  }

  final groups = <_UpcomingGroup>[];
  for (final groupEntry in grouped.entries) {
    final groupEntries = groupEntry.value
      ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
    final income = _sumEntriesByType(groupEntries, 'income');
    final expense = _sumEntriesByType(groupEntries, 'expense');

    if (groupEntry.key.startsWith('card:')) {
      final cardId = groupEntry.key.substring('card:'.length);
      final card = cardById[cardId];
      final limit = card?.limitAmount ?? 0;
      // Limite usado = tudo em aberto no cartão (todas as faturas, inclusive
      // parcelas futuras), não só o que vence nos próximos dias.
      final used = cardOpenByCard[cardId] ?? 0;
      final remaining = limit - used;
      final committed = _sumBudgetCommitmentsByType(groupEntries, 'expense');
      final futureAvailable = remaining - committed;
      groups.add(
        _UpcomingGroup(
          key: groupEntry.key,
          name: card?.name ?? 'Cartão não identificado',
          subtitle: 'Cartão de crédito',
          icon: Icons.credit_card_outlined,
          color: _parseColor(card?.color) ?? context.hopeColors.card,
          entries: groupEntries,
          metrics: [
            _UpcomingMetric(
              label: 'Limite total',
              value: limit,
              color: context.hopeColors.card,
            ),
            _UpcomingMetric(
              label: 'Limite usado',
              value: used,
              color: context.hopeColors.expense,
            ),
            _UpcomingMetric(
              label: 'Limite comprometido',
              value: committed,
              color: context.hopeColors.warning,
            ),
            _UpcomingMetric(
              label: 'Disponível',
              value: remaining,
              color: remaining >= 0 ? Theme.of(context).colorScheme.primary : context.hopeColors.expense,
            ),
            _UpcomingMetric(
              label: 'Disponível futuro',
              value: futureAvailable,
              color: futureAvailable >= 0
                  ? Theme.of(context).colorScheme.primary
                  : context.hopeColors.expense,
            ),
          ],
        ),
      );
      continue;
    }

    if (groupEntry.key.startsWith('account:')) {
      final accountId = groupEntry.key.substring('account:'.length);
      final account = accountById[accountId];
      final balance = accountBalances[accountId] ?? 0;
      // Corrente/poupança projetam o saldo com o previsto; os demais tipos
      // mostram o saldo atual.
      final isBankAccount =
          account?.type == 'checking' || account?.type == 'savings';
      final shownBalance = isBankAccount ? balance + income - expense : balance;
      groups.add(
        _UpcomingGroup(
          key: groupEntry.key,
          name: account?.name ?? 'Conta não identificada',
          subtitle: _accountTypeLabel(account?.type),
          icon: Icons.account_balance_outlined,
          color: _parseColor(account?.color) ?? context.hopeColors.investment,
          entries: groupEntries,
          metrics: [
            _UpcomingMetric(
              label: 'Receitas',
              value: income,
              color: context.hopeColors.income,
            ),
            _UpcomingMetric(
              label: 'Despesas',
              value: expense,
              color: context.hopeColors.expense,
            ),
            _UpcomingMetric(
              label: isBankAccount ? 'Saldo futuro' : 'Saldo',
              value: shownBalance,
              color: shownBalance >= 0 ? Theme.of(context).colorScheme.primary : context.hopeColors.expense,
            ),
          ],
        ),
      );
      continue;
    }

    final balance = income - expense;
    groups.add(
      _UpcomingGroup(
        key: groupEntry.key,
        name: 'Sem conta/cartão',
        subtitle: 'Compromissos ainda não vinculados',
        icon: Icons.help_outline_rounded,
        color: context.hopeColors.warning,
        entries: groupEntries,
        metrics: [
          _UpcomingMetric(
            label: 'Receitas',
            value: income,
            color: context.hopeColors.income,
          ),
          _UpcomingMetric(
            label: 'Despesas',
            value: expense,
            color: context.hopeColors.expense,
          ),
          _UpcomingMetric(
            label: 'Saldo',
            value: balance,
            color: balance >= 0 ? Theme.of(context).colorScheme.primary : context.hopeColors.expense,
          ),
        ],
      ),
    );
  }

  groups.sort((a, b) {
    final aDate = a.entries.isEmpty ? '' : (a.entries.first.dueDate ?? '');
    final bDate = b.entries.isEmpty ? '' : (b.entries.first.dueDate ?? '');
    return aDate.compareTo(bDate);
  });
  return groups;
}

double _sumEntriesByType(List<FinancialAgendaEntry> entries, String type) {
  return entries
      .where((entry) => entry.type == type)
      .fold<double>(0, (sum, entry) => sum + entry.amount);
}

double _sumBudgetCommitmentsByType(
  List<FinancialAgendaEntry> entries,
  String type,
) {
  final value = entries
      .where((entry) => entry.isBudget && entry.type == type)
      .fold<double>(0, (sum, entry) => sum + entry.amount);
  return (value * 100).roundToDouble() / 100;
}

LocalGoal? _primaryGoal(List<LocalGoal> goals) {
  final active = goals.where((goal) => goal.status == 'active').toList();
  if (active.isEmpty) return null;
  active.sort((a, b) {
    final ap = a.targetAmount <= 0 ? 0.0 : a.accumulatedAmount / a.targetAmount;
    final bp = b.targetAmount <= 0 ? 0.0 : b.accumulatedAmount / b.targetAmount;
    return bp.compareTo(ap);
  });
  return active.first;
}

String _goalProgressLabel(LocalGoal goal) {
  if (goal.targetAmount <= 0) return '0%';
  final progress = (goal.accumulatedAmount / goal.targetAmount).clamp(0.0, 1.0);
  return '${(progress * 100).round()}% atingido';
}

String? _topCategoryName(
  Map<String, double> spentByCategory,
  List<LocalCategory> categories,
) {
  if (spentByCategory.isEmpty) return null;
  final top = spentByCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final names = {for (final category in categories) category.id: category.name};
  return names[top.first.key] ?? 'Sem categoria';
}

List<FinancialAgendaEntry> _overdueEntries(List<FinancialAgendaEntry> entries) {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return entries
      .where((entry) => (entry.dueDate ?? '').compareTo(today) < 0)
      .toList();
}

String _accountTypeLabel(String? type) {
  return switch (type) {
    'checking' => 'Conta corrente',
    'savings' => 'Poupança',
    'cash' => 'Dinheiro',
    'investment' => 'Investimento',
    null || '' => 'Conta / banco',
    _ => type,
  };
}


Color? _parseColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}
