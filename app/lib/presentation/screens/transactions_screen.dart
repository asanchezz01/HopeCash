import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../../core/utils/transaction_export.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';
import '../widgets/debt_payment_sheet.dart';
import '../widgets/edit_transaction_sheet.dart';
import '../widgets/month_navigator.dart';

final _filterProvider = StateProvider<String>((ref) => 'all');

/// Modo de exibição da lista.
///
/// [statement] (Extrato): só o que aconteceu de fato — movimentações pagas na
/// conta ou, com um cartão selecionado, as compras lançadas na fatura. Serve
/// para conferir extrato bancário e fatura.
/// [planned] (Previsto): visão de planejamento — inclui lançamentos previstos
/// com seus valores orçados.
enum _ViewMode { statement, planned }

final _viewModeProvider = StateProvider<_ViewMode>((ref) => _ViewMode.planned);

/// Ordenação do extrato: true = mais recentes primeiro (padrão).
final _statementSortDescProvider = StateProvider<bool>((ref) => true);

/// Origem de um filtro: conta ou cartão de crédito.
enum _SourceKind { account, card }

/// Seleção de origem no filtro (conta ou cartão). `null` = todas as origens.
class _SourceFilter {
  const _SourceFilter(this.kind, this.id);

  final _SourceKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is _SourceFilter && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Filtro por conta ou cartão (null = todas as origens).
final _accountFilterProvider = StateProvider<_SourceFilter?>((ref) => null);

/// Texto de busca por descrição/categoria.
final _searchProvider = StateProvider<String>((ref) => '');

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({
    super.key,
    this.initialSourceKind,
    this.initialSourceId,
    this.initialOpenTransactionId,
  });

  final String? initialSourceKind;
  final String? initialSourceId;

  /// Id de um lançamento específico a abrir assim que os dados locais
  /// estiverem disponíveis (link "Ver lançamento" vindo do chat da Hope).
  final String? initialOpenTransactionId;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  bool _openedTarget = false;

