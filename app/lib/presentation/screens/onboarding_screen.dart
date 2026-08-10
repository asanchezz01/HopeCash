import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/providers.dart';
import '../components/hope_components.dart';
import '../widgets/brand_logo.dart';

/// Última página do tutorial (a da conexão MCP) — ela ganha um atalho extra
/// para a tela de tokens, por isso o índice é nomeado.
const _lastPageIndex = 8;

/// Tutorial de boas-vindas: 9 passos visuais com swipe, indicador de páginas
/// e botão de pular. Abre sozinho no primeiro login e fica disponível em
/// "Mais → Tutorial do HopeCash". Os exemplos são apenas ilustrativos —
/// nenhum dado é criado no banco.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = _lastPageIndex + 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pageCount - 1;

  Future<void> _finish() async {
    final user = ref.read(authStateProvider);
    if (user != null) {
      await ref
          .read(databaseProvider)
          .setStateValue('onboarding_completed_${user.id}', '1');
      // Servidor guarda a marca definitiva — o tutorial não reabre nem em
      // outro aparelho, nem após reinstalar o app.
      unawaited(ref.read(authRepositoryProvider).markOnboardingSeen());
      ref.invalidate(onboardingSeenProvider);
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Atalho da página de MCP: encerra o tutorial e abre a tela onde o token
  /// é gerado. O router é capturado antes porque `_finish` desmonta esta tela.
  Future<void> _openApiTokens() async {
    final router = GoRouter.of(context);
    await _finish();
    router.push('/more/api-tokens');
  }

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: HopeMotion.normal,
    curve: HopeMotion.standard,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HopeSpacing.lg,
                HopeSpacing.sm,
                HopeSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  const HopeCashLogo(compact: true, iconSize: 30),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Pular')),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: const _AnyDeviceScrollBehavior(),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pageCount,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: HopeSpacing.lg,
                          vertical: HopeSpacing.md,
                        ),
                        child: _OnboardingPage(
                          index: index,
                          onOpenApiTokens: _openApiTokens,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HopeSpacing.lg,
                HopeSpacing.sm,
                HopeSpacing.lg,
                HopeSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _page > 0
                          ? TextButton(
                              onPressed: () => _goTo(_page - 1),
                              child: const Text('Voltar'),
                            )
                          : null,
                    ),
                  ),
                  _PageDots(count: _pageCount, current: _page),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isLast ? _finish : () => _goTo(_page + 1),
                        child: Text(_isLast ? 'Começar' : 'Próximo'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PageView arrastável também com mouse/trackpad (desktop e web).
class _AnyDeviceScrollBehavior extends MaterialScrollBehavior {
  const _AnyDeviceScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Passo ${current + 1} de $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: HopeMotion.normal,
              curve: HopeMotion.standard,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == current ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(HopeRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}

/// Entrada suave (fade + deslizamento) usada para animar cada bloco da página.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - _t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.index, required this.onOpenApiTokens});

  final int index;
  final VoidCallback onOpenApiTokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, description, illustration) = switch (index) {
      0 => (
        'Bem-vindo ao HopeCash',
        'Organize sua vida financeira em um só lugar: contas, cartões, '
            'lançamentos, orçamento, metas, dívidas e investimentos.',
        const _WelcomeIllustration() as Widget,
      ),
      1 => (
        'Lançamentos: o coração do app',
        'Cada receita, despesa ou compra no cartão vira um lançamento. '
            'Registre em segundos pelos botões Voz e Lançar da barra de '
            'navegação — são eles que alimentam o dashboard e os relatórios.',
        const _TransactionsIllustration(),
      ),
      2 => (
        'Categorias organizam tudo',
        'Classifique os lançamentos por categoria para entender para onde '
            'o dinheiro vai — e de onde ele vem.',
        const _CategoriesIllustration(),
      ),
      3 => (
        'Orçamento: o plano do mês',
        'Defina quanto pretende gastar (ou receber) em cada categoria e '
            'acompanhe o planejado × realizado ao longo do mês.',
        const _BudgetIllustration(),
      ),
      4 => (
        'Dívidas, metas e investimentos',
        'Acompanhe parcelas e saldo devedor, guarde dinheiro para objetivos '
            'e acompanhe o patrimônio aplicado.',
        const _GoalsIllustration(),
      ),
      5 => (
        'Dashboard: o resultado de tudo',
        'O dashboard resume o que você lançou e planejou. Quanto mais '
            'completos os lançamentos, melhor o retrato das suas finanças.',
        const _DashboardIllustration(),
      ),
      6 => (
        'Conheça a Hope, sua assistente',
        'Converse por texto ou voz sobre as suas finanças: saldo, gastos do '
            'mês, orçamento, faturas e vencimentos. A Hope consulta seus '
            'dados na hora — toque no ícone ✦ no dashboard para começar.',
        const _HopeIllustration(),
      ),
      7 => (
        'A Hope também lança por você',
        'Peça em português: "lance R\$ 250 de mercado hoje". Ela monta o '
            'lançamento, escolhe a categoria e espera o seu OK — nada é '
            'gravado sem confirmação.',
        const _HopeActionsIllustration(),
      ),
      _ => (
        'Plugue o ChatGPT ou o Claude',
        'O HopeCash fala MCP: conecte um agente externo e pergunte sobre as '
            'suas finanças (ou peça um lançamento) sem sair da conversa dele. '
            'O acesso é só à sua conta, e você revoga quando quiser.',
        const _McpIllustration(),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Entrance(child: illustration),
        const SizedBox(height: HopeSpacing.lg),
        _Entrance(
          delayMs: 90,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: HopeSpacing.sm),
        _Entrance(
          delayMs: 180,
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (index == _lastPageIndex) ...[
          const SizedBox(height: HopeSpacing.md),
          _Entrance(
            delayMs: 260,
            child: Center(
              child: OutlinedButton.icon(
                onPressed: onOpenApiTokens,
                icon: const Icon(Icons.key_outlined, size: 18),
                label: const Text('Gerar meu token agora'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ilustrações — composições visuais com dados de exemplo (nada é gravado).
// ---------------------------------------------------------------------------

class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    final hope = context.hopeColors;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HopeRadius.lg),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [hope.heroStart, hope.heroEnd],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(HopeSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: hope.heroOnSurfaceMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'R\$ 4.250,00',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: hope.heroOnSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: HopeSpacing.sm),
                Wrap(
                  spacing: HopeSpacing.xs,
                  runSpacing: HopeSpacing.xs,
                  children: [
                    MetricPill(
                      label: 'Receitas',
                      value: 'R\$ 6.200',
                      color: hope.heroIncome,
                      icon: Icons.arrow_upward_rounded,
                    ),
                    MetricPill(
                      label: 'Despesas',
                      value: 'R\$ 1.950',
                      color: hope.heroExpense,
                      icon: Icons.arrow_downward_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HopeSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                icon: Icons.credit_card_outlined,
                color: hope.card,
                label: 'Cartões',
              ),
            ),
            const SizedBox(width: HopeSpacing.xs),
            Expanded(
              child: _MiniStat(
                icon: Icons.flag_outlined,
                color: hope.investment,
                label: 'Metas',
              ),
            ),
            const SizedBox(width: HopeSpacing.xs),
            Expanded(
              child: _MiniStat(
                icon: Icons.show_chart_outlined,
                color: hope.success,
                label: 'Investimentos',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransactionsIllustration extends StatelessWidget {
  const _TransactionsIllustration();

  @override
  Widget build(BuildContext context) {
    final hope = context.hopeColors;
    return Column(
      children: [
        _MockTile(
          icon: Icons.arrow_upward_rounded,
          color: hope.income,
          title: 'Salário',
          subtitle: 'Receita · Conta corrente',
          trailing: '+R\$ 5.000,00',
        ),
        const SizedBox(height: HopeSpacing.xs),
        _MockTile(
          icon: Icons.arrow_downward_rounded,
          color: hope.expense,
          title: 'Mercado',
          subtitle: 'Despesa · Alimentação',
          trailing: '-R\$ 250,00',
        ),
        const SizedBox(height: HopeSpacing.xs),
        _MockTile(
          icon: Icons.credit_card_outlined,
          color: hope.card,
          title: 'Farmácia no cartão',
          subtitle: 'Cartão de crédito · Saúde',
          trailing: '-R\$ 80,00',
        ),
        const SizedBox(height: HopeSpacing.sm),
        const _MockNavBar(),
      ],
    );
  }
}

/// Réplica em miniatura da barra de navegação, destacando as ações de
/// lançamento (Voz e Lançar) que ficam integradas a ela.
class _MockNavBar extends StatelessWidget {
  const _MockNavBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.md,
        vertical: HopeSpacing.sm,
      ),
      // Cada item ocupa um quarto da barra — em telas estreitas isso é o que
      // impede a réplica de estourar para fora do cartão.
      child: Row(
        children: [
          Expanded(
            child: _MockNavItem(
              icon: Icons.home_outlined,
              label: 'Inicio',
              color: scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: _MockNavItem(
              icon: Icons.mic_none_rounded,
              label: 'Voz',
              color: scheme.primary,
              highlighted: true,
            ),
          ),
          Expanded(
            child: _MockNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: 'Lançar',
              color: scheme.primary,
              highlighted: true,
            ),
          ),
          Expanded(
            child: _MockNavItem(
              icon: Icons.more_horiz,
              label: 'Mais',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockNavItem extends StatelessWidget {
  const _MockNavItem({
    required this.icon,
    required this.label,
    required this.color,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.xs,
        vertical: HopeSpacing.xs,
      ),
      decoration: highlighted
          ? BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(HopeRadius.pill),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriesIllustration extends StatelessWidget {
  const _CategoriesIllustration();

  @override
  Widget build(BuildContext context) {
    final hope = context.hopeColors;
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: HopeSpacing.xs,
            runSpacing: HopeSpacing.xs,
            children: [
              _CategoryChip(
                icon: Icons.restaurant_outlined,
                label: 'Alimentação',
                color: hope.expense,
              ),
              _CategoryChip(
                icon: Icons.home_outlined,
                label: 'Moradia',
                color: hope.card,
              ),
              _CategoryChip(
                icon: Icons.directions_car_outlined,
                label: 'Transporte',
                color: hope.warning,
              ),
              _CategoryChip(
                icon: Icons.payments_outlined,
                label: 'Receita',
                color: hope.income,
              ),
            ],
          ),
          const SizedBox(height: HopeSpacing.sm),
          Text(
            'Alimentação: mercado, restaurante, padaria\n'
            'Moradia: aluguel, energia, internet\n'
            'Transporte: combustível, Uber, manutenção\n'
            'Receita: salário, bônus, renda extra',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetIllustration extends StatelessWidget {
  const _BudgetIllustration();

  @override
  Widget build(BuildContext context) {
    final hope = context.hopeColors;
    return AppSurface(
      child: Column(
        children: [
          _MockBudgetBar(
            label: 'Alimentação',
            spentLabel: 'R\$ 850 de R\$ 1.200',
            progress: 850 / 1200,
            color: hope.success,
          ),
          const SizedBox(height: HopeSpacing.md),
          _MockBudgetBar(
            label: 'Moradia',
            spentLabel: 'R\$ 1.950 de R\$ 2.000',
            progress: 1950 / 2000,
            color: hope.warning,
          ),
        ],
      ),
    );
  }
}

class _GoalsIllustration extends StatelessWidget {
  const _GoalsIllustration();

  @override
  Widget build(BuildContext context) {
    final hope = context.hopeColors;
    return Column(
      children: [
        _MockTile(
          icon: Icons.trending_down_outlined,
          color: hope.warning,
          title: 'Financiamento',
          subtitle: 'Dívida · parcela 8/24',
          trailing: 'R\$ 890/mês',
        ),
        const SizedBox(height: HopeSpacing.xs),
        _MockTile(
          icon: Icons.flag_outlined,
          color: hope.investment,
          title: 'Reserva de emergência',
          subtitle: 'Meta · 65% alcançado',
          trailing: '65%',
          progress: 0.65,
        ),
        const SizedBox(height: HopeSpacing.xs),
        _MockTile(
          icon: Icons.show_chart_outlined,
          color: hope.success,
          title: 'Tesouro Selic',
          subtitle: 'Investimento · renda fixa',
          trailing: 'R\$ 3.500',
        ),
      ],
    );
  }
}

class _DashboardIllustration extends StatelessWidget {
  const _DashboardIllustration();

  @override
  Widget build(BuildContext context) {
    final hope = context.hopeColors;
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (Icons.account_balance_wallet_outlined, hope.success, 'Saldo total'),
      (Icons.arrow_upward_rounded, hope.income, 'Receitas do mês'),
      (Icons.arrow_downward_rounded, hope.expense, 'Despesas do mês'),
      (Icons.event_outlined, hope.warning, 'Próximos vencimentos'),
      (Icons.pie_chart_outline, scheme.primary, 'Gastos por categoria'),
      (Icons.credit_card_outlined, hope.card, 'Cartões em aberto'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - HopeSpacing.xs) / 2;
        return Wrap(
          spacing: HopeSpacing.xs,
          runSpacing: HopeSpacing.xs,
          children: [
            for (final (icon, color, label) in items)
              SizedBox(
                width: tileWidth,
                child: _MiniStat(icon: icon, color: color, label: label),
              ),
          ],
        );
      },
    );
  }
}

class _HopeIllustration extends StatelessWidget {
  const _HopeIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 22, color: scheme.primary),
            const SizedBox(width: HopeSpacing.xs),
            Text(
              'Hope',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: HopeSpacing.sm),
        const _MockChatBubble(isUser: true, text: 'Quanto gastei este mês?'),
        const _MockChatBubble(
          isUser: false,
          text:
              'Você gastou R\$ 1.950,00 até agora. As maiores despesas '
              'foram em Moradia e Alimentação.',
        ),
        const SizedBox(height: HopeSpacing.sm),
        Wrap(
          spacing: HopeSpacing.xs,
          runSpacing: HopeSpacing.xs,
          alignment: WrapAlignment.center,
          children: [
            for (final suggestion in const [
              'Qual é o meu saldo?',
              'Como está meu orçamento?',
              'O que vence esta semana?',
            ])
              _CategoryChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: suggestion,
                color: scheme.primary,
              ),
          ],
        ),
        const SizedBox(height: HopeSpacing.sm),
        // As três formas de usar a Hope, na ordem em que aparecem na tela dela.
        Row(
          children: const [
            Expanded(
              child: _MiniFeature(
                icon: Icons.keyboard_alt_outlined,
                label: 'Digite',
              ),
            ),
            SizedBox(width: HopeSpacing.xs),
            Expanded(
              child: _MiniFeature(icon: Icons.mic_none_rounded, label: 'Fale'),
            ),
            SizedBox(width: HopeSpacing.xs),
            Expanded(
              child: _MiniFeature(
                icon: Icons.volume_up_outlined,
                label: 'Ouça',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Passo 8 — a Hope propondo um lançamento e aguardando confirmação humana.
class _HopeActionsIllustration extends StatelessWidget {
  const _HopeActionsIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hope = context.hopeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pedido chegando por voz — o caminho mais rápido de lançar.
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: HopeSpacing.md,
              vertical: HopeSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(HopeRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Lance R\$ 250 de mercado hoje',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HopeSpacing.sm),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'A Hope sugere',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HopeSpacing.sm),
              Row(
                children: [
                  FinanceIconBadge(
                    icon: Icons.arrow_downward_rounded,
                    color: hope.expense,
                    size: 36,
                  ),
                  const SizedBox(width: HopeSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mercado', style: theme.textTheme.titleSmall),
                        Text(
                          'Despesa · Alimentação · hoje',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '-R\$ 250,00',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: hope.expense,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HopeSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _MockButton(
                      label: 'Descartar',
                      icon: Icons.close_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: HopeSpacing.xs),
                  Expanded(
                    child: _MockButton(
                      label: 'Confirmar',
                      icon: Icons.check_rounded,
                      color: scheme.primary,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Passo 9 — os dois agentes externos ligados ao HopeCash por MCP.
class _McpIllustration extends StatelessWidget {
  const _McpIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hope = context.hopeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _HostBadge(icon: Icons.smart_toy_outlined, label: 'ChatGPT'),
            ),
            const _DashedLink(),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [hope.heroStart, hope.heroEnd],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(HopeSpacing.sm),
                child: Icon(
                  Icons.hub_outlined,
                  color: hope.heroOnSurface,
                  size: 26,
                ),
              ),
            ),
            const _DashedLink(),
            const Expanded(
              child: _HostBadge(
                icon: Icons.psychology_outlined,
                label: 'Claude',
              ),
            ),
          ],
        ),
        const SizedBox(height: HopeSpacing.sm),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _NumberedStep(
                number: 1,
                text: 'Copie a URL do MCP em Mais → Apps conectados.',
              ),
              const _NumberedStep(
                number: 2,
                text: 'No ChatGPT, use essa URL como conector: o login e a '
                    'escolha do nível de acesso acontecem na hora, sem colar '
                    'token nenhum.',
              ),
              const _NumberedStep(
                number: 3,
                text: 'No Claude Code e em automações, que não fazem esse login '
                    'automático, gere um token manual na mesma tela (em "Uso '
                    'avançado") e cole na configuração.',
              ),
              const _NumberedStep(
                number: 4,
                text: 'Pronto — pergunte de lá. Tudo que estiver conectado '
                    'aparece nessa tela e pode ser desconectado a qualquer '
                    'momento.',
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: HopeSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Só os seus dados, nunca os de outra pessoa.',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Agente externo (host MCP) representado como cartão compacto.
class _HostBadge extends StatelessWidget {
  const _HostBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.xs,
        vertical: HopeSpacing.sm,
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha pontilhada curta ligando um agente externo ao HopeCash.
class _DashedLink extends StatelessWidget {
  const _DashedLink();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({
    required this.number,
    required this.text,
    this.last = false,
  });

  final int number;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : HopeSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: HopeSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão apenas ilustrativo — não recebe toque.
class _MockButton extends StatelessWidget {
  const _MockButton({
    required this.label,
    required this.icon,
    required this.color,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: HopeSpacing.xs),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(HopeRadius.pill),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: filled ? Theme.of(context).colorScheme.onPrimary : color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: filled ? Theme.of(context).colorScheme.onPrimary : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Recurso da Hope em formato compacto (ícone acima do rótulo).
class _MiniFeature extends StatelessWidget {
  const _MiniFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.xs,
        vertical: HopeSpacing.sm,
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// Bolha de chat no mesmo estilo da conversa real com a Hope.
class _MockChatBubble extends StatelessWidget {
  const _MockChatBubble({required this.isUser, required this.text});

  final bool isUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: HopeSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.sm,
        ),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isUser ? scheme.onPrimaryContainer : scheme.onSurface,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blocos reutilizáveis das ilustrações
// ---------------------------------------------------------------------------

class _MockTile extends StatelessWidget {
  const _MockTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.progress,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.md,
        vertical: HopeSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              FinanceIconBadge(icon: icon, color: color, size: 36),
              const SizedBox(width: HopeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                trailing,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: HopeSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(HopeRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MockBudgetBar extends StatelessWidget {
  const _MockBudgetBar({
    required this.label,
    required this.spentLabel,
    required this.progress,
    required this.color,
  });

  final String label;
  final String spentLabel;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(
              spentLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(HopeRadius.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.sm,
        vertical: HopeSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HopeRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          // Rótulos longos (sugestões da Hope) precisam ceder em telas estreitas.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.sm,
        vertical: HopeSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: HopeSpacing.xs),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
