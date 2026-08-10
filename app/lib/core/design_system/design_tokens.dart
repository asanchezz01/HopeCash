import 'package:flutter/material.dart';

/// Escala de espaçamento em passos de 4. Use os nomes, nunca literais soltos:
/// é o que mantém o ritmo vertical igual entre telas.
class HopeSpacing {
  const HopeSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

class HopeRadius {
  const HopeRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}

class HopeMotion {
  const HopeMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}

class HopeBreakpoints {
  const HopeBreakpoints._();

  static const double mobile = 0;
  static const double foldable = 600;
  static const double tablet = 840;
  static const double desktop = 1200;
  static const double ultraWide = 1600;
}

/// Alvo mínimo de toque recomendado pelas diretrizes de acessibilidade.
/// Qualquer controle interativo próprio deve respeitar este valor.
const double kHopeMinTapTarget = 48;

/// Largura máxima de leitura confortável para conteúdo em telas largas.
const double kHopeContentMaxWidth = 1120;

/// Ênfase de um valor monetário — define tamanho, peso e tracking.
///
/// A régua existe para que dois números com o mesmo papel tenham sempre o
/// mesmo tratamento, em qualquer tela.
enum MoneyEmphasis {
  /// Número herói: o saldo que resume a tela.
  hero,

  /// Valor principal de um painel ou seção.
  primary,

  /// Valor de uma linha de lista.
  row,

  /// Valor de apoio, sempre subordinado a outro número.
  caption,
}

/// Tipografia de números.
///
/// Dinheiro nunca usa figuras proporcionais: com `tabularFigures` todos os
/// dígitos ocupam a mesma largura, então colunas de valores alinham e o número
/// não "dança" quando muda de 9 para 10.
class HopeNumerals {
  const HopeNumerals._();

  static const List<FontFeature> features = [FontFeature.tabularFigures()];

  static TextStyle style(BuildContext context, MoneyEmphasis emphasis) {
    final text = Theme.of(context).textTheme;
    final base = switch (emphasis) {
      MoneyEmphasis.hero => text.displaySmall,
      MoneyEmphasis.primary => text.titleLarge,
      MoneyEmphasis.row => text.titleSmall,
      MoneyEmphasis.caption => text.bodySmall,
    };
    final weight = switch (emphasis) {
      MoneyEmphasis.hero => FontWeight.w800,
      MoneyEmphasis.primary => FontWeight.w800,
      MoneyEmphasis.row => FontWeight.w700,
      MoneyEmphasis.caption => FontWeight.w600,
    };
    // Números grandes pedem tracking negativo para não parecerem espaçados;
    // números pequenos pedem o contrário para continuarem legíveis.
    final tracking = switch (emphasis) {
      MoneyEmphasis.hero => -0.8,
      MoneyEmphasis.primary => -0.3,
      MoneyEmphasis.row => -0.1,
      MoneyEmphasis.caption => 0.0,
    };
    return (base ?? const TextStyle()).copyWith(
      fontWeight: weight,
      letterSpacing: tracking,
      fontFeatures: features,
    );
  }
}

/// Nível de uma superfície. Elevação carrega informação: só sobe quem é uma
/// unidade independente de decisão.
enum HopeSurfaceLevel {
  /// Bloco agrupado dentro de uma seção — sem sombra, apenas contorno.
  flat,

  /// Cartão independente que carrega uma decisão. Padrão.
  raised,
}

class HopeColors extends ThemeExtension<HopeColors> {
  const HopeColors({
    required this.income,
    required this.expense,
    required this.investment,
    required this.card,
    required this.warning,
    required this.success,
    required this.heroStart,
    required this.heroEnd,
    required this.softBorder,
    required this.positiveSurface,
    required this.negativeSurface,
    required this.infoSurface,
    required this.heroIncome,
    required this.heroExpense,
    required this.heroInvestment,
    required this.heroWarning,
    required this.heroOnSurface,
    required this.heroOnSurfaceMuted,
    required this.onInverseIncome,
    required this.onInverseExpense,
    required this.onInverseWarning,
  });

  final Color income;
  final Color expense;
  final Color investment;
  final Color card;
  final Color warning;
  final Color success;
  final Color heroStart;
  final Color heroEnd;
  final Color softBorder;
  final Color positiveSurface;
  final Color negativeSurface;
  final Color infoSurface;