  /// Aplica o filtro de origem vindo da rota ("ver lançamentos" de uma conta
  /// ou cartão) uma única vez. Antes isso rodava a cada rebuild e desfazia
  /// qualquer troca manual de origem no frame seguinte.
  void _applyInitialFilter() {
    final initial = _sourceFilterFromRoute(
      widget.initialSourceKind,
      widget.initialSourceId,
    );
    if (initial == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(_accountFilterProvider.notifier).state = initial;
    });
  }

  @override
  void initState() {
    super.initState();
    _applyInitialFilter();
  }

  @override
  void didUpdateWidget(covariant TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nova navegação para outra origem reaproveita o mesmo State.
    if (widget.initialSourceKind != oldWidget.initialSourceKind ||
        widget.initialSourceId != oldWidget.initialSourceId) {
      _applyInitialFilter();
    }
    if (widget.initialOpenTransactionId != oldWidget.initialOpenTransactionId) {
      _openedTarget = false;
    }
  }

  /// Abre o lançamento pedido pela rota assim que ele aparecer nos dados
  /// locais. Fica tentando a cada rebuild (sem marcar como feito) até achar,
  /// pois logo após confirmar uma ação no chat o sync ainda pode estar em
  /// andamento quando esta tela abre.
  void _maybeOpenTarget(List<LocalTransaction> all) {
    final targetId = widget.initialOpenTransactionId;
    if (targetId == null || _openedTarget) return;
    final matches = all.where((t) => t.id == targetId);
    if (matches.isEmpty) return;
    final target = matches.first;
    _openedTarget = true;
    final month = DateTime.parse(target.competenceDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedMonthProvider.notifier).state = DateTime(
        month.year,
        month.month,
      );
      showTransactionActions(context, ref, target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(_viewModeProvider);
    final statement = mode == _ViewMode.statement;
    final sortDesc = ref.watch(_statementSortDescProvider);
    final filter = ref.watch(_filterProvider);
    final accountFilter = ref.watch(_accountFilterProvider);
    final search = ref.watch(_searchProvider).trim().toLowerCase();
    final month = ref.watch(selectedMonthProvider);
    final monthKey =
        '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}';
    final txsAsync = ref.watch(transactionsProvider);
    if (txsAsync.valueOrNull != null) _maybeOpenTarget(txsAsync.valueOrNull!);
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? <LocalAccount>[];
    final categories = {
      for (final c
          in ref.watch(categoriesProvider).valueOrNull ?? <LocalCategory>[])
        c.id: c.name,
    };
    final subcategories = {
      for (final s
          in ref.watch(subcategoriesProvider).valueOrNull ??
              <LocalSubcategory>[])
        s.id: s.name,
    };
    final cardList =
        ref.watch(creditCardsProvider).valueOrNull ?? <LocalCreditCard>[];
    final activeCards = cardList.where((c) => c.isActive).toList();
    final cards = {for (final c in cardList) c.id: c.name};
    final accountNames = {for (final a in accounts) a.id: a.name};

    Future<void> exportToExcel() async {
      final all =
          ref.read(transactionsProvider).valueOrNull ?? <LocalTransaction>[];
      final exportCardView =
          statement && accountFilter?.kind == _SourceKind.card;
      String sortDate(LocalTransaction t) => statement
          ? _statementDate(t, cardView: exportCardView)
          : t.competenceDate;
      final rows =
          all
              .where(
                (t) => _txMatches(
                  t,
                  monthKey: monthKey,
                  filter: filter,
                  accountFilter: accountFilter,
                  search: search,
                  categoryNames: categories,
                  subcategoryNames: subcategories,
                  statement: statement,
                ),
              )
              .toList()
            ..sort((a, b) {
              final cmp = sortDate(a).compareTo(sortDate(b));
              return statement && sortDesc ? -cmp : cmp;
            });

      final messenger = ScaffoldMessenger.of(context);
      if (rows.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nada para exportar neste filtro.')),
        );
        return;
      }

      final bytes = buildTransactionsXlsx(
        transactions: rows,
        categoryNames: categories,
        accountNames: {for (final a in accounts) a.id: a.name},
        cardNames: cards,
      );
      final filename = 'lancamentos_$monthKey.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: xlsxMimeType,
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
          subject: 'Lançamentos $monthKey',
        ),
      );
    }

    Future<void> exportToPdf() async {
      final all =
          ref.read(transactionsProvider).valueOrNull ?? <LocalTransaction>[];
      final exportCardView =
          statement && accountFilter?.kind == _SourceKind.card;
      String sortDate(LocalTransaction t) => statement
          ? _statementDate(t, cardView: exportCardView)
          : t.competenceDate;
      final rows =
          all
              .where(
                (t) => _txMatches(
                  t,
                  monthKey: monthKey,
                  filter: filter,
                  accountFilter: accountFilter,
                  search: search,
                  categoryNames: categories,
                  subcategoryNames: subcategories,
                  statement: statement,
                ),
              )
              .toList()
            ..sort((a, b) {
              final cmp = sortDate(a).compareTo(sortDate(b));
              return statement && sortDesc ? -cmp : cmp;
            });
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nada para exportar neste filtro.')),
        );
        return;
      }
      final bytes = await buildTransactionsPdf(
        transactions: rows,
        categoryNames: categories,
        accountNames: accountNames,
        cardNames: cards,
        title: 'Lançamentos $monthKey',
      );
      final filename = 'lancamentos_$monthKey.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: pdfMimeType,
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
          subject: 'Lançamentos $monthKey',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lançamentos'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Exportar lançamentos filtrados',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (value) {
              if (value == 'excel') exportToExcel();
              if (value == 'pdf') exportToPdf();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'excel', child: Text('Compartilhar Excel')),
              PopupMenuItem(value: 'pdf', child: Text('Compartilhar PDF')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _TransactionsToolbar(
            mode: mode,
            filter: filter,
            accountFilter: accountFilter,
            sortDesc: sortDesc,
            accounts: accounts,
            cards: activeCards,
          ),
          Expanded(
            child:
                !statement &&
                    (filter == 'planned_income' || filter == 'planned_expense')
                ? _PlannedList(
                    monthKey: monthKey,
                    incomeView: filter == 'planned_income',
                    accountFilter: accountFilter,
                    search: search,
                    categoryNames: categories,
                    subcategoryNames: subcategories,
                    cardNames: cards,
                    accountNames: {for (final a in accounts) a.id: a.name},
                  )
                : txsAsync.when(
                    loading: () => const HopeSkeleton(rows: 8),
                    error: (error, _) => HopeErrorState.load(
                      error,
                      what: 'seus lançamentos',
                      onRetry: () => ref.invalidate(transactionsProvider),
                    ),
                    data: (all) {
                      final cardView =
                          statement && accountFilter?.kind == _SourceKind.card;
                      final txs = all
                          .where(
                            (t) => _txMatches(
                              t,
                              monthKey: monthKey,
                              filter: filter,
                              accountFilter: accountFilter,
                              search: search,
                              categoryNames: categories,
                              subcategoryNames: subcategories,
                              statement: statement,
                            ),
                          )
                          .toList();

                      if (txs.isEmpty) {
                        final filtering =
                            filter != 'all' ||
                            accountFilter != null ||
                            search.isNotEmpty;
                        // Sem filtros ativos, mas há lançamentos em outros
                        // meses: o mês selecionado é que está vazio.
                        final emptyMonth = !filtering && all.isNotEmpty;
                        return _EmptyPlaceholder(
                          icon: filtering || emptyMonth
                              ? Icons.search_off_outlined
                              : Icons.receipt_long_outlined,
                          title: statement
                              ? 'Nada realizado neste período'
                              : filtering || emptyMonth
                              ? 'Nenhum lançamento encontrado'
                              : 'Nenhum lançamento ainda',
                          subtitle: statement
                              ? 'O extrato mostra só o que foi efetivado. '
                                    'Lançamentos futuros ficam no modo '
                                    'Previsto.'
                              : emptyMonth
                              ? 'Nenhum lançamento neste mês.'
                              : filtering
                              ? 'Ajuste os filtros ou a busca.'
                              : 'Toque em + para começar.',
                        );
                      }

                      // Extrato agrupa pela data em que o valor aconteceu
                      // (pagamento/compra); previsto, pela competência.
                      final groups = <String, List<LocalTransaction>>{};
                      for (final t in txs) {
                        final date = statement
                            ? _statementDate(t, cardView: cardView)
                            : t.competenceDate;
                        groups.putIfAbsent(date, () => []).add(t);
                      }
                      final dates = groups.keys.toList()
                        ..sort(
                          (a, b) => statement && !sortDesc
                              ? a.compareTo(b)
                              : b.compareTo(a),
                        );

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: dates.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return statement
                                ? _StatementTotals(txs: txs, cardView: cardView)
                                : _MixedTotals(txs: txs);
                          }
                          final date = dates[index - 1];
                          final items = groups[date]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  formatDate(date),
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ),
                              for (final t in items)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: _TransactionTile(
                                    tx: t,
                                    categoryName: _categoryLabel(
                                      categories[t.categoryId],
                                      subcategories[t.subcategoryId],
                                    ),
                                    accountName: accountNames[t.accountId],
                                    cardName: cards[t.cardId],
                                    statement: statement,
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Barra de controle da lista.
///
/// Antes eram cinco faixas empilhadas — busca, mês, modo, tipo, origem e
/// ordenação — que comiam cerca de 300px antes do primeiro lançamento aparecer
/// num celular. Agora só o que muda a leitura fica na tela: busca, mês e modo.
/// Tipo, origem e ordenação vão para uma folha, e o que estiver ativo volta
/// como etiqueta removível.
class _TransactionsToolbar extends ConsumerWidget {
  const _TransactionsToolbar({
    required this.mode,
    required this.filter,
    required this.accountFilter,
    required this.sortDesc,
    required this.accounts,
    required this.cards,
  });

  final _ViewMode mode;
  final String filter;
  final _SourceFilter? accountFilter;
  final bool sortDesc;
  final List<LocalAccount> accounts;
  final List<LocalCreditCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = mode == _ViewMode.statement;
    final activeCount = (filter == 'all' ? 0 : 1) + (accountFilter == null ? 0 : 1);
    final padding = context.pagePadding;

    final modeSelector = SegmentedButton<_ViewMode>(
      segments: const [
        ButtonSegment(
          value: _ViewMode.statement,
          icon: Icon(Icons.receipt_long_outlined),
          label: Text('Extrato'),
        ),
        ButtonSegment(
          value: _ViewMode.planned,
          icon: Icon(Icons.event_note_outlined),
          label: Text('Previsto'),
        ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        final next = selection.first;
        ref.read(_viewModeProvider.notifier).state = next;
        // Os filtros de previstos não existem no extrato.
        if (next == _ViewMode.statement && filter.startsWith('planned_')) {
          ref.read(_filterProvider.notifier).state = 'all';
        }
      },
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, HopeSpacing.xxs, padding, HopeSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _SearchField()),
              const SizedBox(width: HopeSpacing.xs),
              _FilterButton(
                activeCount: activeCount,
                onPressed: () => _showFiltersSheet(
                  context,
                  ref,
                  statement: statement,
                  accounts: accounts,
                  cards: cards,
                ),
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MonthNavigator(),
                    const SizedBox(height: HopeSpacing.xs),
                    modeSelector,
                  ],
                );
              }
              return Row(
                children: [
                  const Expanded(child: MonthNavigator()),
                  const SizedBox(width: HopeSpacing.xs),
                  modeSelector,
                ],
              );
            },
          ),
          if (activeCount > 0 || (statement && !sortDesc))
            Padding(
              padding: const EdgeInsets.only(top: HopeSpacing.xs),
              child: Wrap(
                spacing: HopeSpacing.xs,
                runSpacing: HopeSpacing.xxs,
                children: [
                  if (filter != 'all')
                    _ActiveFilterChip(
                      label: _filterLabel(filter),
                      onClear: () =>
                          ref.read(_filterProvider.notifier).state = 'all',
                    ),
                  if (accountFilter != null)
                    _ActiveFilterChip(
                      label: _sourceLabel(accountFilter!, accounts, cards),
                      onClear: () =>
                          ref.read(_accountFilterProvider.notifier).state = null,
                    ),
                  if (statement && !sortDesc)
                    _ActiveFilterChip(
                      label: 'Mais antigas primeiro',
                      onClear: () => ref
                          .read(_statementSortDescProvider.notifier)
                          .state = true,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _filterLabel(String filter) => switch (filter) {
  'income' => 'Receitas',
  'expense' => 'Despesas',
  'planned_income' => 'Receitas previstas',
  'planned_expense' => 'Despesas previstas',
  _ => 'Todos',
};

String _sourceLabel(
  _SourceFilter source,
  List<LocalAccount> accounts,
  List<LocalCreditCard> cards,
) {
  if (source.kind == _SourceKind.account) {
    final match = accounts.where((a) => a.id == source.id);
    return match.isEmpty ? 'Conta' : match.first.name;
  }
  final match = cards.where((c) => c.id == source.id);
  return match.isEmpty ? 'Cartão' : 'Cartão ${match.first.name}';
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Filtrar e ordenar',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: active,
          label: Text('$activeCount'),
          child: const Icon(Icons.tune_rounded, size: 20),
        ),
        label: Text(context.isPhone ? '' : 'Filtros'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(kHopeMinTapTarget, kHopeMinTapTarget),
          padding: EdgeInsets.symmetric(
            horizontal: context.isPhone ? HopeSpacing.sm : HopeSpacing.md,
          ),
          foregroundColor: active ? scheme.primary : scheme.onSurfaceVariant,
          side: BorderSide(
            color: active ? scheme.primary : context.hopeColors.softBorder,
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteButtonTooltipMessage: 'Remover filtro $label',
      visualDensity: VisualDensity.compact,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
    );
  }
}

Future<void> _showFiltersSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool statement,
  required List<LocalAccount> accounts,
  required List<LocalCreditCard> cards,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final filter = ref.watch(_filterProvider);
        final accountFilter = ref.watch(_accountFilterProvider);
        final sortDesc = ref.watch(_statementSortDescProvider);
        final hasAny = filter != 'all' || accountFilter != null;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                HopeSpacing.lg,
                HopeSpacing.xs,
                HopeSpacing.lg,
                HopeSpacing.lg,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filtrar e ordenar',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (hasAny)
                      TextButton(
                        onPressed: () {
                          ref.read(_filterProvider.notifier).state = 'all';
                          ref.read(_accountFilterProvider.notifier).state = null;
                        },
                        child: const Text('Limpar'),
                      ),
                  ],
                ),
                const SizedBox(height: HopeSpacing.md),
                Text('Tipo', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: HopeSpacing.xs),
                Wrap(
                  spacing: HopeSpacing.xs,
                  runSpacing: HopeSpacing.xs,
                  children: [
                    for (final (value, label) in [
                      ('all', 'Todos'),
                      ('income', 'Receitas'),
                      ('expense', 'Despesas'),
                      if (!statement) ('planned_income', 'Receitas previstas'),
                      if (!statement) ('planned_expense', 'Despesas previstas'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: filter == value,
                        onSelected: (_) =>
                            ref.read(_filterProvider.notifier).state = value,
                      ),
                  ],
                ),
                if (accounts.isNotEmpty || cards.isNotEmpty) ...[
                  const SizedBox(height: HopeSpacing.lg),
                  Text('Origem', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: HopeSpacing.xs),
                  Wrap(
                    spacing: HopeSpacing.xs,
                    runSpacing: HopeSpacing.xs,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 18,
                        ),
                        label: const Text('Todas'),
                        selected: accountFilter == null,
                        onSelected: (_) => ref
                            .read(_accountFilterProvider.notifier)
                            .state = null,
                      ),
                      for (final a in accounts)
                        ChoiceChip(
                          avatar: const Icon(
                            Icons.account_balance_outlined,
                            size: 18,
                          ),
                          label: Text(a.name),
                          selected:
                              accountFilter ==
                              _SourceFilter(_SourceKind.account, a.id),
                          onSelected: (_) {
                            final selection = _SourceFilter(
                              _SourceKind.account,
                              a.id,
                            );
                            ref.read(_accountFilterProvider.notifier).state =
                                accountFilter == selection ? null : selection;
                          },
                        ),
                      for (final c in cards)
                        ChoiceChip(
                          avatar: const Icon(Icons.credit_card_outlined, size: 18),
                          label: Text(c.name),
                          selected:
                              accountFilter ==
                              _SourceFilter(_SourceKind.card, c.id),
                          onSelected: (_) {
                            final selection = _SourceFilter(
                              _SourceKind.card,
                              c.id,
                            );
                            ref.read(_accountFilterProvider.notifier).state =
                                accountFilter == selection ? null : selection;
                          },
                        ),
                    ],
                  ),
                ],
                if (statement) ...[
                  const SizedBox(height: HopeSpacing.lg),
                  Text(
                    'Ordenação',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: HopeSpacing.xs),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Mais recentes'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Mais antigas'),
                      ),
                    ],
                    selected: {sortDesc},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => ref
                        .read(_statementSortDescProvider.notifier)
                        .state = selection.first,
                  ),
                ],
                const SizedBox(height: HopeSpacing.lg),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Ver resultados'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

