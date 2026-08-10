import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/utils/finance_calc.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/finance_repository.dart';
import '../components/hope_components.dart';

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

/// Despesas de um cartão, reativas ao banco local.
final _cardTransactionsProvider =
    StreamProvider.family<List<LocalTransaction>, String>(
      (ref, cardId) =>
          ref.watch(financeRepositoryProvider).watchCardTransactions(cardId),
    );

/// Mês de vencimento selecionado por cartão (YYYY-MM).
final _selectedInvoiceMonthProvider = StateProvider.family<String?, String>(
  (ref, cardId) => null,
);

String _shiftMonth(String month, int delta) {
  final d = DateTime.parse('$month-01');
  final s = DateTime(d.year, d.month + delta, 1);
  return '${s.year}-${s.month.toString().padLeft(2, '0')}';
}

String _monthLabel(String month) {
  final d = DateTime.parse('$month-01');
  return '${_monthNames[d.month - 1]} ${d.year}';
}

String _clampDay(String month, int day) {
  final d = DateTime.parse('$month-01');
  final last = DateTime(d.year, d.month + 1, 0).day;
  final dd = day > last ? last : day;
  return '$month-${dd.toString().padLeft(2, '0')}';
}

/// Valor com sinal na fatura: estorno (receita) é crédito e abate o total.
double _cardSigned(LocalTransaction t) {
  final v = t.amountPlanned ?? t.amount ?? 0;
  return t.type == 'income' ? -v : v;
}

