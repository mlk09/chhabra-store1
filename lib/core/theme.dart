import 'package:flutter/material.dart';

/// Brand colours: kirana green + saffron, warm and trustworthy.
class Brand {
  const Brand._();
  static const green = Color(0xFF1FA45A);
  static const greenDeep = Color(0xFF0E7A3E);
  static const saffron = Color(0xFFFF9933);
  static const saffronDeep = Color(0xFFE07A12);
  static const red = Color(0xFFE5484D);

  // Dark (default) surfaces
  static const ink = Color(0xFF0C110F);
  static const panel = Color(0xFF141B18);
  static const panelHigh = Color(0xFF1C2622);
  static const line = Color(0xFF2A3631);
}

const _font = 'Mukta';

/// Mukta's built-in line spacing is very tall (it has room for Devanagari
/// marks). A fixed height keeps every layout the same size on every phone.
const _lineHeight = 1.3;

TextTheme _withLineHeight(TextTheme t) => t.copyWith(
  displayLarge: t.displayLarge?.copyWith(height: _lineHeight),
  displayMedium: t.displayMedium?.copyWith(height: _lineHeight),
  displaySmall: t.displaySmall?.copyWith(height: _lineHeight),
  headlineLarge: t.headlineLarge?.copyWith(height: _lineHeight),
  headlineMedium: t.headlineMedium?.copyWith(height: _lineHeight),
  headlineSmall: t.headlineSmall?.copyWith(height: _lineHeight),
  titleLarge: t.titleLarge?.copyWith(height: _lineHeight),
  titleMedium: t.titleMedium?.copyWith(height: _lineHeight),
  titleSmall: t.titleSmall?.copyWith(height: _lineHeight),
  bodyLarge: t.bodyLarge?.copyWith(height: _lineHeight),
  bodyMedium: t.bodyMedium?.copyWith(height: _lineHeight),
  bodySmall: t.bodySmall?.copyWith(height: _lineHeight),
  labelLarge: t.labelLarge?.copyWith(height: _lineHeight),
  labelMedium: t.labelMedium?.copyWith(height: _lineHeight),
  labelSmall: t.labelSmall?.copyWith(height: _lineHeight),
);

/// [brand]: the shop's own colour (owner picks it); null = default kirana green.
ThemeData buildTheme(Brightness brightness, {Color? brand}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brand ?? Brand.green,
    brightness: brightness,
    primary: brand == null
        ? (dark ? const Color(0xFF3DDC84) : Brand.greenDeep)
        : (dark ? Color.lerp(brand, Colors.white, 0.35)! : brand),
    onPrimary: dark ? const Color(0xFF00210E) : Colors.white,
    secondary: Brand.saffron,
    onSecondary: const Color(0xFF2B1600),
    tertiary: Brand.saffronDeep,
    error: Brand.red,
    surface: dark ? Brand.ink : const Color(0xFFF7F8F5),
    surfaceContainerLowest: dark ? const Color(0xFF080B0A) : Colors.white,
    surfaceContainerLow: dark ? Brand.panel : Colors.white,
    surfaceContainer: dark ? Brand.panel : const Color(0xFFF0F2EE),
    surfaceContainerHigh: dark ? Brand.panelHigh : const Color(0xFFE8ECE7),
    surfaceContainerHighest: dark ? const Color(0xFF24302B) : const Color(0xFFDFE5DF),
    outlineVariant: dark ? Brand.line : const Color(0xFFD5DCD6),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: _font,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  final radius = BorderRadius.circular(14);
  return base.copyWith(
    textTheme: _withLineHeight(base.textTheme.apply(fontFamily: _font)).copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontFamily: _font,
        height: _lineHeight,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontFamily: _font,
        height: _lineHeight,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFamily: _font,
        height: _lineHeight,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 21, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(fontFamily: _font, fontSize: 15, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: _font, fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}