_SourceFilter? _sourceFilterFromRoute(String? kind, String? id) {
  if (id == null || id.isEmpty) return null;
  return switch (kind) {
    'account' => _SourceFilter(_SourceKind.account, id),
    'card' => _SourceFilter(_SourceKind.card, id),
    _ => null,
  };
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.tx,
    this.categoryName,
    this.accountName,
    this.cardName,
    this.statement = false,
  });

  final LocalTransaction tx;
  final String? categoryName;
  final String? accountName;
  final String? cardName;

  /// Modo extrato: o lançamento é um fato (compra na fatura ou pagamento) e o
  /// valor aparece sempre pleno; o chip indica a fatura em vez de "previsto".
  final bool statement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = tx.type == 'income';
    final value = tx.amount ?? tx.amountPlanned ?? 0;
    final planned = tx.status == 'planned' || tx.status == 'overdue';
    final color = isIncome
        ? context.hopeColors.income
        : context.hopeColors.expense;
    // No modo previsto, valores que ainda não aconteceram ficam atenuados para
    // se distinguirem dos efetivados.
    final valueColor = !statement && planned
        ? color.withValues(alpha: 0.55)
        : color;
    final onCardInvoice = statement && planned && tx.cardId != null;
    final statusLabel = onCardInvoice
        ? (tx.dueDate != null
              ? 'fatura ${_shortDate(tx.dueDate!)}'
              : 'na fatura')
        : switch (tx.status) {
            'paid' => isIncome ? 'recebido' : 'pago',
            'overdue' => 'atrasado',
            'canceled' => 'cancelado',
            _ => 'previsto',
          };

    Future<void> markPaid() async {
      if (!planned) return;
      await ref.read(financeRepositoryProvider).markPaid(tx);
      ref.read(syncServiceProvider).syncNow();
      if (context.mounted) {
        showHopeSnack(
          context,
          isIncome ? 'Recebimento confirmado' : 'Pagamento confirmado',
          tone: HopeSnackTone.success,
        );
      }
    }

    Future<void> delete() async {
      // Deslizar para a esquerda apagava o lançamento na hora, sem aviso e sem
      // volta. Agora o gesto abre a confirmação.
      final confirmed = await confirmDeleteTransaction(context, tx);
      if (!confirmed) return;
      await ref.read(financeRepositoryProvider).deleteTransaction(tx);
      ref.read(syncServiceProvider).syncNow();
      if (context.mounted) {
        showHopeSnack(context, 'Lançamento excluído', tone: HopeSnackTone.danger);
      }
    }

    return Dismissible(
      key: ValueKey('transaction-${tx.id}'),
      // Sem lançamento previsto não há o que confirmar: o gesto para a direita
      // fica desabilitado em vez de não fazer nada.
      direction: planned
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (planned) await markPaid();
        } else {
          await delete();
        }
        return false;
      },
      background: _SwipeActionBackground(
        alignment: Alignment.centerLeft,
        color: context.hopeColors.success,
        icon: Icons.check_circle_outline_rounded,
        label: isIncome ? 'Receber' : 'Pagar',
      ),
      secondaryBackground: _SwipeActionBackground(
        alignment: Alignment.centerRight,
        color: context.hopeColors.expense,
        icon: Icons.delete_outline_rounded,
        label: 'Excluir',
      ),
      child: AppSurface(
        padding: const EdgeInsets.all(HopeSpacing.sm),
        onTap: () => showTransactionActions(context, ref, tx),
        child: Row(
          children: [
            FinanceIconBadge(
              icon: isIncome
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: color,
              size: 42,
            ),
            const SizedBox(width: HopeSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      ?categoryName,
                      ?accountName,
                      if (cardName != null) 'Cartão $cardName',
                      if (tx.syncStatus == 'pending') 'aguardando sync',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HopeSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  isIncome ? value : -value,
                  signed: true,
                  color: valueColor,
                  strikethrough: tx.status == 'canceled',
                  semanticsPrefix: isIncome ? 'Receita' : 'Despesa',
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(HopeRadius.pill),
                  ),
                  child: Text(
                    statusLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final right = alignment == Alignment.centerRight;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: HopeSpacing.lg),
      alignment: alignment,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(HopeRadius.md),
      ),
      child: Row(
        mainAxisAlignment: right
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!right) Icon(icon, color: color),
          if (!right) const SizedBox(width: HopeSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (right) const SizedBox(width: HopeSpacing.xs),
          if (right) Icon(icon, color: color),
        ],
      ),
    );
  }
}

