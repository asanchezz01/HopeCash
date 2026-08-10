import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../design_system/design_tokens.dart';

/// Identidade visual do HopeCash: verde-esperança como cor de marca sobre uma
/// base azul-petróleo, Material 3, modo claro e escuro.
///
/// Regra de contraste: toda cor usada como **texto** foi verificada contra o
/// fundo em que aparece (mínimo 4,5:1). Por isso o verde de marca tem duas
/// versões — uma profunda para o tema claro e uma luminosa para o escuro. Um
/// único tom não consegue passar nos dois.
class AppTheme {
  AppTheme._();

  static const deepBlue = Color(0xFF0D1B2A);
  static const primaryBlue = Color(0xFF1B263B);

  /// Verde de marca do tema claro. Texto branco sobre ele: 5,0:1.
  static const hopeGreen = Color(0xFF0D7F57);

  /// Verde de marca do tema escuro. Texto escuro sobre ele: 10,1:1.
  static const hopeGreenBright = Color(0xFF3DD598);

  static const success = Color(0xFF10714A);
  static const skyBlue = Color(0xFF1F5FE0);
  static const warning = Color(0xFFA2600B);
  static const danger = Color(0xFFB03A3A);
  static const purple = Color(0xFF6B4CC9);
  static const gray900 = Color(0xFF111827);
  static const gray600 = Color(0xFF4B5563);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray100 = Color(0xFFF5F4F6);

  static const seed = hopeGreen;
  static const income = success;
  static const expense = danger;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  /// Escala tipográfica explícita.
  ///
  /// Não é a escala padrão do Material: títulos grandes recebem tracking
  /// negativo (senão parecem soltos) e os rótulos pequenos recebem tracking
  /// positivo (senão fecham demais). O app mostra muito texto de apoio em
  /// 11–13px, então essa faixa foi calibrada primeiro.
  static TextTheme _textTheme(Color onSurface) {
    TextStyle style(
      double size,
      double height,
      FontWeight weight,
      double tracking,
    ) => TextStyle(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: tracking,
      color: onSurface,
    );

    return TextTheme(
      displayLarge: style(48, 1.06, FontWeight.w800, -1.4),
      displayMedium: style(40, 1.08, FontWeight.w800, -1.1),
      displaySmall: style(32, 1.10, FontWeight.w800, -0.8),
      headlineLarge: style(28, 1.16, FontWeight.w800, -0.6),
      headlineMedium: style(24, 1.20, FontWeight.w700, -0.4),
      headlineSmall: style(20, 1.26, FontWeight.w700, -0.3),
      titleLarge: style(20, 1.30, FontWeight.w700, -0.2),
      titleMedium: style(16, 1.36, FontWeight.w700, -0.1),
      titleSmall: style(14, 1.40, FontWeight.w600, 0),
      bodyLarge: style(16, 1.50, FontWeight.w400, 0),
      bodyMedium: style(14, 1.46, FontWeight.w400, 0),
      bodySmall: style(12.5, 1.40, FontWeight.w400, 0.1),
      labelLarge: style(14, 1.20, FontWeight.w600, 0.1),
      labelMedium: style(12, 1.25, FontWeight.w600, 0.2),
      labelSmall: style(11, 1.25, FontWeight.w700, 0.6),
    );
  }

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? HopeColors.dark : HopeColors.light;

