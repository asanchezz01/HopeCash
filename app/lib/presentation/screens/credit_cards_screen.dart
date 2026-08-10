import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../components/hope_components.dart';

/// Valor em aberto (não pago) por cartão, reativo às transações.
final _openAmountsProvider = FutureProvider<Map<String, double>>((ref) async {
  final cards = ref.watch(creditCardsProvider).valueOrNull ?? [];
  ref.watch(transactionsProvider);
  final repo = ref.watch(financeRepositoryProvider);
  return {for (final c in cards) c.id: await repo.cardOpenAmount(c.id)};
});

const _cardColors = [
  AppTheme.deepBlue,
  AppTheme.hopeGreen,
  AppTheme.skyBlue,
  AppTheme.purple,
  AppTheme.warning,
  AppTheme.danger,
];

void showCreditCardSheet(
  BuildContext context,
  WidgetRef ref, {
  LocalCreditCard? card,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CreditCardForm(card: card),
  );
}

class CreditCardsScreen extends ConsumerWidget {
  const CreditCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(creditCardsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cartões de crédito',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          AppBarPrimaryAction(
            tooltip: 'Novo cartão',
            label: 'Cartão',
            icon: Icons.add_card_outlined,
            onPressed: () => showCreditCardSheet(context, ref),
          ),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const HopeSkeleton(rows: 4),
        error: (error, _) => HopeErrorState.load(
          error,
          what: 'seus cartões',
          onRetry: () => ref.invalidate(creditCardsProvider),
        ),
        data: (cards) {
          if (cards.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.credit_card_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum cartão cadastrado',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cadastre seus cartões para organizar limites, faturas e vencimentos.',
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

          final openAmounts = ref.watch(_openAmountsProvider).valueOrNull ?? {};
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              context.pagePadding,
              HopeSpacing.xs,
              context.pagePadding,
              // Espaço para o botão flutuante de lançamento da casca.
              120,
            ),
            itemBuilder: (context, index) {
              final card = cards[index];
              return _CreditCardTile(
                card: card,
                openAmount: openAmounts[card.id] ?? 0,
                onTap: () => context.push('/more/credit-cards/${card.id}'),
                onEdit: () => showCreditCardSheet(context, ref, card: card),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemCount: cards.length,
          );
        },
      ),
    );
  }
}

class _CreditCardTile extends StatelessWidget {
  const _CreditCardTile({
    required this.card,
    required this.openAmount,
    required this.onTap,
    required this.onEdit,
  });

