import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/local/database.dart';
import '../components/hope_components.dart';
import 'credit_cards_screen.dart';
import '../widgets/icon_picker.dart';

const _accountTypes = {
  'checking': 'Conta corrente',
  'savings': 'Poupança',
  'investment': 'Investimento',
  'wallet': 'Carteira digital',
  'cash': 'Dinheiro',
  'digital': 'Conta digital',
};

/// Paleta de cores disponíveis para a conta (hex com #).
const _accountColors = [
  '#16C784', // hopeGreen
  '#06B6D4', // skyBlue
  '#885CF6', // purple
  '#F59E0B', // warning
  '#EF4444', // danger
  '#1B263B', // primaryBlue
];

/// Ícones disponíveis para a conta, identificados pela chave salva em
/// [LocalAccount.icon].
const _accountIcons = <String, IconData>{
  'account_balance': Icons.account_balance_outlined,
  'savings': Icons.savings_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'credit_card': Icons.credit_card_outlined,
  'payments': Icons.payments_outlined,
  'money': Icons.attach_money,
  'currency_exchange': Icons.currency_exchange,
  'trending_up': Icons.trending_up,
  'card_giftcard': Icons.card_giftcard,
  'business': Icons.business_outlined,
  'pix': Icons.pix_outlined,
  'qr_code': Icons.qr_code_2_outlined,
  'phone': Icons.smartphone_outlined,
  'security': Icons.security_outlined,
  'home': Icons.home_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'work': Icons.work_outline,
  'diamond': Icons.diamond_outlined,
  'euro': Icons.euro_outlined,
  'monetization': Icons.monetization_on_outlined,
};

/// Ícone da conta a partir da chave salva; usa um padrão quando ausente.
IconData _accountIconData(String? key) =>
    _accountIcons[key] ?? Icons.account_balance_outlined;

/// Saldo por conta calculado localmente.
final _balancesProvider = FutureProvider<Map<String, double>>((ref) async {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
  ref.watch(transactionsProvider); // recalcula quando transações mudam
  final repo = ref.watch(financeRepositoryProvider);
  return {for (final a in accounts) a.id: await repo.accountBalance(a)};
});

