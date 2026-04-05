/// WhisPaste ThemeData builder — constructs Material 3 themes from design tokens.
library;

import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';

/// Build the complete WhisPaste dark [ThemeData].
ThemeData wpDarkTheme() {
  final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: WpColorsDark.accent,
    onPrimary: WpColorsDark.background,
    primaryContainer: WpColorsDark.accentSubtle,
    onPrimaryContainer: WpColorsDark.accent,
    secondary: WpColorsDark.textSecondary,
    onSecondary: WpColorsDark.background,
    secondaryContainer: WpColorsDark.surfaceVariant,
    onSecondaryContainer: WpColorsDark.textPrimary,
    surface: WpColorsDark.surface,
    onSurface: WpColorsDark.textPrimary,
    surfaceContainerHighest: WpColorsDark.surfaceVariant,
    error: WpColorsDark.error,
    onError: WpColorsDark.background,
    outline: WpColorsDark.borderDefault,
    outlineVariant: WpColorsDark.borderSubtle,
    shadow: const Color(0xFF000000),
  );

  return _buildTheme(colorScheme, isDark: true);
}

/// Build the complete WhisPaste light [ThemeData].
ThemeData wpLightTheme() {
  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: WpColorsLight.accent,
    onPrimary: Colors.white,
    primaryContainer: WpColorsLight.accentSubtle,
    onPrimaryContainer: WpColorsLight.accent,
    secondary: WpColorsLight.textSecondary,
    onSecondary: Colors.white,
    secondaryContainer: WpColorsLight.surfaceVariant,
    onSecondaryContainer: WpColorsLight.textPrimary,
    surface: WpColorsLight.surface,
    onSurface: WpColorsLight.textPrimary,
    surfaceContainerHighest: WpColorsLight.surfaceVariant,
    error: WpColorsLight.error,
    onError: Colors.white,
    outline: WpColorsLight.borderDefault,
    outlineVariant: WpColorsLight.borderSubtle,
    shadow: const Color(0x33000000),
  );

  return _buildTheme(colorScheme, isDark: false);
}

ThemeData _buildTheme(ColorScheme colorScheme, {required bool isDark}) {
  final bg = isDark ? WpColorsDark.background : WpColorsLight.background;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: bg,
    fontFamily: null, // uses system font stack

    // Typography
    textTheme: _textTheme(colorScheme),

    // AppBar (custom title bar area, not system bar)
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: WpLayout.appBarHeight,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    ),

    // Cards — only for actionable items
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: WpRadius.borderMd,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),

    // Elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.lg,
          vertical: WpSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),

    // Icon buttons
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        padding: const EdgeInsets.all(WpSpacing.xs),
        minimumSize: const Size(36, 36),
        shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      ),
    ),

    // Input fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant,
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
      hintStyle: TextStyle(
        color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        fontSize: 14,
      ),
    ),

    // Switch / Toggle
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
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
        color: isDark ? WpColorsDark.surfaceVariant : WpColorsLight.textPrimary,
        borderRadius: WpRadius.borderSm,
      ),
      textStyle: TextStyle(
        color: isDark ? WpColorsDark.textPrimary : Colors.white,
        fontSize: 12,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),

    // Scrollbar
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted)
            .withValues(alpha: 0.4),
      ),
      radius: const Radius.circular(WpRadius.full),
      thickness: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return 6;
        return 4;
      }),
    ),

    // Snackbar (used for toasts)
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surface,
      contentTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderLg),
      elevation: 8,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

TextTheme _textTheme(ColorScheme cs) {
  return TextTheme(
    // Display → Page titles (24px / 700)
    headlineLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      letterSpacing: -0.5,
    ),
    // Heading → Section headers (18px / 600)
    headlineMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    ),
    // Subheading → Card titles (15px / 600)
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    ),
    // Body → Default text (14px / 400)
    bodyLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: cs.onSurface,
    ),
    // Body small → secondary text
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: cs.secondary,
    ),
    // Caption → metadata (12px / 400)
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: cs.secondary,
    ),
    // Micro → status chips (11px / 500)
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: cs.secondary,
      letterSpacing: 0.3,
    ),
  );
}
