import 'package:flutter/material.dart';

import '../../core/design_system/design_tokens.dart';
import '../../core/utils/money.dart';

/// Ação primária de uma tela, posicionada no lado direito da AppBar.
///
/// O preenchimento garante destaque sem recorrer a um FAB sobre o conteúdo.
class AppBarPrimaryAction extends StatelessWidget {
  const AppBarPrimaryAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    // Num celular estreito o rótulo disputa espaço com o título da tela e
    // estourava a barra. Aqui ele vira ícone; o nome continua no tooltip e na
    // leitura de tela, então nada se perde.
    final message = tooltip ?? label;
    final button = context.isPhone
        ? IconButton.filled(
            tooltip: message,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(kHopeMinTapTarget),
            ),
          )
        : Tooltip(
            message: message,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label, maxLines: 1),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: HopeSpacing.md),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: HopeSpacing.xs),
      child: Semantics(button: true, label: label, child: button),
    );
  }
}

/// Superfície base do app.
///
/// [level] decide se o bloco flutua: `raised` é um cartão que carrega uma
/// decisão própria; `flat` é conteúdo agrupado dentro de uma seção que já tem
/// dono. Só sobe quem precisa ser lido como unidade — é isso que evita a
/// "sopa de cartões".
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HopeSpacing.md),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = HopeRadius.md,
    this.onTap,
    this.level = HopeSurfaceLevel.raised,
    this.semanticLabel,
  });

  /// Atalho para um bloco agrupado, sem sombra.
  const AppSurface.flat({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HopeSpacing.md),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = HopeRadius.md,
    this.onTap,
    this.semanticLabel,
  }) : level = HopeSurfaceLevel.flat;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final HopeSurfaceLevel level;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raised = level == HopeSurfaceLevel.raised;
    final surface = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color:
            color ??
            (raised
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? context.hopeColors.softBorder),
        boxShadow: [
          if (raised && theme.brightness == Brightness.light)
            BoxShadow(
              color: const Color(0xFF0D1B2A).withValues(alpha: 0.045),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: child,
    );

    if (onTap == null) {
      return semanticLabel == null
          ? surface
          : Semantics(label: semanticLabel, container: true, child: surface);
    }
    return AnimatedPressable(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          // Foco de teclado visível no desktop: a borda do próprio cartão
          // não muda, então o anel precisa vir do InkWell.
          focusColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: surface,
          ),
        ),
      ),
    );
  }
}

/// Rebaixamento sutil ao toque. Some quando o sistema pede menos movimento.
class AnimatedPressable extends StatefulWidget {
  const AnimatedPressable({super.key, required this.child});

  final Widget child;

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: HopeMotion.fast,
        curve: HopeMotion.standard,
        child: widget.child,
      ),
    );
  }
}

class FinanceIconBadge extends StatelessWidget {
  const FinanceIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 2.8),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

/// Valor monetário.
///
/// Único lugar do app que decide como um número é desenhado: figuras
/// tabulares (colunas alinham), sinal explícito quando o fluxo importa,
/// máscara de privacidade e rótulo falado em português. Nunca escreva
/// `Text(formatMoney(x))` numa tela — o alinhamento entre linhas se perde.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.emphasis = MoneyEmphasis.row,
    this.color,
    this.signed = false,
    this.hidden = false,
    this.style,
    this.textAlign,
    this.strikethrough = false,
    this.semanticsPrefix,
  });

  final num? value;
  final MoneyEmphasis emphasis;
  final Color? color;

  /// Mostra `+` / `−` na frente. Use em listas de movimentação, onde a direção
  /// do dinheiro é a informação principal.
  final bool signed;

  /// Modo privacidade do painel: substitui os dígitos por marcadores.
  final bool hidden;

  final TextStyle? style;
  final TextAlign? textAlign;
  final bool strikethrough;
  final String? semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    final amount = value ?? 0;
    final negative = signed && amount < 0;
    final resolved = HopeNumerals.style(context, emphasis)
        .copyWith(
          color: color,
          decoration: strikethrough ? TextDecoration.lineThrough : null,
        )
        .merge(style);

    if (hidden) {
      return Text(
        'R\$ ••••',
        style: resolved,
        textAlign: textAlign,
        maxLines: 1,
        semanticsLabel: 'valor oculto',
      );
    }

    final formatted = formatMoney(amount.abs());
    final text = signed ? '${negative ? '−' : '+'}$formatted' : formatted;
    final spoken = moneySemanticLabel(amount, negative: negative);
    return Text(
      text,
      style: resolved,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: semanticsPrefix == null
          ? spoken
          : '$semanticsPrefix: $spoken',
    );
  }
}