  /// Acentos para uso **sobre o painel herói**, que segue o tema: gradiente
  /// claro no modo claro, escuro no modo escuro.
  ///
  /// Existem separados de `income`/`expense`… porque o painel não é a mesma
  /// superfície que um card comum — o tom de fundo é outro, e cada acento aqui
  /// foi verificado contra a ponta MAIS ESCURA do gradiente (≥ 4,5:1).
  final Color heroIncome;
  final Color heroExpense;
  final Color heroInvestment;
  final Color heroWarning;
  final Color heroOnSurface;
  final Color heroOnSurfaceMuted;

  /// Acentos para uso sobre `colorScheme.inverseSurface` — na prática, o
  /// SnackBar, cuja cor de fundo é o INVERSO do tema (escura no tema claro,
  /// clara no tema escuro). É o oposto do painel herói, por isso tokens
  /// próprios: antes o snack pegava emprestados os `hero*`, o que dava certo
  /// no tema claro por coincidência e reprovava em contraste no escuro.
  final Color onInverseIncome;
  final Color onInverseExpense;
  final Color onInverseWarning;

  /// Acento correspondente ao tipo de movimento (`income`/`expense`).
  Color forType(String type) => type == 'income' ? income : expense;

  static const light = HopeColors(
    income: Color(0xFF10714A),
    expense: Color(0xFFB03A3A),
    investment: Color(0xFF1F5FE0),
    card: Color(0xFF6B4CC9),
    warning: Color(0xFFA2600B),
    success: Color(0xFF10714A),
    // Gradiente do painel herói no tema claro. Um verde-menta suave: precisa
    // se destacar do fundo da página (#F6F8FA) e dos cards brancos sem virar
    // outro retângulo branco. Contrastes conferidos contra a ponta mais escura
    // (#DCEFE7): texto 12,7:1, apoio 5,4:1, acentos ≥ 4,7:1.
    heroStart: Color(0xFFEDF8F3),
    heroEnd: Color(0xFFDCEFE7),
    softBorder: Color(0xFFE3E9EF),
    positiveSurface: Color(0xFFEAF7F1),
    negativeSurface: Color(0xFFFBEDED),
    infoSurface: Color(0xFFEAF2FF),
    heroIncome: Color(0xFF10714A),
    heroExpense: Color(0xFFB03A3A),
    heroInvestment: Color(0xFF1F5FE0),
    // Mais escuro que o `warning` normal (#A2600B): aquele dá só 4,05:1 sobre
    // o verde-menta e reprovaria.
    heroWarning: Color(0xFF8A5209),
    heroOnSurface: Color(0xFF1B263B),
    heroOnSurfaceMuted: Color(0xFF4E6076),
    // Snack no tema claro = fundo escuro, então acentos luminosos.
    onInverseIncome: Color(0xFF55D69C),
    onInverseExpense: Color(0xFFFF9E9E),
    onInverseWarning: Color(0xFFF2BC62),
  );

  static const dark = HopeColors(
    income: Color(0xFF55D69C),
    expense: Color(0xFFFF9E9E),
    investment: Color(0xFF8DB2FF),
    card: Color(0xFFB8A7FF),
    warning: Color(0xFFF2BC62),
    success: Color(0xFF55D69C),
    heroStart: Color(0xFF07111F),
    heroEnd: Color(0xFF142B42),
    softBorder: Color(0xFF26394B),
    positiveSurface: Color(0xFF0E3428),
    negativeSurface: Color(0xFF3B1F24),
    infoSurface: Color(0xFF102B4E),
    heroIncome: Color(0xFF55D69C),
    heroExpense: Color(0xFFFF9E9E),
    heroInvestment: Color(0xFF8DB2FF),
    heroWarning: Color(0xFFF2BC62),
    heroOnSurface: Color(0xFFFFFFFF),
    heroOnSurfaceMuted: Color(0xFFB6C0CB),
    // Snack no tema escuro = fundo claro, então acentos profundos.
    onInverseIncome: Color(0xFF10714A),
    onInverseExpense: Color(0xFFB03A3A),
    onInverseWarning: Color(0xFF8A5209),
  );