class CardInvoicesScreen extends ConsumerWidget {
  const CardInvoicesScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(creditCardsProvider).valueOrNull ?? [];
    final card = cards.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fatura')),
        body: const Center(child: Text('Cartão não encontrado')),
      );
    }

    final allTxs =
        ref.watch(_cardTransactionsProvider(cardId)).valueOrNull ?? [];
    // Fatura corrente: aquela que receberia uma compra feita hoje.
    final currentMonth = cardDueDate(
      purchaseDate: todayIso(),
      closingDay: card.closingDay,
      dueDay: card.dueDay,
    ).substring(0, 7);
    final month =
        ref.watch(_selectedInvoiceMonthProvider(cardId)) ?? currentMonth;

    final invoiceTxs = allTxs
        .where((t) => (t.dueDate ?? '').startsWith(month))
        .toList();
    final total = invoiceTxs.fold<double>(0, (s, t) => s + _cardSigned(t));
    final openTotal = invoiceTxs
        .where((t) => t.status == 'planned' || t.status == 'overdue')
        .fold<double>(0, (s, t) => s + _cardSigned(t));
    final usedLimit = allTxs
        .where((t) => t.status == 'planned' || t.status == 'overdue')
        .where((t) => !FinanceRepository.isInvoiceSettlement(t))
        .fold<double>(0, (s, t) => s + _cardSigned(t));

    // Datas da fatura selecionada.
    final dueDate = _clampDay(month, card.dueDay);
    final closingMonth = card.dueDay > card.closingDay
        ? month
        : _shiftMonth(month, -1);
    final closingDate = _clampDay(closingMonth, card.closingDay);

    final today = todayIso();
    final String status;
    if (invoiceTxs.isNotEmpty && openTotal == 0) {
      status = 'Paga';
    } else if (openTotal > 0 && today.compareTo(dueDate) > 0) {
      status = 'Vencida';
    } else if (today.compareTo(closingDate) > 0) {
      status = 'Fechada';
    } else {
      status = 'Aberta';
    }
    final statusColor = switch (status) {
      'Paga' => context.hopeColors.success,
      'Vencida' => context.hopeColors.expense,
      'Fechada' => context.hopeColors.warning,
      _ => context.hopeColors.investment,
    };

    final categories = {
      for (final c
          in ref.watch(categoriesProvider).valueOrNull ?? <LocalCategory>[])
        c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(card.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Importar e conciliar fatura',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => context.push(
              '/more/import?cardId=${Uri.encodeQueryComponent(cardId)}'
              '&referenceMonth=${Uri.encodeQueryComponent('$month-01')}'
              '&dueDate=${Uri.encodeQueryComponent(dueDate)}',
            ),
          ),
          if (openTotal > 0)
            AppBarPrimaryAction(
              label: 'Pagar',
              icon: Icons.payments_outlined,
              tooltip: 'Pagar fatura (${formatMoney(openTotal)})',
              onPressed: () =>
                  _payInvoice(context, ref, card, invoiceTxs, openTotal),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () =>
                    ref
                        .read(_selectedInvoiceMonthProvider(cardId).notifier)
                        .state = _shiftMonth(
                      month,
                      -1,
                    ),
              ),
              Expanded(
                child: Text(
                  'Fatura de ${_monthLabel(month)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    ref
                        .read(_selectedInvoiceMonthProvider(cardId).notifier)
                        .state = _shiftMonth(
                      month,
                      1,
                    ),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          status,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatMoney(total),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCell(
                          label: 'Fechamento',
                          value: formatDate(closingDate),
                        ),
                      ),
                      Expanded(
                        child: _InfoCell(
                          label: 'Vencimento',
                          value: formatDate(dueDate),
                        ),
                      ),
                      Expanded(
                        child: _InfoCell(
                          label: 'Em aberto',
                          value: formatMoney(openTotal),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: clampProgress(usedLimit, card.limitAmount),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: usedLimit > card.limitAmount * 0.8
                        ? context.hopeColors.expense
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Limite usado: ${formatMoney(usedLimit)} de ${formatMoney(card.limitAmount)} '
                    '(disponível ${formatMoney(card.limitAmount - usedLimit)})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (invoiceTxs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nenhuma despesa nesta fatura.\nLance uma compra no cartão pelo botão + do início.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Text(
              'Despesas da fatura',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final t in invoiceTxs)
                    _InvoiceLineTile(
                      t: t,
                      categoryName: categories[t.categoryId],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _payInvoice(
    BuildContext context,
    WidgetRef ref,
    LocalCreditCard card,
    List<LocalTransaction> invoiceTxs,
    double openTotal,
  ) async {
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre uma conta para pagar a fatura')),
      );
      return;
    }
    String accountId = card.defaultAccountId ?? accounts.first.id;
    if (!accounts.any((a) => a.id == accountId)) accountId = accounts.first.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pagar fatura'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Será lançado um débito de ${formatMoney(openTotal)} na conta '
                'escolhida e as despesas da fatura serão marcadas como pagas.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(
                  labelText: 'Debitar da conta',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => accountId = v ?? accountId),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar pagamento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final paid = await ref
        .read(financeRepositoryProvider)
        .payCardInvoice(
          card: card,
          transactions: invoiceTxs,
          accountId: accountId,
          paymentDate: todayIso(),
        );
    ref.read(syncServiceProvider).syncNow();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fatura paga: ${formatMoney(paid)}')),
      );
    }
  }
}

/// Linha de um lançamento na fatura. Estornos (receita) aparecem como crédito,
/// em verde e com sinal negativo, pois abatem o valor da fatura.
class _InvoiceLineTile extends StatelessWidget {
  const _InvoiceLineTile({required this.t, this.categoryName});

  final LocalTransaction t;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final isCredit = t.type == 'income';
    final value = (t.amountPlanned ?? t.amount ?? 0).abs();
    return ListTile(
      dense: true,
      leading: Icon(
        isCredit
            ? Icons.replay_outlined
            : (FinanceRepository.isInvoiceSettlement(t)
                  ? Icons.receipt_long_outlined
                  : Icons.shopping_bag_outlined),
        color: isCredit
            ? context.hopeColors.income
            : (t.status == 'paid' ? context.hopeColors.success : context.hopeColors.expense),
        size: 20,
      ),
      title: Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          formatDate(t.competenceDate),
          ?categoryName,
          if (isCredit) 'estorno',
          if (t.installmentTotal != null)
            'parcela ${t.installmentNumber}/${t.installmentTotal}',
          if (t.status == 'paid') 'paga',
        ].join(' · '),
      ),
      trailing: Text(
        '${isCredit ? '− ' : ''}${formatMoney(value)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCredit ? context.hopeColors.income : null,
        ),
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});

  final String label;
  final String value;

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
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
