import 'package:flutter/material.dart';

/// Tokens de design do HopeCash — compartilhados com o app para manter a mesma
/// identidade visual na retaguarda.
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

  static const light = HopeColors(
    income: Color(0xFF18865A),
    expense: Color(0xFFC44A4A),
    investment: Color(0xFF246BFE),
    card: Color(0xFF7C5CDB),
    warning: Color(0xFFC7831E),
    success: Color(0xFF18865A),
    heroStart: Color(0xFF101820),
    heroEnd: Color(0xFF1D2D3F),
    softBorder: Color(0xFFE7ECF1),
    positiveSurface: Color(0xFFEAF7F1),
    negativeSurface: Color(0xFFFBEDED),
    infoSurface: Color(0xFFEAF2FF),
  );

  static const dark = HopeColors(
    income: Color(0xFF55D69C),
    expense: Color(0xFFFF8E8E),
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
    );
  }
}

extension HopeThemeX on BuildContext {
  HopeColors get hopeColors => Theme.of(this).extension<HopeColors>()!;
  bool get isCompact => MediaQuery.sizeOf(this).width < HopeBreakpoints.tablet;
  bool get isDesktop =>
      MediaQuery.sizeOf(this).width >= HopeBreakpoints.desktop;
}