  @override
  HopeColors copyWith({
    Color? income,
    Color? expense,
    Color? investment,
    Color? card,
    Color? warning,
    Color? success,
    Color? heroStart,
    Color? heroEnd,
    Color? softBorder,
    Color? positiveSurface,
    Color? negativeSurface,
    Color? infoSurface,
    Color? heroIncome,
    Color? heroExpense,
    Color? heroInvestment,
    Color? heroWarning,
    Color? heroOnSurface,
    Color? heroOnSurfaceMuted,
    Color? onInverseIncome,
    Color? onInverseExpense,
    Color? onInverseWarning,
  }) {
    return HopeColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      investment: investment ?? this.investment,
      card: card ?? this.card,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      softBorder: softBorder ?? this.softBorder,
      positiveSurface: positiveSurface ?? this.positiveSurface,
      negativeSurface: negativeSurface ?? this.negativeSurface,
      infoSurface: infoSurface ?? this.infoSurface,
      heroIncome: heroIncome ?? this.heroIncome,
      heroExpense: heroExpense ?? this.heroExpense,
      heroInvestment: heroInvestment ?? this.heroInvestment,
      heroWarning: heroWarning ?? this.heroWarning,
      heroOnSurface: heroOnSurface ?? this.heroOnSurface,
      heroOnSurfaceMuted: heroOnSurfaceMuted ?? this.heroOnSurfaceMuted,
      onInverseIncome: onInverseIncome ?? this.onInverseIncome,
      onInverseExpense: onInverseExpense ?? this.onInverseExpense,
      onInverseWarning: onInverseWarning ?? this.onInverseWarning,
    );
  }

  @override
  HopeColors lerp(ThemeExtension<HopeColors>? other, double t) {
    if (other is! HopeColors) return this;
    return HopeColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      investment: Color.lerp(investment, other.investment, t)!,
      card: Color.lerp(card, other.card, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      softBorder: Color.lerp(softBorder, other.softBorder, t)!,
      positiveSurface: Color.lerp(positiveSurface, other.positiveSurface, t)!,
      negativeSurface: Color.lerp(negativeSurface, other.negativeSurface, t)!,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t)!,
      heroIncome: Color.lerp(heroIncome, other.heroIncome, t)!,
      heroExpense: Color.lerp(heroExpense, other.heroExpense, t)!,
      heroInvestment: Color.lerp(heroInvestment, other.heroInvestment, t)!,
      heroWarning: Color.lerp(heroWarning, other.heroWarning, t)!,
      heroOnSurface: Color.lerp(heroOnSurface, other.heroOnSurface, t)!,
      heroOnSurfaceMuted: Color.lerp(
        heroOnSurfaceMuted,
        other.heroOnSurfaceMuted,
        t,
      )!,
      onInverseIncome: Color.lerp(onInverseIncome, other.onInverseIncome, t)!,
      onInverseExpense: Color.lerp(onInverseExpense, other.onInverseExpense, t)!,
      onInverseWarning: Color.lerp(onInverseWarning, other.onInverseWarning, t)!,
    );
  }
}

extension HopeThemeX on BuildContext {
  /// Paleta semântica do app.
  ///
  /// Cai para a paleta do brilho atual quando a extensão não está no tema —
  /// um componente do design system dentro de um `MaterialApp` sem
  /// [AppTheme] (testes, previews, telas isoladas) continua desenhando em vez
  /// de estourar em tempo de build.
  HopeColors get hopeColors {
    final theme = Theme.of(this);
    return theme.extension<HopeColors>() ??
        (theme.brightness == Brightness.dark
            ? HopeColors.dark
            : HopeColors.light);
  }

  bool get isCompact => MediaQuery.sizeOf(this).width < HopeBreakpoints.tablet;

  bool get isPhone => MediaQuery.sizeOf(this).width < HopeBreakpoints.foldable;

  bool get isDesktop =>
      MediaQuery.sizeOf(this).width >= HopeBreakpoints.desktop;

  /// O usuário pediu menos movimento no sistema operacional. Animações
  /// decorativas devem sumir; transições de estado viram cortes secos.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);

  /// Duração de animação já filtrada pela preferência de acessibilidade.
  Duration motion(Duration duration) =>
      reduceMotion ? Duration.zero : duration;

  /// Padding lateral do conteúdo conforme a largura disponível.
  double get pagePadding =>
      isCompact ? HopeSpacing.md : HopeSpacing.xxl;
}
