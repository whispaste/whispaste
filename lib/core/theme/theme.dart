/// WhisPaste ThemeData builder — constructs Material 3 themes from design tokens.
///
/// Premium aesthetic: clean surfaces, crisp typography, refined spacing,
/// warm tonal gradients. No glow effects — depth via layered surfaces,
/// clean soft shadows, and chromatic temperature, not alpha-blended light.
library;

import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';

/// Build the complete WhisPaste dark [ThemeData].
ThemeData wpDarkTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: WpColors.accent,
    onPrimary: WpColors.background,
    primaryContainer: WpColors.accentSubtle,
    onPrimaryContainer: WpColors.accent,
    secondary: WpColors.textSecondary,
    onSecondary: WpColors.background,
    secondaryContainer: WpColors.surfaceVariant,
    onSecondaryContainer: WpColors.textPrimary,
    surface: WpColors.surface,
    onSurface: WpColors.textPrimary,
    surfaceContainerHighest: WpColors.surfaceVariant,
    error: WpColors.error,
    onError: WpColors.background,
    outline: WpColors.borderDefault,
    outlineVariant: WpColors.borderSubtle,
    shadow: Color(0xFF000000),
  );

  return _buildTheme(colorScheme);
}

/// Turns the [ColorScheme] above into the full [ThemeData].
///
/// `wpLightTheme()` stood beside [wpDarkTheme] here until 2026-08-11 and is
/// gone with the light stack. It had already stopped being a second theme:
/// once `WpColorsLight` went, every surface it named resolved through
/// [WpColors] to the same dark tokens, and what still differed was four
/// literals — `Colors.white` where dark used `WpColors.background`, and a
/// 10 %-black shadow — i.e. white text painted on dark surfaces. It was not
/// a light theme any more, it was a broken dark one.
///
/// This stays split out from [wpDarkTheme] even with one caller left. The
/// split is not a leftover of the theme pair: it separates the colour
/// contract (the [ColorScheme] literal, which is the part a reader looks up)
/// from ~240 lines of component styling derived from it. Merging them would
/// bury the first in the second.
ThemeData _buildTheme(ColorScheme colorScheme) {
  const bg = WpColors.background;
  // Build textTheme first so component themes can reference it (e.g. snackBar).
  final textTheme = _textTheme(colorScheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: bg,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Helvetica Neue', 'Arial', 'sans-serif'],

    // Typography
    textTheme: textTheme,

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: WpLayout.appBarHeight,
      titleTextStyle: TextStyle(
        fontSize: WpTypography.subheading,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
        letterSpacing: -0.2,
      ),
    ),

    // Cards
    cardTheme: CardThemeData(
      color: WpColors.surfaceElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: WpRadius.borderMd,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),

    // These four theme blocks (elevated/filled/outlined/text) style the raw
    // Material button classes directly. App code itself never calls those
    // classes anymore — every user-triggered action routes through
    // WpButton (see its library doc comment) — but Material's own internal
    // widgets still build them under the hood (e.g. DatePicker/TimePicker
    // OK-Cancel, SnackBar actions), so these stay as the safety net that
    // keeps those borrowed controls on-brand instead of falling back to
    // Material's stock look.

    // Elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xl,
          vertical: WpSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
        textStyle: const TextStyle(
          fontSize: WpTypography.body,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          // Explicit fontFamily ensures buttons render correctly in tests.
          // Flutter's _ButtonStyleButton replaces DefaultTextStyle entirely,
          // so the ThemeData.fontFamily cascade is severed without this.
          fontFamily: 'Inter',
        ),
      ),
    ),

    // Filled buttons — Material 3 defaults to a fully-rounded `StadiumBorder`
    // for this variant with no override; every dialog's primary CTA uses
    // FilledButton, so without this the pill shape broke from the rest of
    // the system's WpRadius.sm corners.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xl,
          vertical: WpSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
        textStyle: const TextStyle(
          fontSize: WpTypography.body,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // Outlined buttons — same StadiumBorder gap as FilledButton above.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xl,
          vertical: WpSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
        textStyle: const TextStyle(
          fontSize: WpTypography.body,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // Text buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.xs,
        ),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
        textStyle: const TextStyle(
          fontSize: WpTypography.body,
          fontWeight: FontWeight.w500,
          fontFamily: 'Inter',
        ),
      ),
    ),

    // Icon buttons
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        padding: const EdgeInsets.all(WpSpacing.xs),
        minimumSize: const Size(
          WpLayout.minTouchTarget,
          WpLayout.minTouchTarget,
        ),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      ),
    ),

    // Input fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WpColors.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: WpRadius.borderSm,
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: WpRadius.borderSm,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: WpRadius.borderSm,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      hintStyle: const TextStyle(
        color: WpColors.textMuted,
        fontSize: WpTypography.body,
      ),
    ),

    // Switch / Toggle
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return WpColors.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary.withValues(alpha: 0.3);
        }
        return colorScheme.outlineVariant;
      }),
    ),

    // Divider
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // Tooltip
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: WpColors.surfaceElevated,
        borderRadius: WpRadius.borderSm,
        border: Border.all(color: WpColors.borderDefault),
      ),
      textStyle: const TextStyle(
        color: WpColors.textPrimary,
        fontSize: WpTypography.small,
        fontWeight: FontWeight.w500,
      ),
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
    ),

    // Scrollbar
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        (WpColors.textMuted).withValues(alpha: 0.3),
      ),
      radius: const Radius.circular(WpRadius.full),
      thickness: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return 6;
        return 3;
      }),
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: WpColors.surfaceElevated,
      contentTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: WpColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderLg),
      elevation: 8,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: WpTypography.title,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
  );
}

