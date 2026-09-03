import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/design_system/design_tokens.dart';
import '../../core/utils/finance_calc.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import '../widgets/quick_create_category.dart';
import '../widgets/searchable_category_field.dart';

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// Mês selecionado na tela de orçamento (YYYY-MM-01).
final _selectedMonthProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
});

String _shiftMonth(String month, int delta) {
  final d = DateTime.parse(month);
  final shifted = DateTime(d.year, d.month + delta, 1);
  return '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}-01';
}

String _monthLabel(String month) {
  final d = DateTime.parse(month);
  return '${_monthNames[d.month - 1]} ${d.year}';
}

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_selectedMonthProvider);
    final budgetAsync = ref.watch(budgetForMonthProvider(month));
    final budget = budgetAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Orçamento mensal',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!budgetAsync.isLoading && !budgetAsync.hasError)
            AppBarPrimaryAction(
              label: budget == null ? 'Criar' : 'Adicionar',
              icon: Icons.add_rounded,
              tooltip: budget == null
                  ? 'Criar orçamento'
                  : 'Adicionar ao orçamento',
              onPressed: budget == null
                  ? () => ref
                        .read(financeRepositoryProvider)
                        .createBudget(referenceMonth: month)
                        .then((_) => ref.read(syncServiceProvider).syncNow())
                  : () => _showBudgetItemSheet(context, budget),
            ),
          if (budget != null)
            PopupMenuButton<BudgetSource>(
              tooltip: 'Gerar orçamento',
              icon: const Icon(Icons.autorenew_rounded),
              onSelected: (source) =>
                  _regenerate(context, ref, month: month, source: source),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: BudgetSource.budget,
                  child: Text('Refazer com o orçamento do mês anterior'),
                ),
                PopupMenuItem(
                  value: BudgetSource.realized,
                  child: Text('Refazer com o realizado do mês anterior'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      ref.read(_selectedMonthProvider.notifier).state =
                          _shiftMonth(month, -1),
                ),
                Expanded(
                  child: Text(
                    _monthLabel(month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      ref.read(_selectedMonthProvider.notifier).state =
                          _shiftMonth(month, 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: budgetAsync.when(
              loading: () => const HopeSkeleton(rows: 4),
              error: (error, _) => HopeErrorState.load(
                error,
                what: 'o orçamento',
                onRetry: () => ref.invalidate(budgetForMonthProvider(month)),
              ),
              data: (budget) => budget == null
                  ? _NoBudget(month: month)
                  : _BudgetDetail(budget: budget),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gera o orçamento de [month] a partir do mês anterior, avisando quando não
/// há o que aproveitar lá atrás.
Future<void> _generate(
  BuildContext context,
  WidgetRef ref, {
  required String month,
  required BudgetSource source,
  bool replace = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final generated = await ref
      .read(financeRepositoryProvider)
      .generateBudget(
        fromMonth: _shiftMonth(month, -1),
        toMonth: month,
        source: source,
        replace: replace,
      );
  ref.read(syncServiceProvider).syncNow();
  if (generated != null || !context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        source == BudgetSource.realized
            ? 'O mês anterior não teve movimentação'
            : 'O mês anterior não tem orçamento',
      ),
    ),
  );
}

/// Reescreve um orçamento já existente — os itens atuais são perdidos, então
/// pergunta antes.
Future<void> _regenerate(
  BuildContext context,
  WidgetRef ref, {
  required String month,
  required BudgetSource source,
}) async {
  final base = source == BudgetSource.realized ? 'realizado' : 'orçamento';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Refazer o orçamento?'),
      content: Text(
        'Os itens de ${_monthLabel(month)} serão substituídos pelo $base de '
        '${_monthLabel(_shiftMonth(month, -1))}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Refazer'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _generate(
    context,
    ref,
    month: month,
    source: source,
    replace: true,
  );
}

class _NoBudget extends ConsumerWidget {
  const _NoBudget({required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pie_chart_outline,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Sem orçamento para ${_monthLabel(month)}',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Planeje quanto gastar em cada categoria e acompanhe o realizado.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: HopeSpacing.xs,
              runSpacing: HopeSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _generate(
                    context,
                    ref,
                    month: month,
                    source: BudgetSource.budget,
                  ),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar orçamento anterior'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _generate(
                    context,
                    ref,
                    month: month,
                    source: BudgetSource.realized,
                  ),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Usar realizado anterior'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetDetail extends ConsumerStatefulWidget {
  const _BudgetDetail({required this.budget});

  final LocalBudget budget;

  @override
  ConsumerState<_BudgetDetail> createState() => _BudgetDetailState();
}

class _BudgetDetailState extends ConsumerState<_BudgetDetail> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Grava o previsto apertado assim que o dedo solta a barra.
  ///
  /// Não há botão de confirmar: o desfazer da snackbar é o que segura um
  /// arraste sem querer.
  Future<void> _applySqueeze(LocalBudgetItem item, double plannedAmount) async {
    final repo = ref.read(financeRepositoryProvider);
    final sync = ref.read(syncServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final previous = item.plannedAmount;

    Future<void> write(double amount) async {
      await repo.upsertBudgetItem(
        id: item.id,
        budgetId: item.budgetId,
        categoryId: item.categoryId,
        subcategoryId: item.subcategoryId,
        plannedAmount: amount,
        isFixed: item.isFixed,
        dueDay: item.dueDay,
        accountId: item.accountId,
        cardId: item.cardId,
        currentVersion: item.version,
      );
      sync.syncNow();
    }

    await write(plannedAmount);
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Previsto: ${formatMoney(previous)} → ${formatMoney(plannedAmount)}',
          ),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () => write(previous),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final budget = widget.budget;
    final items = ref.watch(budgetItemsProvider(budget.id)).valueOrNull ?? [];
    final month = budget.referenceMonth.substring(0, 7);
    final realized =
        ref
            .watch(
              budgetItemRealizedProvider((month: month, budgetId: budget.id)),
            )
            .valueOrNull ??
        {};
    final categories = {
      for (final c
          in ref.watch(categoriesProvider).valueOrNull ?? <LocalCategory>[])
        c.id: c,
    };
    final subcategories = {
      for (final s
          in ref.watch(subcategoriesProvider).valueOrNull ??
              <LocalSubcategory>[])
        s.id: s,
    };
    final accounts = {
      for (final a
          in ref.watch(accountsProvider).valueOrNull ?? <LocalAccount>[])
        a.id: a,
    };
    final cards = {
      for (final c
          in ref.watch(creditCardsProvider).valueOrNull ?? <LocalCreditCard>[])
        c.id: c,
    };

    double realizedOf(LocalBudgetItem i) => realized[i.id] ?? 0;

    final expenseItems = [
      for (final i in items)
        if (categories[i.categoryId]?.type != 'income') i,
    ];
    final incomeItems = [
      for (final i in items)
        if (categories[i.categoryId]?.type == 'income') i,
    ];
    final expenseGroups = _groupBudgetItems(
      items: expenseItems,
      categories: categories,
      subcategories: subcategories,
      realizedOf: realizedOf,
    );
    final incomeGroups = _groupBudgetItems(
      items: incomeItems,
      categories: categories,
      subcategories: subcategories,
      realizedOf: realizedOf,
    );
    final normalizedQuery = _normalizeBudgetSearch(_query);
    final filteredExpenseGroups = _filterBudgetGroups(
      groups: expenseGroups,
      subcategories: subcategories,
      normalizedQuery: normalizedQuery,
    );
    final filteredIncomeGroups = _filterBudgetGroups(
      groups: incomeGroups,
      subcategories: subcategories,
      normalizedQuery: normalizedQuery,
    );
    final hasSearch = normalizedQuery.isNotEmpty;
    final hasSearchResults =
        filteredExpenseGroups.isNotEmpty || filteredIncomeGroups.isNotEmpty;

    final totalPlanned = expenseItems.fold<double>(
      0,
      (s, i) => s + i.plannedAmount,
    );
    final totalRealized = expenseItems.fold<double>(
      0,
      (s, i) => s + realizedOf(i),
    );
    final exceeded = expenseItems.where((i) => realizedOf(i) > i.plannedAmount);
    final totalPlannedIncome = incomeItems.fold<double>(
      0,
      (s, i) => s + i.plannedAmount,
    );
    final totalRealizedIncome = incomeItems.fold<double>(
      0,
      (s, i) => s + realizedOf(i),
    );

    // Aperto: só despesa, e só onde ainda existe folga entre previsto e
    // consumido. O resumo apenas anuncia a folga — quem aperta é a barra de
    // cada linha.
    final squeezable = [
      for (final item in expenseItems)
        if (_hasSlack(realizedOf(item), item.plannedAmount)) item,
    ];
    final totalSlack = squeezable.fold<double>(
      0,
      (sum, item) =>
          sum +
          _round2(item.plannedAmount) -
          _squeezeFloor(realizedOf(item), item.plannedAmount),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        context.isDesktop ? HopeSpacing.md : HopeSpacing.xs,
        context.pagePadding,
        // Espaço para o botão flutuante de lançamento da casca.
        120,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // O título cede espaço para a porcentagem: em tela estreita
                    // (320 px) os dois juntos não caberiam.
                    Expanded(
                      child: Text(
                        'Previsto × Realizado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: HopeSpacing.xs),
                    Text(
                      totalPlanned > 0
                          ? '${(totalRealized / totalPlanned * 100).round()}%'
                          : '—',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: totalRealized > totalPlanned
                            ? context.hopeColors.expense
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: clampProgress(totalRealized, totalPlanned),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                  color: totalRealized > totalPlanned
                      ? context.hopeColors.expense
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  '${formatMoney(totalRealized)} gastos de ${formatMoney(totalPlanned)} planejados',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (exceeded.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${exceeded.length} categoria(s) estouraram o orçamento',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.hopeColors.expense,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (incomeItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Receitas: ${formatMoney(totalRealizedIncome)} recebidos de ${formatMoney(totalPlannedIncome)} previstos',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // A folga é a situação; o gesto que a recolhe mora na própria
                // barra de cada linha, então aqui só se anuncia os dois.
                if (squeezable.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${formatMoney(totalSlack)} de folga em ${squeezable.length == 1 ? '1 linha' : '${squeezable.length} linhas'} · arraste a ponta da barra para apertar o previsto',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Buscar por categoria ou valor',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Nenhuma categoria no orçamento ainda.\nToque em + para adicionar.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (items.isNotEmpty && hasSearch && !hasSearchResults)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text('Nenhum resultado encontrado'),
                  const SizedBox(height: 4),
                  Text(
                    'Tente buscar por outro nome de categoria ou por outro valor.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (filteredIncomeGroups.isNotEmpty && filteredExpenseGroups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'Despesas',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        for (final group in filteredExpenseGroups) ...[
          _BudgetCategoryCard(
            group: group,
            subcategories: subcategories,
            accounts: accounts,
            cards: cards,
            isIncome: false,
            onTapItem: (item) =>
                _showBudgetItemSheet(context, budget, item: item),
            onAddSubcategory: () => _showBudgetItemSheet(
              context,
              budget,
              initialCategoryId: group.categoryId,
              initialType: 'expense',
            ),
            onSqueeze: _applySqueeze,
          ),
          const SizedBox(height: HopeSpacing.sm),
        ],
        if (filteredIncomeGroups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
            child: Text(
              'Receitas planejadas',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        for (final group in filteredIncomeGroups) ...[
          _BudgetCategoryCard(
            group: group,
            subcategories: subcategories,
            accounts: accounts,
            cards: cards,
            isIncome: true,
            onTapItem: (item) =>
                _showBudgetItemSheet(context, budget, item: item),
            onAddSubcategory: () => _showBudgetItemSheet(
              context,
              budget,
              initialCategoryId: group.categoryId,
              initialType: 'income',
            ),
            onSqueeze: _applySqueeze,
          ),
          const SizedBox(height: HopeSpacing.sm),
        ],
      ],
    );
  }
}

void _showBudgetItemSheet(
  BuildContext context,
  LocalBudget budget, {
  LocalBudgetItem? item,
  String? initialCategoryId,
  String? initialType,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BudgetItemForm(
      budget: budget,
      item: item,
      initialCategoryId: initialCategoryId,
      initialType: initialType,
    ),
  );
}

// ---------------- Aperto do previsto ----------------

double _round2(double value) => (value * 100).roundToDouble() / 100;

/// O consumido é o piso do aperto: o mês já gastou (ou já comprometeu) esse
/// valor, então prever menos que isso não aperta nada — só fabrica um estouro.
double _squeezeFloor(double consumed, double planned) =>
    _round2(consumed.clamp(0, planned <= 0 ? 0 : planned));

bool _hasSlack(double consumed, double planned) =>
    _round2(planned) - _squeezeFloor(consumed, planned) >= 0.01;

/// A barra de execução do orçamento que também é o controle de aperto.
///
/// A ponta direita é uma alça: arrastando para a esquerda o previsto encolhe
/// até o consumido, que funciona como muro. Só o arraste horizontal mexe no
/// valor — o toque continua subindo para a linha, que abre o formulário.
class _SqueezeBar extends StatelessWidget {
  const _SqueezeBar({
    super.key,
    required this.consumed,
    required this.value,
    required this.scale,
    required this.color,
    required this.consumedColor,
    required this.height,
    required this.label,
    this.onDragStart,
    this.onChanged,
    this.onDragEnd,
  });

  /// Realizado da linha. Some com o previsto quando estoura.
  final double consumed;

  /// Previsto que a barra está mostrando agora (o gravado ou o em arraste).
  final double value;

  /// Largura total da barra em reais. Fica congelada no previsto do início do
  /// arraste, senão a régua encolheria junto com o valor e o dedo perseguiria
  /// a própria alça.
  final double scale;

  /// Cor da alça e da fatia planejada.
  final Color color;

  /// Cor da fatia consumida. Vem de fora porque só a linha sabe se passar do
  /// previsto é um problema (despesa) ou uma boa notícia (receita).
  final Color consumedColor;

  final double height;

  /// Nome da linha, para leitor de tela.
  final String label;

  final VoidCallback? onDragStart;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onDragEnd;

  bool get _enabled => onChanged != null && _hasSlack(consumed, scale);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.hopeColors;
    final floor = _squeezeFloor(consumed, scale);
    final safeScale = scale <= 0 ? 1.0 : scale;
    final step = (safeScale / 20).clamp(0.01, double.infinity);

    double toValue(double dx, double width) =>
        _round2(((dx / width) * safeScale).clamp(floor, safeScale));

    // Alvo de arraste confortável sem engordar a linha: a área sensível tem
    // 24 px, a barra desenhada continua fina.
    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: !_enabled
              ? null
              : (details) {
                  onDragStart?.call();
                  onChanged!(toValue(details.localPosition.dx, width));
                },
          onHorizontalDragUpdate: !_enabled
              ? null
              : (details) => onChanged!(toValue(details.localPosition.dx, width)),
          onHorizontalDragEnd: !_enabled ? null : (_) => onDragEnd?.call(),
          onHorizontalDragCancel: !_enabled ? null : onDragEnd,
          child: SizedBox(
            height: 24,
            child: Center(
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SqueezeBarPainter(
                    consumedFraction: (consumed / safeScale).clamp(0.0, 1.0),
                    valueFraction: (value / safeScale).clamp(0.0, 1.0),
                    trackColor: theme.colorScheme.surfaceContainerHigh,
                    consumedColor: consumedColor,
                    freedColor: colors.success.withValues(alpha: 0.30),
                    handleColor: _enabled ? color : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!_enabled) return bar;
    return Semantics(
      slider: true,
      label: 'Previsto de $label',
      value: formatMoney(value),
      increasedValue: formatMoney((value + step).clamp(floor, safeScale)),
      decreasedValue: formatMoney((value - step).clamp(floor, safeScale)),
      // Sem gesto: quem usa leitor de tela ou teclado aperta em degraus, e
      // cada degrau grava sozinho (não existe "soltar" aqui).
      onIncrease: value >= safeScale
          ? null
          : () {
              onChanged!(_round2((value + step).clamp(floor, safeScale)));
              onDragEnd?.call();
            },
      onDecrease: value <= floor
          ? null
          : () {
              onChanged!(_round2((value - step).clamp(floor, safeScale)));
              onDragEnd?.call();
            },
      child: ExcludeSemantics(child: bar),
    );
  }
}

class _SqueezeBarPainter extends CustomPainter {
  const _SqueezeBarPainter({
    required this.consumedFraction,
    required this.valueFraction,
    required this.trackColor,
    required this.consumedColor,
    required this.freedColor,
    required this.handleColor,
  });

  final double consumedFraction;
  final double valueFraction;
  final Color trackColor;
  final Color consumedColor;

  /// Faixa entre o previsto em arraste e o previsto original: o que o aperto
  /// está devolvendo.
  final Color freedColor;
  final Color handleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, Paint()..color = trackColor);

    canvas.save();
    canvas.clipRRect(track);
    if (valueFraction < 1) {
      canvas.drawRect(
        Rect.fromLTRB(size.width * valueFraction, 0, size.width, size.height),
        Paint()..color = freedColor,
      );
    }
    final consumed = size.width * consumedFraction;
    if (consumed > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, consumed, size.height),
        Paint()..color = consumedColor,
      );
    }
    canvas.restore();

    if (handleColor.a == 0) return;
    // A alça estoura a altura da barra de propósito: é o que a anuncia como
    // pegável em vez de decoração da própria trilha.
    final handleHeight = size.height + 10;
    final center = (size.width * valueFraction).clamp(3.0, size.width - 3.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center, size.height / 2),
          width: 6,
          height: handleHeight,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = handleColor,
    );
  }

  @override
  bool shouldRepaint(_SqueezeBarPainter old) =>
      old.consumedFraction != consumedFraction ||
      old.valueFraction != valueFraction ||
      old.trackColor != trackColor ||
      old.consumedColor != consumedColor ||
      old.freedColor != freedColor ||
      old.handleColor != handleColor;
}

/// Estado de um aperto em andamento: o valor sendo arrastado e a régua
/// congelada no previsto de quando o dedo encostou.
mixin _SqueezeDrag<T extends StatefulWidget> on State<T> {
  double? pendingPlanned;
  double? dragScale;

  double get committedPlanned;

  double get effectivePlanned => pendingPlanned ?? committedPlanned;
  double get squeezeScale => dragScale ?? effectivePlanned;

  void startSqueeze() => setState(() => dragScale = committedPlanned);

  void updateSqueeze(double value) => setState(() => pendingPlanned = value);

  /// Devolve o valor a gravar, ou null quando o arraste não mudou nada.
  double? endSqueeze() {
    final value = pendingPlanned;
    setState(() => dragScale = null);
    if (value == null || value == committedPlanned) {
      setState(() => pendingPlanned = null);
      return null;
    }
    return value;
  }

  /// O valor gravado chegou (ou foi desfeito): a fonte da verdade reassume.
  void syncSqueeze(double previous) {
    if (previous != committedPlanned && pendingPlanned != null) {
      setState(() => pendingPlanned = null);
    }
  }
}

List<_BudgetCategoryGroup> _groupBudgetItems({
  required List<LocalBudgetItem> items,
  required Map<String, LocalCategory> categories,
  required Map<String, LocalSubcategory> subcategories,
  required double Function(LocalBudgetItem item) realizedOf,
}) {
  final grouped = <String, List<LocalBudgetItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.categoryId, () => []).add(item);
  }

  final groups = [
    for (final entry in grouped.entries)
      _BudgetCategoryGroup(
        categoryId: entry.key,
        category: categories[entry.key],
        items: [...entry.value]
          ..sort(
            (a, b) => _budgetItemLabel(
              a,
              subcategories,
            ).compareTo(_budgetItemLabel(b, subcategories)),
          ),
        planned: entry.value.fold<double>(
          0,
          (sum, item) => sum + item.plannedAmount,
        ),
        realized: entry.value.fold<double>(
          0,
          (sum, item) => sum + realizedOf(item),
        ),
        realizedByItemKey: {
          for (final item in entry.value)
            _budgetItemKey(item): realizedOf(item),
        },
      ),
  ];

  groups.sort((a, b) => a.name.compareTo(b.name));
  return groups;
}

List<_BudgetCategoryGroup> _filterBudgetGroups({
  required List<_BudgetCategoryGroup> groups,
  required Map<String, LocalSubcategory> subcategories,
  required String normalizedQuery,
}) {
  if (normalizedQuery.isEmpty) return groups;

  final filtered = <_BudgetCategoryGroup>[];
  for (final group in groups) {
    final groupMatches =
        _matchesBudgetSearch(group.name, normalizedQuery) ||
        _matchesBudgetAmount(group.planned, normalizedQuery) ||
        _matchesBudgetAmount(group.realized, normalizedQuery);
    final matchingItems = [
      for (final item in group.items)
        if (groupMatches ||
            _matchesBudgetSearch(
              _budgetItemDisplayName(item, subcategories),
              normalizedQuery,
            ) ||
            _matchesBudgetAmount(item.plannedAmount, normalizedQuery) ||
            _matchesBudgetAmount(group.realizedFor(item), normalizedQuery))
          item,
    ];
    if (matchingItems.isEmpty) continue;

    filtered.add(
      _BudgetCategoryGroup(
        categoryId: group.categoryId,
        category: group.category,
        items: matchingItems,
        planned: matchingItems.fold<double>(
          0,
          (sum, item) => sum + item.plannedAmount,
        ),
        realized: matchingItems.fold<double>(
          0,
          (sum, item) => sum + group.realizedFor(item),
        ),
        realizedByItemKey: {
          for (final item in matchingItems)
            _budgetItemKey(item): group.realizedFor(item),
        },
      ),
    );
  }
  return filtered;
}

String _budgetItemKey(LocalBudgetItem item) => item.id;

String _budgetItemDisplayName(
  LocalBudgetItem item,
  Map<String, LocalSubcategory> subcategories,
) {
  if (item.subcategoryId == null) return 'Toda a categoria';
  return subcategories[item.subcategoryId]?.name ?? 'Subcategoria';
}

String _budgetItemLabel(
  LocalBudgetItem item,
  Map<String, LocalSubcategory> subcategories,
) {
  if (item.subcategoryId == null) return '0';
  return subcategories[item.subcategoryId]?.name ?? 'Subcategoria';
}

bool _matchesBudgetSearch(String value, String normalizedQuery) =>
    _normalizeBudgetSearch(value).contains(normalizedQuery);

bool _matchesBudgetAmount(double value, String normalizedQuery) {
  final compactQuery = _compactBudgetAmountSearch(normalizedQuery);
  if (compactQuery.isEmpty) return false;
  final formatted = formatMoney(value);
  final fixed = value.toStringAsFixed(2);
  final candidates = [
    formatted,
    fixed,
    fixed.replaceAll('.', ','),
    value.roundToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toString(),
  ];
  return candidates.any(
    (candidate) => _compactBudgetAmountSearch(
      _normalizeBudgetSearch(candidate),
    ).contains(compactQuery),
  );
}

String _compactBudgetAmountSearch(String value) =>
    value.replaceAll(RegExp(r'[^0-9,.]'), '');

String _normalizeBudgetSearch(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString().trim();
}

class _BudgetCategoryGroup {
  const _BudgetCategoryGroup({
    required this.categoryId,
    required this.category,
    required this.items,
    required this.planned,
    required this.realized,
    required this.realizedByItemKey,
  });

  final String categoryId;
  final LocalCategory? category;
  final List<LocalBudgetItem> items;
  final double planned;
  final double realized;
  final Map<String, double> realizedByItemKey;

  String get name => category?.name ?? 'Categoria';
  int get subcategoryCount =>
      items.where((item) => item.subcategoryId != null).length;
  double realizedFor(LocalBudgetItem item) =>
      realizedByItemKey[_budgetItemKey(item)] ?? 0;
}

class _BudgetCategoryCard extends StatefulWidget {
  const _BudgetCategoryCard({
    required this.group,
    required this.subcategories,
    required this.accounts,
    required this.cards,
    required this.isIncome,
    required this.onTapItem,
    required this.onAddSubcategory,
    required this.onSqueeze,
  });

  final _BudgetCategoryGroup group;
  final Map<String, LocalSubcategory> subcategories;
  final Map<String, LocalAccount> accounts;
  final Map<String, LocalCreditCard> cards;
  final bool isIncome;
  final ValueChanged<LocalBudgetItem> onTapItem;
  final VoidCallback onAddSubcategory;
  final void Function(LocalBudgetItem item, double plannedAmount) onSqueeze;

  @override
  State<_BudgetCategoryCard> createState() => _BudgetCategoryCardState();
}

class _BudgetCategoryCardState extends State<_BudgetCategoryCard>
    with _SqueezeDrag<_BudgetCategoryCard> {
  /// A barra do cabeçalho soma várias linhas. Ela só vira alça quando a
  /// categoria tem uma linha só — aí o número da barra e o do item são o mesmo,
  /// e não há como o arraste ser ambíguo.
  LocalBudgetItem? get _soleItem =>
      widget.isIncome || widget.group.items.length != 1
      ? null
      : widget.group.items.first;

  @override
  double get committedPlanned => widget.group.planned;

  @override
  void didUpdateWidget(_BudgetCategoryCard old) {
    super.didUpdateWidget(old);
    syncSqueeze(old.group.planned);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isIncome = widget.isIncome;
    final subcategories = widget.subcategories;
    final accounts = widget.accounts;
    final cards = widget.cards;
    final onTapItem = widget.onTapItem;
    final onAddSubcategory = widget.onAddSubcategory;

    final sole = _soleItem;
    final planned = sole == null ? group.planned : effectivePlanned;
    final over = !isIncome && group.realized > planned;
    final color =
        _parseColor(group.category?.color) ??
        (isIncome ? context.hopeColors.income : context.hopeColors.expense);
    final subcategoryText = group.subcategoryCount == 0
        ? 'Toda a categoria'
        : group.subcategoryCount == 1
        ? '1 subcategoria'
        : '${group.subcategoryCount} subcategorias';

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey('budget-category-${group.categoryId}'),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(_budgetCategoryIcon(group.category?.icon), color: color),
        ),
        title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$subcategoryText · ${formatMoney(group.realized)} de ${formatMoney(planned)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: over ? context.hopeColors.expense : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _SqueezeBar(
                // Chave própria: com a categoria aberta, esta barra e a da
                // linha controlam o mesmo item e não podem se confundir.
                key: sole == null
                    ? null
                    : ValueKey('budget-squeeze-head-${sole.id}'),
                consumed: group.realized,
                value: planned,
                scale: sole == null ? group.planned : squeezeScale,
                color: color,
                consumedColor: over ? context.hopeColors.expense : color,
                height: 6,
                label: group.name,
                onDragStart: sole == null ? null : startSqueeze,
                onChanged: sole == null ? null : updateSqueeze,
                onDragEnd: sole == null
                    ? null
                    : () {
                        final value = endSqueeze();
                        if (value != null) widget.onSqueeze(sole, value);
                      },
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          HopeSpacing.xxl,
          0,
          HopeSpacing.md,
          HopeSpacing.sm,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: HopeSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in group.items)
                  _BudgetItemRow(
                    key: ValueKey('budget-item-${item.id}'),
                    item: item,
                    subcategory: item.subcategoryId == null
                        ? null
                        : subcategories[item.subcategoryId],
                    account: item.accountId == null
                        ? null
                        : accounts[item.accountId],
                    card: item.cardId == null ? null : cards[item.cardId],
                    isIncome: isIncome,
                    color: color,
                    realized: group.realizedFor(item),
                    onTap: () => onTapItem(item),
                    onSqueeze: (value) => widget.onSqueeze(item, value),
                  ),
                const SizedBox(height: HopeSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onAddSubcategory,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Adicionar subcategoria'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetItemRow extends StatefulWidget {
  const _BudgetItemRow({
    super.key,
    required this.item,
    required this.subcategory,
    required this.account,
    required this.card,
    required this.isIncome,
    required this.color,
    required this.realized,
    required this.onTap,
    required this.onSqueeze,
  });

  final LocalBudgetItem item;
  final LocalSubcategory? subcategory;
  final LocalAccount? account;
  final LocalCreditCard? card;
  final bool isIncome;
  final Color color;
  final double realized;
  final VoidCallback onTap;
  final ValueChanged<double> onSqueeze;

  @override
  State<_BudgetItemRow> createState() => _BudgetItemRowState();
}

class _BudgetItemRowState extends State<_BudgetItemRow>
    with _SqueezeDrag<_BudgetItemRow> {
  @override
  double get committedPlanned => widget.item.plannedAmount;

  @override
  void didUpdateWidget(_BudgetItemRow old) {
    super.didUpdateWidget(old);
    syncSqueeze(old.item.plannedAmount);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final subcategory = widget.subcategory;
    final account = widget.account;
    final card = widget.card;
    final isIncome = widget.isIncome;
    final color = widget.color;
    final realized = widget.realized;

    final planned = effectivePlanned;
    final squeezing = pendingPlanned != null;
    final over = !isIncome && realized > planned;
    final title = subcategory?.name ?? 'Toda a categoria';
    final fixedText = item.isFixed
        ? item.dueDay == null
              ? 'Fixa'
              : 'Fixa · dia ${item.dueDay}'
        : null;
    final destinationText = card != null
        ? 'Cartão 💳 ${card.name}'
        : account == null
        ? null
        : isIncome
        ? 'Entra em ${account.name}'
        : 'Sai de ${account.name}';
    final details = [?fixedText, ?destinationText].join(' · ');

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(HopeRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  subcategory == null
                      ? Icons.category_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
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
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 148),
                  child: Text(
                    '${formatMoney(realized)} / ${formatMoney(planned)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: over
                          ? context.hopeColors.expense
                          : squeezing
                          ? context.hopeColors.success
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            _SqueezeBar(
              key: ValueKey('budget-squeeze-${item.id}'),
              consumed: realized,
              value: planned,
              scale: squeezeScale,
              color: color,
              consumedColor: over ? context.hopeColors.expense : color,
              height: 4,
              label: title,
              onDragStart: isIncome ? null : startSqueeze,
              onChanged: isIncome ? null : updateSqueeze,
              onDragEnd: isIncome
                  ? null
                  : () {
                      final value = endSqueeze();
                      if (value != null) widget.onSqueeze(value);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

const _budgetCategoryIcons = <String, IconData>{
  'home': Icons.home_outlined,
  'rent': Icons.apartment_outlined,
  'maintenance': Icons.handyman_outlined,
  'food': Icons.restaurant_outlined,
  'groceries': Icons.shopping_cart_outlined,
  'coffee': Icons.local_cafe_outlined,
  'bar': Icons.local_bar_outlined,
  'car': Icons.directions_car_outlined,
  'transport': Icons.directions_bus_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'flight': Icons.flight_outlined,
  'travel': Icons.luggage_outlined,
  'health': Icons.health_and_safety_outlined,
  'medicine': Icons.medical_services_outlined,
  'fitness': Icons.fitness_center_outlined,
  'beauty': Icons.spa_outlined,
  'work': Icons.work_outline,
  'salary': Icons.payments_outlined,
  'business': Icons.storefront_outlined,
  'education': Icons.school_outlined,
  'books': Icons.menu_book_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'clothing': Icons.checkroom_outlined,
  'gift': Icons.card_giftcard_outlined,
  'entertainment': Icons.movie_outlined,
  'games': Icons.sports_esports_outlined,
  'music': Icons.music_note_outlined,
  'sports': Icons.sports_soccer_outlined,
  'pets': Icons.pets_outlined,
  'kids': Icons.child_care_outlined,
  'phone': Icons.smartphone_outlined,
  'internet': Icons.wifi_outlined,
  'subscription': Icons.subscriptions_outlined,
  'bills': Icons.receipt_long_outlined,
  'water': Icons.water_drop_outlined,
  'electricity': Icons.bolt_outlined,
  'gas': Icons.local_fire_department_outlined,
  'insurance': Icons.shield_outlined,
  'taxes': Icons.account_balance_outlined,
  'savings': Icons.savings_outlined,
  'investment': Icons.trending_up_outlined,
  'card': Icons.credit_card_outlined,
  'donation': Icons.volunteer_activism_outlined,
  'more': Icons.category_outlined,
};

IconData _budgetCategoryIcon(String? value) =>
    _budgetCategoryIcons[value] ?? Icons.category_outlined;

Color? _parseColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

class _BudgetItemForm extends ConsumerStatefulWidget {
  const _BudgetItemForm({
    required this.budget,
    this.item,
    this.initialCategoryId,
    this.initialType,
  });

  final LocalBudget budget;
  final LocalBudgetItem? item;
  final String? initialCategoryId;
  final String? initialType;

  @override
  ConsumerState<_BudgetItemForm> createState() => _BudgetItemFormState();
}

class _BudgetItemFormState extends ConsumerState<_BudgetItemForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _dueDay = TextEditingController();

  /// expense | income
  String _type = 'expense';
  String? _categoryId;
  String? _subcategoryId;

  /// Destino/origem previsto: `account:<id>` ou `card:<id>` (null = sem vínculo).
  String? _paymentKey;
  bool _isFixed = false;
  bool _saving = false;

  bool get _editing => widget.item != null;
  bool get _isExpense => _type == 'expense';
  bool get _isCardPayment => _paymentKey?.startsWith('card:') ?? false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _categoryId = item?.categoryId ?? widget.initialCategoryId;
    _subcategoryId = item?.subcategoryId;
    _type = widget.initialType ?? _type;
    if (item?.cardId != null && item!.cardId!.isNotEmpty) {
      _paymentKey = 'card:${item.cardId}';
    } else if (item?.accountId != null && item!.accountId!.isNotEmpty) {
      _paymentKey = 'account:${item.accountId}';
    }
    _isFixed = item?.isFixed ?? false;
    if (item != null) {
      _amount.text = item.plannedAmount.toStringAsFixed(2).replaceAll('.', ',');
      if (item.dueDay != null) _dueDay.text = item.dueDay.toString();
      final categories = ref.read(categoriesProvider).valueOrNull ?? [];
      for (final c in categories) {
        if (c.id == item.categoryId) _type = c.type;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    final key = _paymentKey;
    final accountId = (key?.startsWith('account:') ?? false)
        ? key!.substring('account:'.length)
        : null;
    final cardId = (key?.startsWith('card:') ?? false)
        ? key!.substring('card:'.length)
        : null;
    // A mesma categoria pode ter limites diferentes por conta/cartão.
    final items =
        ref.read(budgetItemsProvider(widget.budget.id)).valueOrNull ?? [];
    final duplicate = items.any(
      (i) =>
          i.id != widget.item?.id &&
          i.categoryId == _categoryId &&
          i.subcategoryId == _subcategoryId &&
          i.accountId == accountId &&
          i.cardId == cardId,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Essa categoria/subcategoria já está no orçamento para essa conta ou cartão',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final fixed = _isFixed;
    await ref
        .read(financeRepositoryProvider)
        .upsertBudgetItem(
          id: widget.item?.id,
          budgetId: widget.budget.id,
          categoryId: _categoryId!,
          subcategoryId: _subcategoryId,
          plannedAmount: parseMoney(_amount.text)!,
          isFixed: fixed,
          dueDay: fixed ? int.tryParse(_dueDay.text.trim()) : null,
          accountId: accountId,
          cardId: cardId,
          currentVersion: widget.item?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    await ref.read(financeRepositoryProvider).deleteBudgetItem(item);
    ref.read(syncServiceProvider).syncNow();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? [])
        .where((c) => c.type == _type)
        .toList();
    final accounts = (ref.watch(accountsProvider).valueOrNull ?? [])
        .where((a) => a.isActive)
        .toList();
    final cards = (ref.watch(creditCardsProvider).valueOrNull ?? [])
        .where((c) => c.isActive || 'card:${c.id}' == _paymentKey)
        .toList();

    return PremiumFormSheet(
      title: _editing ? 'Editar item' : 'Adicionar ao orçamento',
      subtitle: 'Planeje receitas e despesas com conta, valor e recorrência.',
      icon: Icons.pie_chart_outline,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Classificação',
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'expense',
                  label: Text('Despesa'),
                  icon: Icon(Icons.south_west),
                ),
                ButtonSegment(
                  value: 'income',
                  label: Text('Receita'),
                  icon: Icon(Icons.north_east),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _categoryId = null;
                _subcategoryId = null;
                // Cartão só se aplica a despesas.
                if (!_isExpense && _isCardPayment) _paymentKey = null;
              }),
            ),
            SearchableCategoryField(
              key: ValueKey('category-$_type'),
              categories: categories,
              value: _categoryId,
              placeholder: 'Escolha a categoria',
              allowEmpty: false,
              quickCreateType: _type,
              onChanged: (value) => setState(() {
                _categoryId = value;
                _subcategoryId = null;
              }),
              validator: (value) =>
                  value == null ? 'Escolha a categoria' : null,
            ),
            if (_categoryId != null)
              SubcategorySelector(
                categoryId: _categoryId,
                value: _subcategoryId,
                emptyOptionLabel: 'Toda a categoria',
                prefixIcon: Icons.subdirectory_arrow_right,
                onChanged: (v) => setState(() => _subcategoryId = v),
              ),
          ],
        ),
        PremiumFormSection(
          title: 'Planejamento',
          children: [
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(
                labelText: 'Valor previsto',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final parsed = v == null ? null : parseMoney(v);
                return (parsed == null || parsed <= 0)
                    ? 'Informe um valor válido'
                    : null;
              },
            ),
            DropdownButtonFormField<String?>(
              key: ValueKey('payment-$_type'),
              initialValue: _paymentKey,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _isExpense
                    ? 'Conta/cartão de saída'
                    : 'Conta de entrada',
                prefixIcon: Icon(
                  _isCardPayment
                      ? Icons.credit_card_outlined
                      : Icons.account_balance_outlined,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sem vínculo'),
                ),
                for (final a in accounts)
                  DropdownMenuItem<String?>(
                    value: 'account:${a.id}',
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
                if (_isExpense)
                  for (final c in cards)
                    DropdownMenuItem<String?>(
                      value: 'card:${c.id}',
                      child: Text(
                        '💳 ${c.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (v) => setState(() => _paymentKey = v),
            ),
            FormSwitchRow(
              icon: Icons.repeat_rounded,
              title: _isExpense ? 'Despesa fixa' : 'Receita fixa',
              subtitle: _isExpense
                  ? 'Ex.: aluguel, assinaturas'
                  : 'Ex.: salário, aluguel recebido',
              value: _isFixed,
              onChanged: (v) => setState(() => _isFixed = v),
            ),
            if (_isFixed)
              TextFormField(
                controller: _dueDay,
                decoration: InputDecoration(
                  labelText: _isExpense
                      ? 'Dia do vencimento'
                      : 'Dia do recebimento',
                  helperText: 'Dia do mês, de 1 a 31',
                  prefixIcon: const Icon(Icons.event_outlined),
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
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Salvar'),
      ),
      destructiveAction: _editing
          ? TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(
                Icons.delete_outline,
                color: context.hopeColors.expense,
              ),
              label: const Text('Remover do orçamento'),
              style: TextButton.styleFrom(
                foregroundColor: context.hopeColors.expense,
              ),
            )
          : null,
    );
  }
}