  final LocalCreditCard card;
  final double openAmount;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(card.color) ?? AppTheme.deepBlue;
    // `cardOpenAmount` soma tudo que ainda não foi pago no cartão (incluindo
    // parcelas de meses à frente), já abatendo estornos — é exatamente o que
    // consome o limite hoje.
    final available = card.limitAmount - openAmount;
    final overLimit = available < 0;
    final usedFraction = card.limitAmount > 0
        ? (openAmount / card.limitAmount).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, AppTheme.deepBlue, 0.45)!],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.credit_card_outlined, color: Colors.white),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Editar cartão',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: onEdit,
                    ),
                    if (!card.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'Inativo',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  card.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (card.issuer != null && card.issuer!.isNotEmpty)
                  Text(
                    card.issuer!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.76),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CardInfo(
                        label: 'Limite',
                        value: formatMoney(card.limitAmount),
                      ),
                    ),
                    Expanded(
                      child: _CardInfo(
                        label: 'Utilizado',
                        value: formatMoney(openAmount),
                      ),
                    ),
                    Expanded(
                      child: _CardInfo(
                        label: 'Disponível',
                        value: formatMoney(available),
                        // Estourou o limite: o número negativo precisa saltar,
                        // senão passa por "só mais um valor".
                        valueColor: overLimit ? const Color(0xFFFF9E9E) : null,
                      ),
                    ),
                  ],
                ),
                if (card.limitAmount > 0) ...[
                  const SizedBox(height: 12),
                  _LimitBar(fraction: usedFraction, overLimit: overLimit),
                ],
                const SizedBox(height: 12),
                Text(
                  'Fechamento dia ${card.closingDay} · '
                  'Vencimento dia ${card.dueDay}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Antes esta faixa repetia o valor em aberto; agora ele é o
                  // "Utilizado" lá em cima, então aqui sobra só a ação — sem
                  // mostrar o mesmo número duas vezes com nomes diferentes.
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: HopeSpacing.xs),
                      Expanded(
                        child: Text(
                          'Ver fatura e lançamentos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  const _CardInfo({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Barra de consumo do limite. Vive sobre o gradiente escuro do cartão, então
/// a trilha e o preenchimento são tons de branco — exceto quando o limite
/// estourou, aí vale o vermelho de alerta.
class _LimitBar extends StatelessWidget {
  const _LimitBar({required this.fraction, required this.overLimit});

  final double fraction;
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction * 100).round();
    return Semantics(
      label: overLimit
          ? 'Limite estourado'
          : 'Limite utilizado: $percent por cento',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 6,
          backgroundColor: Colors.white.withValues(alpha: 0.18),
          valueColor: AlwaysStoppedAnimation(
            overLimit ? const Color(0xFFFF9E9E) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CreditCardForm extends ConsumerStatefulWidget {
  const _CreditCardForm({this.card});

  final LocalCreditCard? card;

  @override
  ConsumerState<_CreditCardForm> createState() => _CreditCardFormState();
}

class _CreditCardFormState extends ConsumerState<_CreditCardForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _limit = TextEditingController();
  final _closingDay = TextEditingController();
  final _dueDay = TextEditingController();
  String? _color;
  String? _defaultAccountId;
  bool _isActive = true;
  bool _saving = false;

  bool get _editing => widget.card != null;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _name.text = card?.name ?? '';
    _issuer.text = card?.issuer ?? '';
    _limit.text = card == null
        ? ''
        : card.limitAmount.toStringAsFixed(2).replaceAll('.', ',');
    _closingDay.text = '${card?.closingDay ?? 1}';
    _dueDay.text = '${card?.dueDay ?? 10}';
    _color = card?.color ?? _hex(_cardColors.first);
    _defaultAccountId = card?.defaultAccountId;
    _isActive = card?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _limit.dispose();
    _closingDay.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(financeRepositoryProvider)
        .upsertCreditCard(
          id: widget.card?.id,
          name: _name.text.trim(),
          issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
          limitAmount: parseMoney(_limit.text) ?? 0,
          closingDay: int.parse(_closingDay.text),
          dueDay: int.parse(_dueDay.text),
          color: _color,
          icon: 'credit_card',
          isActive: _isActive,
          defaultAccountId: _defaultAccountId,
          currentVersion: widget.card?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Cartão atualizado' : 'Cartão cadastrado'),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final card = widget.card;
    if (card == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir cartão?'),
        content: Text('O cartão "${card.name}" será removido da sua lista.'),
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
    await ref.read(financeRepositoryProvider).deleteCreditCard(card);
    ref.read(syncServiceProvider).syncNow();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cartão excluído')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    return PremiumFormSheet(
      title: _editing ? 'Editar cartão' : 'Novo cartão',
      subtitle: 'Defina limite, fechamento, vencimento e conta de pagamento.',
      icon: Icons.credit_card_outlined,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Identificação',
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome do cartão',
                prefixIcon: Icon(Icons.credit_card_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            TextFormField(
              controller: _issuer,
              decoration: const InputDecoration(
                labelText: 'Emissor ou banco',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            DropdownButtonFormField<String>(
              initialValue: _defaultAccountId,
              decoration: const InputDecoration(
                labelText: 'Conta para pagamento',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Nenhuma')),
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _defaultAccountId = value),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Fatura',
          subtitle: 'Esses campos calculam vencimentos e limite disponível.',
          children: [
            TextFormField(
              controller: _limit,
              decoration: const InputDecoration(
                labelText: 'Limite',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              validator: (v) {
                final parsed = v == null ? null : parseMoney(v);
                return (parsed == null || parsed < 0)
                    ? 'Informe um limite válido'
                    : null;
              },
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _closingDay,
                    decoration: const InputDecoration(
                      labelText: 'Fecha dia',
                      prefixIcon: Icon(Icons.event_available_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    validator: _dayValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _dueDay,
                    decoration: const InputDecoration(
                      labelText: 'Vence dia',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    validator: _dayValidator,
                  ),
                ),
              ],
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Aparência e status',
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _cardColors)
                  _ColorSwatch(
                    color: color,
                    selected: _color == _hex(color),
                    onTap: () => setState(() => _color = _hex(color)),
                  ),
              ],
            ),
            FormSwitchRow(
              icon: Icons.visibility_outlined,
              title: 'Cartão ativo',
              subtitle: 'Cartões inativos ficam fora dos lançamentos rápidos.',
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
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
        icon: _saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: const Text('Salvar cartão'),
      ),
      destructiveAction: _editing
          ? TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: context.hopeColors.expense),
              label: const Text('Excluir cartão'),
              style: TextButton.styleFrom(foregroundColor: context.hopeColors.expense),
            )
          : null,
    );
  }

  String? _dayValidator(String? value) {
    final day = int.tryParse(value ?? '');
    if (day == null || day < 1 || day > 31) return 'Dia 1 a 31';
    return null;
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Selecionar cor',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

Color? _parseColor(String? value) {
  if (value == null || !value.startsWith('#')) return null;
  final parsed = int.tryParse(value.substring(1), radix: 16);
  if (parsed == null) return null;
  return Color(0xFF000000 | parsed);
}

String _hex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