final _cardOpenAmountsProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  final cards = ref.watch(creditCardsProvider).valueOrNull ?? [];
  ref.watch(transactionsProvider);
  final repo = ref.watch(financeRepositoryProvider);
  return {
    for (final card in cards) card.id: await repo.cardOpenAmount(card.id),
  };
});

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final cards = ref.watch(creditCardsProvider).valueOrNull ?? [];
    final balances = ref.watch(_balancesProvider).valueOrNull ?? {};
    final openAmounts = ref.watch(_cardOpenAmountsProvider).valueOrNull ?? {};
    final hasFinancialSources = accounts.isNotEmpty || cards.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas'),
        actions: [
          AppBarPrimaryAction(
            label: 'Adicionar',
            icon: Icons.add_rounded,
            tooltip: 'Adicionar conta ou cartão',
            onPressed: () => _showCreateSourceSheet(context, ref),
          ),
        ],
      ),
      body: !hasFinancialSources
          ? PremiumEmptyState(
              icon: Icons.account_balance_outlined,
              title: 'Monte sua visão financeira',
              subtitle:
                  'Cadastre contas e cartões para o HopeCash consolidar '
                  'saldo, limites e faturas.',
              action: FilledButton.icon(
                onPressed: () => _showCreateSourceSheet(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar conta ou cartão'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, kHopeMinTapTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: HopeSpacing.lg,
                  ),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                HopeSpacing.xs,
                context.pagePadding,
                // Espaço para o botão flutuante de lançamento.
                120,
              ),
              children: [
                _SourceSectionHeader(title: 'Contas', count: accounts.length),
                if (accounts.isEmpty)
                  _SectionEmptyHint(
                    icon: Icons.account_balance_outlined,
                    title: 'Nenhuma conta cadastrada',
                    subtitle:
                        'Adicione contas, carteiras e investimentos para acompanhar saldos.',
                  )
                else
                  for (final account in accounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: HopeSpacing.sm),
                      child: _AccountSourceTile(
                        account: account,
                        balance: balances[account.id] ?? account.initialBalance,
                        color: _accountColor(account, context),
                        icon: _accountIconData(account.icon),
                        onViewTransactions: () => context.go(
                          '/transactions?sourceKind=account&sourceId=${account.id}',
                        ),
                        onEdit: () =>
                            _showAccountDialog(context, ref, account: account),
                      ),
                    ),
                const SizedBox(height: HopeSpacing.lg),
                _SourceSectionHeader(
                  title: 'Cartões de crédito',
                  count: cards.length,
                ),
                if (cards.isEmpty)
                  _SectionEmptyHint(
                    icon: Icons.credit_card_outlined,
                    title: 'Nenhum cartão cadastrado',
                    subtitle:
                        'Adicione cartões para acompanhar limite, fatura e vencimentos.',
                  )
                else
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: HopeSpacing.sm),
                      child: _CreditCardSourceTile(
                        card: card,
                        openAmount: openAmounts[card.id] ?? 0,
                        onViewTransactions: () => context.go(
                          '/transactions?sourceKind=card&sourceId=${card.id}',
                        ),
                        onEdit: () =>
                            showCreditCardSheet(context, ref, card: card),
                      ),
                    ),
              ],
            ),
    );
  }

  Color _accountColor(LocalAccount account, BuildContext context) {
    if (account.color != null && account.color!.startsWith('#')) {
      final hex = account.color!.substring(1).padLeft(8, 'F');
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(parsed | 0xFF000000);
    }
    return switch (account.type) {
      'investment' => context.hopeColors.card,
      'wallet' || 'digital' => context.hopeColors.investment,
      'cash' => context.hopeColors.warning,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  void _showAccountDialog(
    BuildContext context,
    WidgetRef ref, {
    LocalAccount? account,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AccountForm(account: account),
    );
  }

  void _showCreateSourceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          HopeSpacing.md,
          0,
          HopeSpacing.md,
          HopeSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'O que deseja adicionar?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: HopeSpacing.sm),
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Nova conta'),
              subtitle: const Text('Conta bancária, carteira ou dinheiro'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAccountDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_card_outlined),
              title: const Text('Novo cartão'),
              subtitle: const Text('Cartão de crédito e limite'),
              onTap: () {
                Navigator.pop(sheetContext);
                showCreditCardSheet(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({this.account});

  final LocalAccount? account;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _bank = TextEditingController();
  final _initial = TextEditingController();
  String _type = 'checking';
  String? _color;
  String? _icon;
  bool _includeInTotal = true;
  bool _isActive = true;
  bool _saving = false;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _name.text = account?.name ?? '';
    _bank.text = account?.bankName ?? '';
    _initial.text = account == null
        ? ''
        : account.initialBalance.toStringAsFixed(2).replaceAll('.', ',');
    _type = account?.type ?? 'checking';
    _color = account?.color;
    _icon = account?.icon;
    _includeInTotal = account?.includeInTotal ?? true;
    _isActive = account?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _bank.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(financeRepositoryProvider)
        .upsertAccount(
          id: widget.account?.id,
          name: _name.text.trim(),
          type: _type,
          initialBalance: parseMoney(_initial.text) ?? 0,
          bankName: _bank.text.trim().isEmpty ? null : _bank.text.trim(),
          color: _color,
          icon: _icon,
          includeInTotal: _includeInTotal,
          isActive: _isActive,
          currentVersion: widget.account?.version,
        );
    ref.read(syncServiceProvider).syncNow();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_editing ? 'Conta atualizada.' : 'Conta criada.')),
    );
  }

  Future<void> _delete() async {
    final account = widget.account;
    if (account == null) return;
    await _confirmDeleteAccount(context, ref, account);
  }

  @override
  Widget build(BuildContext context) {
    return PremiumFormSheet(
      title: _editing ? 'Editar conta' : 'Nova conta',
      subtitle:
          'Organize saldo, banco, ícone e regras de consolidação em um só lugar.',
      icon: Icons.account_balance_outlined,
      formKey: _formKey,
      fields: [
        PremiumFormSection(
          title: 'Identificação',
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome da conta',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o nome da conta'
                  : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final entry in _accountTypes.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => _type = value ?? 'checking'),
            ),
            TextFormField(
              controller: _bank,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Banco ou instituição',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            TextFormField(
              controller: _initial,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Saldo inicial',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.payments_outlined),
                helperText: 'Use o sinal - para saldo negativo',
              ),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Aparência',
          subtitle: 'Use cor e ícone para reconhecer a conta rapidamente.',
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in _accountColors)
                  _ColorSwatch(
                    hex: hex,
                    selected: _color == hex,
                    onTap: () => setState(() => _color = hex),
                  ),
              ],
            ),
            IconPickerGrid(
              icons: _accountIcons,
              selected: _icon,
              color: _colorFromHex(_color),
              onSelected: (key) => setState(() => _icon = key),
            ),
          ],
        ),
        PremiumFormSection(
          title: 'Comportamento',
          children: [
            FormSwitchRow(
              icon: Icons.functions_rounded,
              title: 'Incluir no saldo total',
              subtitle: 'Soma esta conta no saldo consolidado.',
              value: _includeInTotal,
              onChanged: (value) => setState(() => _includeInTotal = value),
            ),
            FormSwitchRow(
              icon: Icons.visibility_outlined,
              title: 'Conta ativa',
              subtitle: 'Contas inativas ficam ocultas nos lançamentos.',
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
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline),
        label: const Text('Salvar conta'),
      ),
      destructiveAction: _editing
          ? TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: context.hopeColors.expense),
              label: const Text('Excluir conta'),
              style: TextButton.styleFrom(foregroundColor: context.hopeColors.expense),
            )
          : null,
    );
  }
}