/// WhisPaste type scale — all roles mapped to SF-grade tracking + line-height.
///
/// Design tokens, Code = SSOT. Inter is the bundled app font (OFL 4.001);
/// it renders identically on Windows, macOS and Linux.
///
/// | Role           | Size | Weight | LS    | LH  |
/// |----------------|------|--------|-------|-----|
/// | headlineLarge  | 22   | 700    | -0.60 | 1.2 |
/// | headlineMedium | 16   | 600    | -0.35 | 1.3 |
/// | titleLarge     | 17   | 600    | -0.20 | 1.3 |
/// | titleMedium    | 14   | 600    | -0.20 | —   |
/// | titleSmall     | 13   | 600    | -0.10 | 1.4 |
/// | bodyLarge      | 13   | 400    |  0    | 1.5 |
/// | bodyMedium     | 13   | 400    |  0    | 1.5 |
/// | bodySmall      | 12   | 400    |  0    | 1.4 |
/// | labelLarge     | 16   | 700    | -0.30 | —   |
/// | labelMedium    | 13   | 500    |  0    | 1.4 |
/// | labelSmall     | 11   | 500    | +0.20 | —   |
TextTheme _textTheme(ColorScheme cs) {
  return TextTheme(
    // Display → Page titles (22px / 700)
    headlineLarge: TextStyle(
      fontSize: WpTypography.headline,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      letterSpacing: -0.6,
      height: 1.2,
    ),
    // Heading → Section headers (16px / 600)
    headlineMedium: TextStyle(
      fontSize: WpTypography.heading,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      letterSpacing: -0.35,
      height: 1.3,
    ),
    // Dialog / panel title (17px / 600) — WpDialog, review prompts, export picker
    titleLarge: TextStyle(
      fontSize: WpTypography.title,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      letterSpacing: -0.2,
      height: 1.3,
    ),
    // Subheading → Card titles (14px / 600)
    titleMedium: TextStyle(
      fontSize: WpTypography.subheading,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      letterSpacing: -0.2,
    ),
    // Form field label / section subheading (13px / 600)
    titleSmall: TextStyle(
      fontSize: WpTypography.body,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      letterSpacing: -0.1,
      height: 1.4,
    ),
    // Body → Default text (13px / 400)
    bodyLarge: TextStyle(
      fontSize: WpTypography.body,
      fontWeight: FontWeight.w400,
      color: cs.onSurface,
      height: 1.5,
    ),
    // Body secondary
    bodyMedium: TextStyle(
      fontSize: WpTypography.body,
      fontWeight: FontWeight.w400,
      color: cs.secondary,
      height: 1.5,
    ),
    // Caption → metadata (12px / 400)
    bodySmall: TextStyle(
      fontSize: WpTypography.small,
      fontWeight: FontWeight.w400,
      color: cs.secondary,
      height: 1.4,
    ),
    // Button label / CTA (16px / 700) — WpHeroButton, SF-style tight tracking
    labelLarge: TextStyle(
      fontSize: WpTypography.heading,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      letterSpacing: -0.3,
    ),
    // Toast / snackbar message (13px / 500)
    labelMedium: TextStyle(
      fontSize: WpTypography.body,
      fontWeight: FontWeight.w500,
      color: cs.onSurface,
      letterSpacing: 0,
      height: 1.4,
    ),
    // Micro → status chips (11px / 500)
    labelSmall: TextStyle(
      fontSize: WpTypography.caption,
      fontWeight: FontWeight.w500,
      color: cs.secondary,
      letterSpacing: 0.2,
    ),
  );
}