/// Confirmação de exclusão de um lançamento.
///
/// Exclusão é irreversível e mexe nos totais do mês: nunca acontece com um
/// toque só. O diálogo nomeia o lançamento para o usuário conferir que é ele
/// mesmo.
Future<bool> confirmDeleteTransaction(
  BuildContext context,
  LocalTransaction tx, {
  String? extraWarning,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir lançamento?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${tx.description}" · ${formatMoney(tx.amount ?? tx.amountPlanned)}',
            style: Theme.of(dialogContext).textTheme.titleSmall,
          ),
          const SizedBox(height: HopeSpacing.xs),
          Text(
            extraWarning ??
                'Ele sai das suas listas e dos totais do mês. Não dá para '
                    'desfazer.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Ações de um lançamento (marcar pago/recebido, excluir), reutilizadas pelas
/// listas simples e pelas listas de previstos.
void showTransactionActions(
  BuildContext context,
  WidgetRef ref,
  LocalTransaction tx,
) {
  final debtPayment = FinanceRepository.isDebtPayment(tx);
  final isIncome = tx.type == 'income';
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HopeSpacing.lg,
              0,
              HopeSpacing.lg,
              HopeSpacing.sm,
            ),
            child: Row(
              children: [
                FinanceIconBadge(
                  icon: isIncome
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: isIncome
                      ? sheetContext.hopeColors.income
                      : sheetContext.hopeColors.expense,
                ),
                const SizedBox(width: HopeSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      Text(
                        formatDate(tx.competenceDate),
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HopeSpacing.xs),
                MoneyText(
                  tx.amount ?? tx.amountPlanned,
                  emphasis: MoneyEmphasis.primary,
                  color: isIncome
                      ? sheetContext.hopeColors.income
                      : sheetContext.hopeColors.expense,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (debtPayment)
            ListTile(
              leading: Icon(
                Icons.account_balance_outlined,
                color: sheetContext.hopeColors.warning,
              ),
              title: const Text('Pagamento vinculado a dívida'),
              subtitle: const Text('A exclusão restaura o saldo devedor.'),
            ),
          if (debtPayment)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar baixa'),
              onTap: () {
                Navigator.pop(sheetContext);
                showEditDebtPaymentSheet(context, tx);
              },
            ),
          if (!debtPayment &&
              (tx.status == 'planned' || tx.status == 'overdue'))
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(
                isIncome ? 'Marcar como recebido' : 'Marcar como pago',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(financeRepositoryProvider).markPaid(tx);
                ref.read(syncServiceProvider).syncNow();
                if (context.mounted) {
                  showHopeSnack(
                    context,
                    isIncome ? 'Recebimento confirmado' : 'Pagamento confirmado',
                    tone: HopeSnackTone.success,
                  );
                }
              },
            ),
          if (!debtPayment && tx.status == 'paid')
            ListTile(
              leading: const Icon(Icons.undo_outlined),
              title: const Text('Voltar para previsto'),
              subtitle: const Text('Desfaz a baixa e devolve o valor ao saldo'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(financeRepositoryProvider).markPlanned(tx);
                ref.read(syncServiceProvider).syncNow();
                if (context.mounted) {
                  showHopeSnack(context, 'Lançamento voltou para previsto');
                }
              },
            ),
          if (!debtPayment)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(sheetContext);
                showEditTransactionSheet(context, tx);
              },
            ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(sheetContext).colorScheme.error,
            ),
            textColor: Theme.of(sheetContext).colorScheme.error,
            title: Text(debtPayment ? 'Excluir baixa da dívida' : 'Excluir'),
            onTap: () async {
              Navigator.pop(sheetContext);
              if (!context.mounted) return;
              final confirmed = await confirmDeleteTransaction(
                context,
                tx,
                extraWarning: debtPayment
                    ? 'A baixa é desfeita e o saldo devedor da dívida volta a '
                          'subir. Não dá para desfazer.'
                    : null,
              );
              if (!confirmed) return;
              await ref.read(financeRepositoryProvider).deleteTransaction(tx);
              ref.read(syncServiceProvider).syncNow();
              if (context.mounted) {
                showHopeSnack(
                  context,
                  'Lançamento excluído',
                  tone: HopeSnackTone.danger,
                );
              }
            },
          ),
          const SizedBox(height: HopeSpacing.xs),
        ],
      ),
    ),
  );
}