/// Cabeçalho de seção. O rótulo à direita é opcional e vira botão quando
/// recebe [onAction] — antes era um `Text` com cara de link e sem toque.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.actionColor,
    this.onAction,
    this.subtitle,
  });

  final String title;
  final String? action;
  final Color? actionColor;
  final VoidCallback? onAction;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = action == null
        ? null
        : Text(
            action!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: actionColor ?? theme.colorScheme.onSurfaceVariant,
            ),
          );

    // O cabeçalho carrega o ritmo da seção: respiro grande antes, pequeno
    // depois. Assim o título "gruda" no conteúdo que ele nomeia.
    return Padding(
      padding: const EdgeInsets.only(
        top: HopeSpacing.xl,
        bottom: HopeSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (label != null)
            if (onAction == null)
              Padding(
                padding: const EdgeInsets.only(left: HopeSpacing.xs),
                child: label,
              )
            else
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HopeSpacing.xs,
                  ),
                ),
                child: Text(action!),
              ),
        ],
      ),
    );
  }
}

/// Rótulo de agrupamento em caixa alta. Um só lugar define o tratamento.
class SectionEyebrow extends StatelessWidget {
  const SectionEyebrow(this.label, {super.key, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            HopeSpacing.xxs,
            HopeSpacing.xl,
            HopeSpacing.xxs,
            HopeSpacing.xs,
          ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Estado vazio. Um convite para agir, nunca um aviso de ausência.
class PremiumEmptyState extends StatelessWidget {
  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  /// Versão reduzida para caber dentro de um cartão já existente.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = compact ? 52.0 : 72.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? HopeSpacing.lg : HopeSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(HopeRadius.lg),
              ),
              child: Icon(
                icon,
                size: side * 0.44,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: HopeSpacing.md),
            Text(
              title,
              style: compact
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HopeSpacing.xs),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: HopeSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Ausência de dados **dentro** de um painel que já tem título.
///
/// Não repete o assunto (o cabeçalho do painel já disse qual é) — só explica o
/// vazio, em uma linha.
class InlineEmptyState extends StatelessWidget {
  const InlineEmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: text,
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 30),
          const SizedBox(height: HopeSpacing.xs),
          ExcludeSemantics(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de erro.
///
/// Diz o que falhou, em português, e oferece a saída. Nunca despeja a exceção
/// na tela: o texto técnico vai para "Detalhes", atrás de um toque.
class HopeErrorState extends StatelessWidget {
  const HopeErrorState({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Tentar de novo',
    this.compact = false,
  });

  /// Erro de carregamento com a mensagem padrão do app.
  factory HopeErrorState.load(
    Object error, {
    String what = 'estes dados',
    VoidCallback? onRetry,
    bool compact = false,
  }) => HopeErrorState(
    message: 'Não foi possível carregar $what.',
    detail: error.toString(),
    onRetry: onRetry,
    compact: compact,
  );

  final String message;
  final String? detail;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? HopeSpacing.lg : HopeSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 44 : 60,
                height: compact ? 44 : 60,
                decoration: BoxDecoration(
                  color: context.hopeColors.negativeSurface,
                  borderRadius: BorderRadius.circular(HopeRadius.md),
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: compact ? 22 : 28,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: HopeSpacing.md),
              Text(
                message,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HopeSpacing.xxs),
              Text(
                'Verifique a conexão. Seus dados locais continuam disponíveis.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: HopeSpacing.md),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kHopeMinTapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: HopeSpacing.lg,
                    ),
                  ),
                ),
              ],
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: HopeSpacing.xs),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Detalhes técnicos'),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          detail!,
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Ver detalhes'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tom de uma mensagem efêmera.
enum HopeSnackTone { neutral, success, warning, danger }

/// Confirmação efêmera padronizada.
///
/// Sucesso, alerta e falha têm o mesmo formato e o mesmo lugar; só o ícone e a
/// cor da barra lateral mudam. Ação opcional para desfazer ou seguir adiante.
void showHopeSnack(
  BuildContext context,
  String message, {
  HopeSnackTone tone = HopeSnackTone.neutral,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final colors = context.hopeColors;
  final accent = switch (tone) {
    HopeSnackTone.neutral => Theme.of(context).colorScheme.inversePrimary,
    // O SnackBar pinta o fundo com `inverseSurface`, que é o inverso do tema —
    // por isso acentos próprios, e não os do painel herói (ver design_tokens).
    HopeSnackTone.success => colors.onInverseIncome,
    HopeSnackTone.warning => colors.onInverseWarning,
    HopeSnackTone.danger => colors.onInverseExpense,
  };
  final icon = switch (tone) {
    HopeSnackTone.neutral => Icons.info_outline_rounded,
    HopeSnackTone.success => Icons.check_circle_outline_rounded,
    HopeSnackTone.warning => Icons.warning_amber_rounded,
    HopeSnackTone.danger => Icons.error_outline_rounded,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: tone == HopeSnackTone.danger ? 6 : 4),
        content: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: HopeSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// Indicador compacto de um número com rótulo. Vira botão quando recebe
/// [onTap] — e aí respeita o alvo mínimo de toque.
class MetricPill extends StatelessWidget {
  const MetricPill({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(
        horizontal: HopeSpacing.sm,
        vertical: HopeSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HopeRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
          ],
          // Flexível: o valor pode ser um nome de categoria comprido, e a
          // pilha vive dentro de um Wrap que já limita a largura.
          Flexible(
            child: Text(
              '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, color: color, size: 16),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(label: '$label $value', child: content);
    }
    return Semantics(
      button: true,
      label: '$label $value',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(HopeRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HopeRadius.pill),
          child: content,
        ),
      ),
    );
  }
}

class HopeSkeleton extends StatefulWidget {
  const HopeSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  State<HopeSkeleton> createState() => _HopeSkeletonState();
}

class _HopeSkeletonState extends State<HopeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sem o brilho correndo, o esqueleto vira um bloco cinza estático — é o
    // que o usuário pediu ao desligar animações no sistema.
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHigh;
    final highlight = Theme.of(context).colorScheme.surface;
    return Semantics(
      label: 'Carregando',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ListView.separated(
            padding: const EdgeInsets.all(HopeSpacing.md),
            itemCount: widget.rows,
            separatorBuilder: (_, _) => const SizedBox(height: HopeSpacing.sm),
            itemBuilder: (context, index) {
              final widthFactor = index.isEven ? 0.92 : 0.72;
              return AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(
                      height: 18,
                      widthFactor: widthFactor,
                      base: base,
                      highlight: highlight,
                      progress: _controller.value,
                    ),
                    const SizedBox(height: HopeSpacing.sm),
                    _SkeletonBar(
                      height: 44,
                      widthFactor: 1,
                      base: base,
                      highlight: highlight,
                      progress: _controller.value,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PremiumFormSheet extends StatelessWidget {
  const PremiumFormSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.formKey,
    required this.fields,
    required this.primaryAction,
    this.secondaryAction,
    this.destructiveAction,
    this.maxWidth = 620,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final Widget primaryAction;
  final Widget? secondaryAction;
  final Widget? destructiveAction;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bottomPadding = viewInsets.bottom + HopeSpacing.lg;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sheetHeight = constraints.maxHeight;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Form(
                key: formKey,
                child: CustomScrollView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        HopeSpacing.lg,
                        HopeSpacing.xs,
                        HopeSpacing.lg,
                        bottomPadding,
                      ),
                      sliver: SliverList.list(
                        children: [
                          _FormSheetHeader(
                            title: title,
                            subtitle: subtitle,
                            icon: icon,
                          ),
                          const SizedBox(height: HopeSpacing.lg),
                          ..._withVerticalGaps(fields, HopeSpacing.sm),
                          const SizedBox(height: HopeSpacing.lg),
                          _FormActionBar(
                            primaryAction: primaryAction,
                            secondaryAction: secondaryAction,
                          ),
                          if (destructiveAction != null) ...[
                            const SizedBox(height: HopeSpacing.xs),
                            destructiveAction!,
                          ],
                          SizedBox(height: sheetHeight < 520 ? 0 : 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PremiumFormSection extends StatelessWidget {
  const PremiumFormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppSurface.flat(
      padding: const EdgeInsets.all(HopeSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: HopeSpacing.md),
          ..._withVerticalGaps(children, HopeSpacing.sm),
        ],
      ),
    );
  }
}

class FormSwitchRow extends StatelessWidget {
  const FormSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A linha inteira alterna o valor: o alvo passa de 32px (só o switch) para
    // a largura toda do campo.
    return Semantics(
      toggled: value,
      label: title,
      hint: subtitle,
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(HopeRadius.sm),
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: kHopeMinTapTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: HopeSpacing.sm,
              vertical: HopeSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HopeRadius.sm),
              border: Border.all(color: context.hopeColors.softBorder),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: HopeSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Switch(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSheetHeader extends StatelessWidget {
  const _FormSheetHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FinanceIconBadge(
          icon: icon,
          color: Theme.of(context).colorScheme.primary,
          size: 44,
        ),
        const SizedBox(width: HopeSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _FormActionBar extends StatelessWidget {
  const _FormActionBar({
    required this.primaryAction,
    required this.secondaryAction,
  });

  final Widget primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    if (secondaryAction == null) return primaryAction;
    return Row(
      children: [
        Expanded(child: secondaryAction!),
        const SizedBox(width: HopeSpacing.sm),
        Expanded(child: primaryAction),
      ],
    );
  }
}

List<Widget> _withVerticalGaps(List<Widget> children, double gap) {
  return [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) SizedBox(height: gap),
      children[i],
    ],
  ];
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.height,
    required this.widthFactor,
    required this.base,
    required this.highlight,
    required this.progress,
  });

  final double height;
  final double widthFactor;
  final Color base;
  final Color highlight;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HopeRadius.xs),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0, 0.45, 1],
            colors: [base, Color.lerp(base, highlight, 0.72)!, base],
            transform: _SlidingGradient(progress),
          ),
        ),
      ),
    );
  }
}

class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.progress);

  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
  }
}
