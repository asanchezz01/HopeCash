import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../design_system/design_tokens.dart';

/// Identidade visual do HopeCash aplicada à retaguarda: verde-esperança como
/// cor semente, Material 3, modo claro e escuro. Mantém as mesmas cores e
/// tipografia do app, com pequenos ajustes de densidade para uso em desktop.
class AppTheme {
  AppTheme._();

  static const deepBlue = Color(0xFF0D1B2A);
  static const primaryBlue = Color(0xFF1B263B);
  static const hopeGreen = Color(0xFF1FA772);
  static const success = Color(0xFF18865A);
  static const skyBlue = Color(0xFF2E7CF6);
  static const warning = Color(0xFFC7831E);
  static const danger = Color(0xFFC44A4A);
  static const purple = Color(0xFF7C5CDB);
  static const gray900 = Color(0xFF111827);
  static const gray600 = Color(0xFF4B5563);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray100 = Color(0xFFF5F4F6);

  static const seed = hopeGreen;
  static const income = success;
  static const expense = danger;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: hopeGreen,
      secondary: skyBlue,
      tertiary: purple,
      error: danger,
      surface: isDark ? deepBlue : Colors.white,
    );
    final baseText = Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(
          fontFamily: 'Poppins',
          bodyColor: isDark ? Colors.white : deepBlue,
          displayColor: isDark ? Colors.white : deepBlue,
        );
    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(letterSpacing: 0),
      bodySmall: baseText.bodySmall?.copyWith(letterSpacing: 0),
    );
    final colors = isDark ? HopeColors.dark : HopeColors.light;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      // Densidade compacta: melhor aproveitamento em telas de desktop.
      visualDensity: VisualDensity.compact,
      extensions: <ThemeExtension<dynamic>>[colors],
      colorScheme: scheme.copyWith(
        primary: hopeGreen,
        onPrimary: Colors.white,
        secondary: skyBlue,
        tertiary: purple,
        error: danger,
        surface: isDark ? deepBlue : Colors.white,
        onSurface: isDark ? Colors.white : deepBlue,
        surfaceContainerLowest: isDark ? const Color(0xFF07111F) : Colors.white,
        surfaceContainerLow: isDark
            ? const Color(0xFF10253A)
            : const Color(0xFFF8FAFC),
        surfaceContainer: isDark ? const Color(0xFF132C44) : gray100,
        surfaceContainerHigh: isDark
            ? const Color(0xFF1A3652)
            : const Color(0xFFEFF4F8),
        outline: isDark ? const Color(0xFF496275) : gray300,
        outlineVariant: colors.softBorder,
      ),
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF07111F)
          : const Color(0xFFF7FAFC),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark
            ? const Color(0xFF07111F)
            : const Color(0xFFF7FAFC),
        foregroundColor: isDark ? Colors.white : deepBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: isDark ? Colors.white : deepBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: deepBlue.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.md),
          side: BorderSide(color: colors.softBorder),
        ),
        color: isDark ? const Color(0xFF10253A) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: BorderSide(color: colors.softBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: const BorderSide(color: hopeGreen, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: const BorderSide(color: danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF10253A) : const Color(0xFFFFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.sm,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: hopeGreen,
          foregroundColor: Colors.white,
          // Altura mínima de 48; largura mínima 64 (padrão Material). NÃO usar
          // Size.fromHeight (largura = infinito): estoura "infinite width" quando
          // o botão é filho não-flexível de um Row, ex.: ações do PageHeader.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HopeRadius.sm),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: hopeGreen,
          side: const BorderSide(color: hopeGreen),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HopeRadius.sm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.pill),
          side: BorderSide(color: colors.softBorder),
        ),
        selectedColor: hopeGreen.withValues(alpha: 0.16),
        checkmarkColor: hopeGreen,
        labelStyle: TextStyle(color: isDark ? Colors.white : deepBlue),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: HopeSpacing.sm,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.xs,
        ),
        iconColor: isDark ? Colors.white70 : primaryBlue,
        titleTextStyle: textTheme.titleSmall?.copyWith(
          color: isDark ? Colors.white : deepBlue,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: isDark ? Colors.white70 : gray600,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelLarge?.copyWith(
          color: isDark ? Colors.white70 : gray600,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? Colors.white : deepBlue,
        ),
        dividerThickness: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: hopeGreen,
        foregroundColor: Colors.white,
        elevation: isDark ? 0 : 6,
        shape: const CircleBorder(),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF07111F) : Colors.white,
        elevation: 0,
        indicatorColor: hopeGreen.withValues(alpha: 0.12),
        selectedIconTheme: const IconThemeData(color: hopeGreen),
        unselectedIconTheme: IconThemeData(
          color: isDark ? Colors.white70 : primaryBlue,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: hopeGreen,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: isDark ? Colors.white70 : gray600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF10253A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? Colors.white : deepBlue,
        contentTextStyle: TextStyle(color: isDark ? deepBlue : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.softBorder,
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