Future<void> _showDebtPaymentSheet(BuildContext context, PlannedEntry entry) {
  final debt = entry.debt;
  final dueDate = entry.dueDate;
  final installmentNumber = entry.debtInstallmentNumber;
  if (debt == null || dueDate == null || installmentNumber == null) {
    return Future.value();
  }
  return showDebtPaymentSheet(
    context,
    debt: debt,
    plannedAmount: entry.planned,
    dueDate: dueDate,
    installmentNumber: installmentNumber,
  );
}

/// Lançamentos absorvidos por uma linha de orçamento: lista as transações que
/// compõem o realizado e abre as ações (editar, excluir, estornar) de cada uma.
void _showMatchedTransactionsSheet(
  BuildContext context,
  WidgetRef ref,
  PlannedEntry entry,
) {
  final txs = [...entry.matchedTransactions]
    ..sort((a, b) => b.competenceDate.compareTo(a.competenceDate));
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              entry.description,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Lançamentos deste orçamento · toque para editar',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ),
          for (final tx in txs)
            ListTile(
              leading: Icon(
                tx.status == 'paid'
                    ? Icons.check_circle_outline
                    : Icons.schedule_outlined,
                color: tx.status == 'paid'
                    ? context.hopeColors.income
                    : Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
              title: Text(tx.description),
              subtitle: Text(
                '${formatDate(tx.competenceDate)} · '
                '${tx.status == 'paid' ? 'pago' : 'previsto'}',
              ),
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

Color _saldoColor(BuildContext context, double saldo) {
  // Quitado, a realizar, excedeu.
  if (saldo.abs() < 0.005) return Theme.of(context).colorScheme.primary;
  return saldo > 0 ? context.hopeColors.warning : context.hopeColors.expense;
}

/// Junta categoria e subcategoria em "Moradia / Aluguel"; devolve só a parte
/// existente quando a outra falta.
String? _categoryLabel(String? category, String? subcategory) {
  if (category == null || category.isEmpty) return subcategory;
  if (subcategory == null || subcategory.isEmpty) return category;
  return '$category / $subcategory';
}

/// "2026-07-08" → "08/07".
String _shortDate(String isoDate) => isoDate.length < 10
    ? isoDate
    : '${isoDate.substring(8, 10)}/${isoDate.substring(5, 7)}';

/// Totais do modo extrato: o que de fato entrou e saiu no período.
/// Com um cartão selecionado, vira Compras × Estornos × Total da fatura.
class _StatementTotals extends StatelessWidget {
  const _StatementTotals({required this.txs, required this.cardView});

  final List<LocalTransaction> txs;
  final bool cardView;

  @override
  Widget build(BuildContext context) {
    double inflow = 0, outflow = 0;
    for (final t in txs) {
      final v = t.amount ?? t.amountPlanned ?? 0;
      if (t.type == 'income') {
        inflow += v;
      } else {
        outflow += v;
      }
    }
    final net = inflow - outflow;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: cardView
                  ? [
                      _MetricColumn(
                        label: 'Compras',
                        value: outflow,
                        color: context.hopeColors.expense,
                        align: CrossAxisAlignment.start,
                      ),
                      _MetricColumn(
                        label: 'Estornos',
                        value: inflow,
                        color: context.hopeColors.income,
                        align: CrossAxisAlignment.center,
                      ),
                      _MetricColumn(
                        label: 'Total no mês',
                        value: outflow - inflow,
                        align: CrossAxisAlignment.end,
                      ),
                    ]
                  : [
                      _MetricColumn(
                        label: 'Entradas',
                        value: inflow,
                        color: context.hopeColors.income,
                        align: CrossAxisAlignment.start,
                      ),
                      _MetricColumn(
                        label: 'Saídas',
                        value: outflow,
                        color: context.hopeColors.expense,
                        align: CrossAxisAlignment.center,
                      ),
                      _MetricColumn(
                        label: 'Resultado',
                        value: net,
                        color: net < -0.005 ? context.hopeColors.expense : context.hopeColors.income,
                        align: CrossAxisAlignment.end,
                      ),
                    ],
            ),
            const SizedBox(height: 8),
            Text(
              cardView
                  ? 'Compras e estornos já efetivados no cartão — confira '
                        'com a fatura. Previsões futuras ficam no modo '
                        'Previsto.'
                  : 'Somente valores efetivados — confira com o extrato da '
                        'conta.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Totais do modo previsto: separa o que já aconteceu do que ainda está por
/// vir e mostra a projeção do mês (líquido: receitas − despesas).
class _MixedTotals extends StatelessWidget {
  const _MixedTotals({required this.txs});

  final List<LocalTransaction> txs;

  @override
  Widget build(BuildContext context) {
    double realized = 0, pending = 0;
    for (final t in txs) {
      if (t.status == 'canceled') continue;
      // Pagamento de fatura não soma: as compras do cartão já contam.
      if (FinanceRepository.isInvoiceSettlement(t)) continue;
      final sign = t.type == 'income' ? 1 : -1;
      if (t.status == 'paid') {
        realized += sign * (t.amount ?? t.amountPlanned ?? 0);
      } else {
        pending += sign * (t.amountPlanned ?? t.amount ?? 0);
      }
    }
    final projected = realized + pending;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MetricColumn(
                  label: 'Realizado',
                  value: realized,
                  color: realized < -0.005 ? context.hopeColors.expense : context.hopeColors.income,
                  align: CrossAxisAlignment.start,
                ),
                _MetricColumn(
                  label: 'A realizar',
                  value: pending,
                  align: CrossAxisAlignment.center,
                ),
                _MetricColumn(
                  label: 'Projeção do mês',
                  value: projected,
                  color: projected < -0.005 ? context.hopeColors.expense : context.hopeColors.income,
                  align: CrossAxisAlignment.end,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Valores esmaecidos são previstos (ainda não aconteceram). '
              'Realizado + a realizar = projeção. Pagamentos de fatura não '
              'somam — as compras já contam.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formas pesquisáveis de um valor monetário, para permitir a busca por valor
/// em diferentes formatos: "1234.56", "1234,56" e "r$ 1.234,56".
String _valueSearchTokens(num value) {
  final fixed = value.toStringAsFixed(2);
  return '$fixed ${fixed.replaceAll('.', ',')} ${formatMoney(value).toLowerCase()}';
}

/// Data em que o lançamento "aconteceu" para fins de extrato: a compra, no
/// cartão; o pagamento, na conta.
String _statementDate(LocalTransaction t, {required bool cardView}) =>
    cardView ? t.competenceDate : (t.paymentDate ?? t.competenceDate);

/// Predicado de filtragem da lista de lançamentos (mês, tipo, conta/cartão e
/// busca), compartilhado entre a lista exibida e a exportação para garantir que
/// o arquivo reflita exatamente o que está na tela.
///
/// No modo extrato ([statement]) só entram lançamentos efetivados:
/// - com um cartão selecionado, as compras/estornos já ocorridos (a fatura,
///   de forma analítica), excluindo a liquidação (que é o débito na conta,
///   não uma compra) e as previsões com data futura — parcelas de compras
///   reais entram mesmo com competência futura, pois já estão na fatura;
/// - caso contrário, movimentações pagas de conta — o espelho do extrato
///   bancário, incluindo os pagamentos de fatura.
bool _txMatches(
  LocalTransaction t, {
  required String monthKey,
  required String filter,
  required _SourceFilter? accountFilter,
  required String search,
  required Map<String, String> categoryNames,
  Map<String, String> subcategoryNames = const {},
  bool statement = false,
}) {
  if (statement) {
    if (t.status == 'canceled') return false;
    final cardView = accountFilter?.kind == _SourceKind.card;
    if (cardView) {
      if (t.cardId != accountFilter!.id) return false;
      if (FinanceRepository.isInvoiceSettlement(t)) return false;
      final isInstallment = t.installmentTotal != null;
      if (!isInstallment && t.competenceDate.compareTo(todayIso()) > 0) {
        return false; // previsão futura no cartão: ainda não é fatura
      }
    } else {
      if (t.status != 'paid' || t.accountId == null) return false;
      if (accountFilter != null && t.accountId != accountFilter.id) {
        return false;
      }
    }
    if (!_statementDate(t, cardView: cardView).startsWith(monthKey)) {
      return false;
    }
  } else {
    if (!t.competenceDate.startsWith(monthKey)) return false;
    if (accountFilter != null) {
      final matchesSource = switch (accountFilter.kind) {
        _SourceKind.account => t.accountId == accountFilter.id,
        _SourceKind.card => t.cardId == accountFilter.id,
      };
      if (!matchesSource) return false;
    }
  }
  final matchesType = switch (filter) {
    'income' || 'planned_income' => t.type == 'income',
    'expense' || 'planned_expense' => t.type == 'expense',
    _ => true,
  };
  if (!matchesType) return false;
  if (search.isNotEmpty) {
    final categoryName = (categoryNames[t.categoryId] ?? '').toLowerCase();
    final subcategoryName = (subcategoryNames[t.subcategoryId] ?? '')
        .toLowerCase();
    final value = t.amount ?? t.amountPlanned ?? 0;
    final haystack =
        '${t.description.toLowerCase()} $categoryName $subcategoryName '
        '${_valueSearchTokens(value)}';
    if (!haystack.contains(search)) return false;
  }
  return true;
}

/// Lista do filtro "previstos": itens de orçamento do mês (com o realizado das
/// transações que casam) somados às transações previstas avulsas (ex.: cartão).
class _PlannedList extends ConsumerWidget {
  const _PlannedList({
    required this.monthKey,
    required this.incomeView,
    required this.accountFilter,
    required this.search,
    required this.categoryNames,
    required this.subcategoryNames,
    required this.cardNames,
    required this.accountNames,
  });

  final String monthKey;
  final bool incomeView;
  final _SourceFilter? accountFilter;
  final String search;
  final Map<String, String> categoryNames;
  final Map<String, String> subcategoryNames;
  final Map<String, String> cardNames;
  final Map<String, String> accountNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(plannedEntriesProvider(monthKey));
    return async.when(
      loading: () => const HopeSkeleton(rows: 6),
      error: (error, _) => HopeErrorState.load(
        error,
        what: 'os lançamentos previstos',
        onRetry: () => ref.invalidate(plannedEntriesProvider(monthKey)),
      ),
      data: (all) {
        final type = incomeView ? 'income' : 'expense';
        final entries = all.where((e) {
          if (e.type != type) return false;
          if (accountFilter != null) {
            final matches = switch (accountFilter!.kind) {
              _SourceKind.account => e.accountId == accountFilter!.id,
              _SourceKind.card => e.cardId == accountFilter!.id,
            };
            if (!matches) return false;
          }
          if (search.isNotEmpty) {
            final categoryName = (categoryNames[e.categoryId] ?? '')
                .toLowerCase();
            final subcategoryName = (subcategoryNames[e.subcategoryId] ?? '')
                .toLowerCase();
            final haystack =
                '${e.description.toLowerCase()} $categoryName $subcategoryName '
                '${_valueSearchTokens(e.planned)} ${_valueSearchTokens(e.realized)}';
            if (!haystack.contains(search)) return false;
          }
          return true;
        }).toList();

        if (entries.isEmpty) {
          return _EmptyPlaceholder(
            icon: Icons.event_note_outlined,
            title: incomeView
                ? 'Nenhuma receita prevista'
                : 'Nenhuma despesa prevista',
            subtitle:
                'Lance itens no orçamento do mês ou agende lançamentos com vencimento.',
          );
        }

        // Orçamentos primeiro; depois dívidas; por fim, avulsos por vencimento.
        final budget = entries.where((e) => e.isBudget).toList()
          ..sort((a, b) => a.description.compareTo(b.description));
        final debts = entries.where((e) => e.isDebt).toList()
          ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
        final standalone =
            entries.where((e) => !e.isBudget && !e.isDebt).toList()
              ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));

        String subtitleFor(PlannedEntry e) {
          if (e.isBudget) {
            final account = accountNames[e.accountId];
            return [
              if (account != null && account.isNotEmpty) account,
              'orçamento',
            ].join(' · ');
          }
          if (e.isDebt) {
            final account = accountNames[e.accountId];
            return [
              if (account != null && account.isNotEmpty) account,
              if (e.dueDate != null) 'vence ${formatDate(e.dueDate)}',
              'dívida',
            ].join(' · ');
          }
          final statusLabel = switch (e.status) {
            'paid' => incomeView ? 'recebido' : 'pago',
            'overdue' => 'atrasado',
            _ => 'previsto',
          };
          final card = cardNames[e.cardId];
          final category = _categoryLabel(
            categoryNames[e.categoryId],
            subcategoryNames[e.subcategoryId],
          );
          return [
            if (category != null && category.isNotEmpty) category,
            if (card != null) '💳 $card',
            statusLabel,
          ].join(' · ');
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _PlannedTotals(entries: entries, incomeView: incomeView),
            if (budget.isNotEmpty) ...[
              const _PlannedSubheader(label: 'Orçamento do mês'),
              for (final e in budget)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: _PlannedEntryTile(entry: e, subtitle: subtitleFor(e)),
                ),
            ],
            if (debts.isNotEmpty) ...[
              const _PlannedSubheader(label: 'Dívidas e financiamentos'),
              for (final e in debts)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: _PlannedEntryTile(entry: e, subtitle: subtitleFor(e)),
                ),
            ],
            if (standalone.isNotEmpty) ...[
              if (budget.isNotEmpty || debts.isNotEmpty)
                const _PlannedSubheader(label: 'Outros previstos'),
              for (final e in standalone)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: _PlannedEntryTile(entry: e, subtitle: subtitleFor(e)),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _PlannedSubheader extends StatelessWidget {
  const _PlannedSubheader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Cabeçalho com os totais Previsto × Realizado × A receber/pagar da lista de
/// previstos.
class _PlannedTotals extends StatelessWidget {
  const _PlannedTotals({required this.entries, required this.incomeView});

  final List<PlannedEntry> entries;
  final bool incomeView;

  @override
  Widget build(BuildContext context) {
    final previsto = entries.fold<double>(0, (s, e) => s + e.planned);
    final realizado = entries.fold<double>(0, (s, e) => s + e.realized);
    final saldo = entries.fold<double>(0, (s, e) => s + e.saldo);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MetricColumn(
                  label: 'Previsto',
                  value: previsto,
                  align: CrossAxisAlignment.start,
                ),
                _MetricColumn(
                  label: 'Realizado',
                  value: realizado,
                  color: incomeView ? context.hopeColors.income : context.hopeColors.expense,
                  align: CrossAxisAlignment.center,
                ),
                _MetricColumn(
                  label: incomeView ? 'A receber' : 'A pagar',
                  value: saldo,
                  color: _saldoColor(context, saldo),
                  align: CrossAxisAlignment.end,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              incomeView
                  ? 'Previsto é o combinado no mês; realizado, o que já '
                        'entrou; a receber, o que falta.'
                  : 'Previsto é o combinado no mês; realizado, o que já foi '
                        'pago; a pagar, o que falta.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha de previsto (orçamento, dívida ou transação avulsa) com as colunas
/// Previsto/Realizado/Saldo. Dívidas abrem o fluxo de baixa; orçamento é
/// apenas informativo.
class _PlannedEntryTile extends ConsumerWidget {
  const _PlannedEntryTile({required this.entry, required this.subtitle});

  final PlannedEntry entry;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = entry.type == 'income';
    final color = isIncome ? context.hopeColors.income : context.hopeColors.expense;
    final tx = entry.transaction;
    final VoidCallback? onTap = entry.isDebt
        ? () {
            _showDebtPaymentSheet(context, entry);
          }
        : tx != null
        ? () => showTransactionActions(context, ref, tx)
        // Linha de orçamento: abre os lançamentos que compõem o realizado,
        // permitindo conferir e editar cada um.
        : entry.matchedTransactions.isNotEmpty
        ? () => _showMatchedTransactionsSheet(context, ref, entry)
        : null;
    final icon = entry.isDebt
        ? Icons.account_balance_outlined
        : entry.isBudget
        ? Icons.savings_outlined
        : (isIncome
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          subtitle,
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
                ],
              ),
              const Divider(height: 18),
              Row(
                children: [
                  _MetricColumn(
                    label: 'Previsto',
                    value: entry.planned,
                    align: CrossAxisAlignment.start,
                  ),
                  _MetricColumn(
                    label: 'Realizado',
                    value: entry.realized,
                    color: color,
                    align: CrossAxisAlignment.center,
                  ),
                  _MetricColumn(
                    label: isIncome ? 'A receber' : 'A pagar',
                    value: entry.saldo,
                    color: _saldoColor(context, entry.saldo),
                    align: CrossAxisAlignment.end,
                  ),
                ],
              ),
              if (entry.planned > 0.005) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ((entry.settled ?? entry.realized) / entry.planned)
                        .clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    color: entry.saldo < -0.005 ? context.hopeColors.expense : color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder centralizado para estados vazios da lista.
class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(icon: icon, title: title, subtitle: subtitle);
  }
}

/// Uma coluna rotulada (Previsto/Realizado/Saldo) dentro de uma Row de 3.
class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    required this.align,
    this.color,
  });

  final String label;
  final double value;
  final CrossAxisAlignment align;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textAlign = switch (align) {
      CrossAxisAlignment.end => TextAlign.right,
      CrossAxisAlignment.center => TextAlign.center,
      _ => TextAlign.left,
    };
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            label,
            textAlign: textAlign,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatMoney(value),
            textAlign: textAlign,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de busca por texto que alimenta [_searchProvider].
class _SearchField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(_searchProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar por descrição, categoria ou valor',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Limpar',
                onPressed: () {
                  _controller.clear();
                  ref.read(_searchProvider.notifier).state = '';
                  setState(() {});
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (v) {
        ref.read(_searchProvider.notifier).state = v;
        setState(() {}); // atualiza o botão de limpar
      },
    );
  }
}