/// Confirma e executa a exclusão da conta, avisando sobre lançamentos
/// vinculados que serão preservados sem conta.
Future<void> _confirmDeleteAccount(
  BuildContext context,
  WidgetRef ref,
  LocalAccount account,
) async {
  final repo = ref.read(financeRepositoryProvider);
  final linked = await repo.accountTransactionCount(account.id);
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir conta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Deseja excluir a conta "${account.name}"?'),
          if (linked > 0) ...[
            const SizedBox(height: 12),
            Text(
              linked == 1
                  ? 'Há 1 lançamento vinculado a esta conta. Ele será mantido, mas ficará sem conta.'
                  : 'Há $linked lançamentos vinculados a esta conta. Eles serão mantidos, mas ficarão sem conta.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.hopeColors.expense),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  await repo.deleteAccount(account);
  ref.read(syncServiceProvider).syncNow();
  if (context.mounted) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Conta "${account.name}" excluída.')),
    );
  }
}

class _SourceSectionHeader extends StatelessWidget {
  const _SourceSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HopeSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          _KindBadge(
            label: '$count',
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SectionEmptyHint extends StatelessWidget {
  const _SectionEmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Row(
        children: [
          FinanceIconBadge(
            icon: icon,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: HopeSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _AccountSourceTile extends StatelessWidget {
  const _AccountSourceTile({
    required this.account,
    required this.balance,
    required this.color,
    required this.icon,
    required this.onViewTransactions,
    required this.onEdit,
  });

  final LocalAccount account;
  final double balance;
  final Color color;
  final IconData icon;
  final VoidCallback onViewTransactions;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        children: [
          Row(
            children: [
              FinanceIconBadge(icon: icon, color: color),
              const SizedBox(width: HopeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: HopeSpacing.xs),
                        _KindBadge(
                          label: 'Conta',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _accountTypes[account.type] ?? account.type,
                        if (account.bankName != null) account.bankName!,
                        if (!account.isActive) 'inativa',
                        if (!account.includeInTotal) 'fora do total',
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
              MoneyText(
                balance,
                emphasis: MoneyEmphasis.primary,
                textAlign: TextAlign.right,
                color: balance < 0 ? context.hopeColors.expense : null,
                semanticsPrefix: 'Saldo',
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.sm),
          _SourceActions(
            onViewTransactions: onViewTransactions,
            onEdit: onEdit,
          ),
        ],
      ),
    );
  }
}

class _SourceActions extends StatelessWidget {
  const _SourceActions({
    required this.onViewTransactions,
    required this.onEdit,
  });

  final VoidCallback onViewTransactions;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onViewTransactions,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Lançamentos'),
          ),
        ),
        const SizedBox(width: HopeSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Editar'),
          ),
        ),
      ],
    );
  }
}

class _CreditCardSourceTile extends StatelessWidget {
  const _CreditCardSourceTile({
    required this.card,
    required this.openAmount,
    required this.onViewTransactions,
    required this.onEdit,
  });

  final LocalCreditCard card;
  final double openAmount;
  final VoidCallback onViewTransactions;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = _nullableColorFromHex(card.color) ?? context.hopeColors.card;
    final available = card.limitAmount - openAmount;
    return AppSurface(
      child: Column(
        children: [
          Row(
            children: [
              FinanceIconBadge(icon: Icons.credit_card_outlined, color: color),
              const SizedBox(width: HopeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: HopeSpacing.xs),
                        _KindBadge(label: 'Cartão', color: color),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (card.issuer != null && card.issuer!.isNotEmpty)
                          card.issuer!,
                        'limite ${formatMoney(card.limitAmount)}',
                        'vence dia ${card.dueDay}',
                        if (!card.isActive) 'inativo',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: HopeSpacing.xs),
                    Text(
                      'Em aberto ${formatMoney(openAmount)} · disponível ${formatMoney(available)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: available >= 0
                            ? context.hopeColors.success
                            : context.hopeColors.expense,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.sm),
          _SourceActions(
            onViewTransactions: onViewTransactions,
            onEdit: onEdit,
          ),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

/// Círculo selecionável de cor para a conta.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _colorFromHex(hex),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

/// Converte um hex "#RRGGBB" em [Color] opaco; usa a cor da marca quando nulo.
Color _colorFromHex(String? hex) {
  if (hex == null || !hex.startsWith('#')) return AppTheme.hopeGreen;
  final parsed = int.tryParse(hex.substring(1).padLeft(8, 'F'), radix: 16);
  return Color((parsed ?? 0xFF000000) | 0xFF000000);
}

Color? _nullableColorFromHex(String? hex) {
  if (hex == null || !hex.startsWith('#')) return null;
  final parsed = int.tryParse(hex.substring(1).padLeft(8, 'F'), radix: 16);
  if (parsed == null) return null;
  return Color(parsed | 0xFF000000);
}
