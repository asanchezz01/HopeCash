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
            OutlinedButton.icon(
              onPressed: () async {
                final copied = await ref
                    .read(financeRepositoryProvider)
                    .copyBudget(
                      fromMonth: _shiftMonth(month, -1),
                      toMonth: month,
                    );
                ref.read(syncServiceProvider).syncNow();
                if (copied == null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('O mês anterior não tem orçamento'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copiar do mês anterior'),
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
    // consumido. O resumo aperta o mês inteiro; cada cartão aperta a categoria.
    final squeezeTargets = _squeezeTargets(
      items: expenseItems,
      categories: categories,
      subcategories: subcategories,
      consumedOf: realizedOf,
      fallbackColor: context.hopeColors.expense,
    );
    final totalSlack = squeezeTargets.fold<double>(0, (s, t) => s + t.slack);
    final squeezeByCategory = {
      for (final group in filteredExpenseGroups)
        group.categoryId: _squeezeTargets(
          items: group.items,
          categories: categories,
          subcategories: subcategories,
          consumedOf: group.realizedFor,
          fallbackColor: context.hopeColors.expense,
        ),
    };

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
                // Primeiro a situação, depois a ação: quanto ainda sobra de
                // folga e só então o convite para apertar.
                if (squeezeTargets.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${formatMoney(totalSlack)} de folga entre o previsto e o consumido em ${squeezeTargets.length == 1 ? '1 linha' : '${squeezeTargets.length} linhas'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: HopeSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showBudgetSqueezeSheet(context, squeezeTargets),
                      icon: const Icon(Icons.compress_rounded, size: 18),
                      label: const Text('Apertar previsto'),
                    ),
                  ),
                ],
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
            onSqueeze:
                (squeezeByCategory[group.categoryId] ?? const []).isEmpty
                ? null
                : () => _showBudgetSqueezeSheet(
                    context,
                    squeezeByCategory[group.categoryId]!,
                  ),
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

/// Uma linha do orçamento vista pela ótica do aperto.
///
/// O piso é o consumido, e não zero: o mês já gastou (ou já comprometeu) esse
/// valor, então prever menos que isso não aperta nada — só fabrica um estouro.
/// Aperto também não sobe o previsto; aumentar continua sendo edição do item.
class _SqueezeTarget {
  const _SqueezeTarget({
    required this.item,
    required this.categoryName,
    required this.label,
    required this.consumed,
    required this.color,
  });

  final LocalBudgetItem item;
  final String categoryName;
  final String label;

  /// Realizado da linha no mês — inclui o que já está comprometido, igual à
  /// barra que a tela mostra. O piso tem que ser o mesmo número da barra, senão
  /// o arraste contradiz o que a pessoa está vendo.
  final double consumed;
  final Color color;

  double get planned => _round2(item.plannedAmount);
  double get floor => _round2(consumed.clamp(0, planned));
  double get slack => _round2(planned - floor);
  bool get hasSlack => slack >= 0.01;

  /// Quem nomeia a linha é o termo mais específico que ela tem: a subcategoria
  /// quando existe, a categoria quando o item cobre a categoria inteira.
  bool get _whole => item.subcategoryId == null;
  String get title => _whole ? categoryName : label;
  String get subtitle => _whole ? label : categoryName;
}

/// Linhas de despesa com folga entre previsto e consumido, maior folga primeiro
/// (é por onde vale começar a cortar).
List<_SqueezeTarget> _squeezeTargets({
  required List<LocalBudgetItem> items,
  required Map<String, LocalCategory> categories,
  required Map<String, LocalSubcategory> subcategories,
  required double Function(LocalBudgetItem item) consumedOf,
  required Color fallbackColor,
}) {
  final targets = [
    for (final item in items)
      _SqueezeTarget(
        item: item,
        categoryName: categories[item.categoryId]?.name ?? 'Categoria',
        label: _budgetItemDisplayName(item, subcategories),
        consumed: consumedOf(item),
        color: _parseColor(categories[item.categoryId]?.color) ?? fallbackColor,
      ),
  ]..sort((a, b) => b.slack.compareTo(a.slack));
  return [
    for (final target in targets)
      if (target.hasSlack) target,
  ];
}

void _showBudgetSqueezeSheet(
  BuildContext context,
  List<_SqueezeTarget> targets,
) {
  if (targets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sem folga para apertar: o consumido alcançou o previsto'),
      ),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BudgetSqueezeSheet(targets: targets),
  );
}

class _BudgetSqueezeSheet extends ConsumerStatefulWidget {
  const _BudgetSqueezeSheet({required this.targets});

  final List<_SqueezeTarget> targets;

  @override
  ConsumerState<_BudgetSqueezeSheet> createState() =>
      _BudgetSqueezeSheetState();
}

class _BudgetSqueezeSheetState extends ConsumerState<_BudgetSqueezeSheet> {
  final _formKey = GlobalKey<FormState>();

  /// Previsto em edição por item. Começa no valor atual: abrir a folha não
  /// muda nada até alguém arrastar.
  late final Map<String, double> _planned = {
    for (final target in widget.targets) target.item.id: target.planned,
  };
  bool _saving = false;

  double _valueOf(_SqueezeTarget target) =>
      _planned[target.item.id] ?? target.planned;

  double get _freed => _round2(
    widget.targets.fold<double>(
      0,
      (sum, target) => sum + (target.planned - _valueOf(target)),
    ),
  );

  List<_SqueezeTarget> get _changed => [
    for (final target in widget.targets)
      if (_valueOf(target) != target.planned) target,
  ];

  void _set(_SqueezeTarget target, double value) {
    final clamped = _round2(value.clamp(target.floor, target.planned));
    if (clamped == _valueOf(target)) return;
    setState(() => _planned[target.item.id] = clamped);
  }

  Future<void> _persist(
    FinanceRepository repo,
    LocalBudgetItem item,
    double plannedAmount,
  ) => repo.upsertBudgetItem(
    id: item.id,
    budgetId: item.budgetId,
    categoryId: item.categoryId,
    subcategoryId: item.subcategoryId,
    plannedAmount: plannedAmount,
    isFixed: item.isFixed,
    dueDay: item.dueDay,
    accountId: item.accountId,
    cardId: item.cardId,
    currentVersion: item.version,
  );

  Future<void> _apply() async {
    final changed = _changed;
    if (changed.isEmpty) return;
    setState(() => _saving = true);
    // Capturados antes do pop: o desfazer da snackbar sobrevive a esta folha.
    final repo = ref.read(financeRepositoryProvider);
    final sync = ref.read(syncServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final freed = _freed;

    for (final target in changed) {
      await _persist(repo, target.item, _valueOf(target));
    }
    sync.syncNow();
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Previsto apertado: ${formatMoney(freed)} de folga'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            for (final target in changed) {
              await _persist(repo, target.item, target.planned);
            }
            sync.syncNow();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = widget.targets;
    final freed = _freed;
    final changedCount = _changed.length;

    return PremiumFormSheet(
      title: 'Aperto do previsto',
      subtitle: targets.length == 1
          ? 'Arraste até onde o mês já consumiu — o consumido é o limite.'
          : '${targets.length} linhas com folga. Arraste cada uma até onde o mês já consumiu.',
      icon: Icons.compress_rounded,
      formKey: _formKey,
      fields: [
        for (final target in targets)
          PremiumFormSection(
            title: target.title,
            subtitle: target.subtitle,
            children: [
              _SqueezeSlider(
                target: target,
                value: _valueOf(target),
                onChanged: (value) => _set(target, value),
              ),
            ],
          ),
        if (targets.length > 1)
          AppSurface.flat(
            color: context.hopeColors.positiveSurface,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Folga liberada',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        changedCount == 0
                            ? 'Nenhuma linha apertada ainda'
                            : changedCount == 1
                            ? '1 linha apertada'
                            : '$changedCount linhas apertadas',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HopeSpacing.sm),
                MoneyText(
                  freed,
                  emphasis: MoneyEmphasis.primary,
                  color: freed >= 0.01 ? context.hopeColors.success : null,
                  semanticsPrefix: 'Folga liberada',
                ),
              ],
            ),
          ),
      ],
      secondaryAction: OutlinedButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _saving || freed < 0.01 ? null : _apply,
        icon: const Icon(Icons.compress_rounded),
        label: Text(
          freed < 0.01
              ? 'Arraste para apertar'
              : 'Apertar ${formatMoney(freed)}',
        ),
      ),
    );
  }
}