    final brand = isDark ? hopeGreenBright : hopeGreen;
    final onBrand = isDark ? const Color(0xFF04231A) : Colors.white;
    final onSurface = isDark ? Colors.white : deepBlue;
    // Texto secundário com contraste verificado: 4,8:1 no claro, 5,9:1 no
    // escuro. O cinza anterior (gray600 sobre branco) ficava no limite e
    // sumia em telas com brilho baixo.
    final onSurfaceVariant = isDark
        ? const Color(0xFFA9B6C3)
        : const Color(0xFF52657A);
    final scaffold = isDark ? const Color(0xFF07111F) : const Color(0xFFF6F8FA);
    final surface = isDark ? const Color(0xFF10202F) : Colors.white;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: onBrand,
      primaryContainer: isDark
          ? const Color(0xFF0B3D2C)
          : const Color(0xFFD9F0E5),
      onPrimaryContainer: isDark
          ? const Color(0xFFB7EFD4)
          : const Color(0xFF063824),
      secondary: colors.investment,
      onSecondary: isDark ? const Color(0xFF06172F) : Colors.white,
      secondaryContainer: colors.infoSurface,
      onSecondaryContainer: isDark
          ? const Color(0xFFCFE0FF)
          : const Color(0xFF10305F),
      tertiary: colors.card,
      onTertiary: isDark ? const Color(0xFF1B1136) : Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF2C2050)
          : const Color(0xFFEDE8FC),
      onTertiaryContainer: isDark
          ? const Color(0xFFDDD3FF)
          : const Color(0xFF2A1C57),
      error: colors.expense,
      onError: isDark ? const Color(0xFF3B0D0D) : Colors.white,
      errorContainer: colors.negativeSurface,
      onErrorContainer: isDark
          ? const Color(0xFFFFD6D6)
          : const Color(0xFF6B1C1C),
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      surfaceContainerLowest: isDark ? const Color(0xFF0A1725) : Colors.white,
      surfaceContainerLow: isDark
          ? const Color(0xFF0E1E2D)
          : const Color(0xFFFAFCFD),
      surfaceContainer: isDark
          ? const Color(0xFF132638)
          : const Color(0xFFF1F5F8),
      surfaceContainerHigh: isDark
          ? const Color(0xFF182F44)
          : const Color(0xFFE9EFF4),
      surfaceContainerHighest: isDark
          ? const Color(0xFF1E3850)
          : const Color(0xFFE1E9F0),
      outline: isDark ? const Color(0xFF56718A) : const Color(0xFF7C8FA3),
      outlineVariant: colors.softBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? Colors.white : deepBlue,
      onInverseSurface: isDark ? deepBlue : Colors.white,
      inversePrimary: isDark ? hopeGreen : hopeGreenBright,
    );

    final textTheme = _textTheme(onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[colors],
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: onSurface),
        iconTheme: IconThemeData(color: onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: onSurfaceVariant, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: deepBlue.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.md),
          side: BorderSide(color: colors.softBorder),
        ),
        color: surface,
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
          borderSide: BorderSide(color: brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
          borderSide: BorderSide(
            color: colors.softBorder.withValues(alpha: 0.6),
          ),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF152838) : Colors.white,
        labelStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => (textTheme.labelLarge ?? const TextStyle()).copyWith(
            color: states.contains(WidgetState.error)
                ? scheme.error
                : states.contains(WidgetState.focused)
                ? brand
                : onSurfaceVariant,
          ),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: onSurfaceVariant.withValues(alpha: 0.7),
        ),
        helperStyle: textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: scheme.error,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.focused) ? brand : onSurfaceVariant,
        ),
        suffixIconColor: onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.sm,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: onBrand,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.10),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: const Size.fromHeight(kHopeMinTapTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HopeRadius.sm),
          ),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          minimumSize: const Size.fromHeight(kHopeMinTapTarget),
          side: BorderSide(color: brand.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HopeRadius.sm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          minimumSize: const Size(0, kHopeMinTapTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HopeRadius.xs),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(kHopeMinTapTarget),
          foregroundColor: onSurfaceVariant,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          side: WidgetStatePropertyAll(BorderSide(color: colors.softBorder)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : onSurfaceVariant,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : Colors.transparent,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.pill),
          side: BorderSide(color: colors.softBorder),
        ),
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge?.copyWith(color: onSurfaceVariant),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        iconTheme: IconThemeData(color: onSurfaceVariant, size: 18),
        padding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.xs,
          vertical: 6,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: HopeSpacing.sm,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.md,
          vertical: HopeSpacing.xs,
        ),
        iconColor: onSurfaceVariant,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: onSurfaceVariant,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: onBrand,
        elevation: isDark ? 0 : 6,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? const Color(0xFF0C1D2C) : Colors.white,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => (textTheme.labelMedium ?? const TextStyle()).copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? brand
                : onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: brand,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.38),
        dragHandleColor: scheme.outline,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HopeRadius.xl)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: scheme.inversePrimary,
        insetPadding: const EdgeInsets.all(HopeSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HopeRadius.sm),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(
          horizontal: HopeSpacing.xs,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(HopeRadius.xs),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.softBorder,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? brand
              : scheme.surfaceContainerHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? brand : scheme.outline,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: brand,
        selectionColor: brand.withValues(alpha: 0.28),
        selectionHandleColor: brand,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