/// A barra de arraste do aperto.
///
/// A escala é o previsto original inteiro (0 → previsto), então a fatia já
/// consumida aparece no mesmo tamanho que tem na barra da lista. O polegar
/// trava nessa fatia: é o limite anunciado pelo recurso, não um erro.
class _SqueezeSlider extends StatelessWidget {
  const _SqueezeSlider({
    required this.target,
    required this.value,
    required this.onChanged,
  });

  final _SqueezeTarget target;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.hopeColors;
    final muted = theme.colorScheme.onSurfaceVariant;
    final freed = _round2(target.planned - value);
    final squeezed = freed >= 0.01;
    final consumedFraction = target.planned <= 0
        ? 0.0
        : target.floor / target.planned;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Novo previsto',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            MoneyText(
              value,
              emphasis: MoneyEmphasis.primary,
              color: squeezed ? colors.success : null,
              semanticsPrefix: 'Novo previsto de ${target.title}',
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 12,
            trackShape: _ConsumedFloorTrackShape(
              consumedFraction: consumedFraction,
              consumedColor: colors.expense,
            ),
            activeTrackColor: target.color.withValues(alpha: 0.38),
            inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
            thumbColor: theme.colorScheme.primary,
            overlayColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 11,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
          ),
          child: Slider(
            value: value.clamp(0, target.planned),
            max: target.planned,
            // O piso é aplicado no callback, num lugar só: teclado, leitor de
            // tela e arraste travam no mesmo ponto.
            onChanged: onChanged,
            semanticFormatterCallback: moneySemanticLabel,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Consumido',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  // O cadeado fica junto do número, não do rótulo: é o valor
                  // que está travado.
                  Row(
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: colors.expense),
                      const SizedBox(width: HopeSpacing.xxs),
                      Flexible(
                        child: MoneyText(
                          target.floor,
                          emphasis: MoneyEmphasis.caption,
                          color: colors.expense,
                          semanticsPrefix: 'Consumido',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: HopeSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    squeezed ? 'Libera' : 'Previsto atual',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  MoneyText(
                    squeezed ? freed : target.planned,
                    emphasis: MoneyEmphasis.caption,
                    color: squeezed ? colors.success : muted,
                    textAlign: TextAlign.end,
                    semanticsPrefix: squeezed ? 'Libera' : 'Previsto atual',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Trilha que pinta a fatia já consumida do previsto.
///
/// Sem ela a barra não explica por que o polegar travou no meio do caminho.
class _ConsumedFloorTrackShape extends RoundedRectSliderTrackShape {
  const _ConsumedFloorTrackShape({
    required this.consumedFraction,
    required this.consumedColor,
  });

  final double consumedFraction;
  final Color consumedColor;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final fraction = consumedFraction.clamp(0.0, 1.0);
    if (fraction <= 0 || (sliderTheme.trackHeight ?? 0) <= 0) return;

    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final width = track.width * fraction;
    if (width <= 0) return;
    // Acompanha a altura extra da trilha ativa: a fatia consumida está sempre
    // dentro dela, então as duas precisam terminar na mesma linha.
    final grow = additionalActiveTrackHeight / 2;
    final rtl = textDirection == TextDirection.rtl;
    final left = rtl ? track.right - width : track.left;
    final radius = Radius.circular(
      (track.height + additionalActiveTrackHeight) / 2,
    );
    // Arredonda só a ponta inicial da trilha; a outra é um corte reto, que é o
    // muro onde o arraste para. Quando a fatia ocupa tudo, as duas arredondam.
    final startRadius = fraction >= 0.999 ? radius : Radius.zero;
    context.canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(left, track.top - grow, width, track.height + grow * 2),
        topLeft: rtl ? startRadius : radius,
        bottomLeft: rtl ? startRadius : radius,
        topRight: rtl ? radius : startRadius,
        bottomRight: rtl ? radius : startRadius,
      ),
      Paint()..color = consumedColor,
    );
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

class _BudgetCategoryCard extends StatelessWidget {
  const _BudgetCategoryCard({
    required this.group,
    required this.subcategories,
    required this.accounts,
    required this.cards,
    required this.isIncome,
    required this.onTapItem,
    required this.onAddSubcategory,
    this.onSqueeze,
  });

  final _BudgetCategoryGroup group;
  final Map<String, LocalSubcategory> subcategories;
  final Map<String, LocalAccount> accounts;
  final Map<String, LocalCreditCard> cards;
  final bool isIncome;
  final ValueChanged<LocalBudgetItem> onTapItem;
  final VoidCallback onAddSubcategory;

  /// Só chega preenchido quando a categoria tem folga para apertar.
  final VoidCallback? onSqueeze;

  @override
  Widget build(BuildContext context) {
    final over = !isIncome && group.realized > group.planned;
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
                '$subcategoryText · ${formatMoney(group.realized)} de ${formatMoney(group.planned)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: over ? context.hopeColors.expense : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: clampProgress(group.realized, group.planned),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: over ? context.hopeColors.expense : color,
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
                  ),
                const SizedBox(height: HopeSpacing.xs),
                // Wrap e não Row: em tela estreita os dois botões empilham em
                // vez de disputar a largura.
                Wrap(
                  spacing: HopeSpacing.xs,
                  runSpacing: HopeSpacing.xs,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onAddSubcategory,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Adicionar subcategoria'),
                    ),
                    if (onSqueeze != null)
                      OutlinedButton.icon(
                        onPressed: onSqueeze,
                        icon: const Icon(Icons.compress_rounded, size: 18),
                        label: const Text('Apertar previsto'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetItemRow extends StatelessWidget {
  const _BudgetItemRow({
    required this.item,
    required this.subcategory,
    required this.account,
    required this.card,
    required this.isIncome,
    required this.color,
    required this.realized,
    required this.onTap,
  });

  final LocalBudgetItem item;
  final LocalSubcategory? subcategory;
  final LocalAccount? account;
  final LocalCreditCard? card;
  final bool isIncome;
  final Color color;
  final double realized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final over = !isIncome && realized > item.plannedAmount;
    final title = subcategory?.name ?? 'Toda a categoria';
    final fixedText = item.isFixed
        ? item.dueDay == null
              ? 'Fixa'
              : 'Fixa · dia ${item.dueDay}'
        : null;
    final destinationText = card != null
        ? 'Cartão 💳 ${card!.name}'
        : account == null
        ? null
        : isIncome
        ? 'Entra em ${account!.name}'
        : 'Sai de ${account!.name}';
    final details = [?fixedText, ?destinationText].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(HopeRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
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
                    '${formatMoney(realized)} / ${formatMoney(item.plannedAmount)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: over ? context.hopeColors.expense : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: clampProgress(realized, item.plannedAmount),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              color: over ? context.hopeColors.expense : color,
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
