/// WhisPaste ThemeData builder — constructs Material 3 themes from design tokens.
///
/// One builder for every appearance (ADR 0016, AR-21): [wpThemeFor] turns a
/// [WpThemeColors] set into [ThemeData]; [wpLightTheme] and [wpDarkTheme]
/// are its two fixed uses.
library;

import 'package:flutter/material.dart';

import 'colors.dart';
import 'generated/wp_tokens.g.dart';
import 'tokens.dart';

/// UI face (ADR 0018). Neither Hanken nor Bricolage covers Cyrillic or
/// Hebrew, so the bundled Inter is the first fallback.
const String kWpUiFont = 'Hanken Grotesk';

/// Display face for page and section titles (ADR 0018).
const String kWpDisplayFont = 'Bricolage Grotesque';

const List<String> kWpFontFallback = [
  'Inter',
  'Helvetica Neue',
  'Segoe UI',
  'Arial',
  'sans-serif',
];

/// Light journal [ThemeData] (the light appearance; navy is the default).
ThemeData wpLightTheme() => wpThemeFor(wpLightColors);

/// Navy [ThemeData]: dark appearance and the stage-only surfaces.
ThemeData wpDarkTheme() => wpThemeFor(wpDarkColors);

/// [ThemeData] for one colour set (AR-21). The navy set paints its content
/// light; only its frame is navy, which the shell reads via `WpColors.frame`.
ThemeData wpThemeFor(WpThemeColors c) {
  final colorScheme = ColorScheme(
    brightness: c.brightness,
    primary: c.action,
    onPrimary: c.onAction,
    primaryContainer: c.accentSubtle,
    onPrimaryContainer: c.accent,
    secondary: c.textSecondary,
    onSecondary: c.surfaceElevated,
    secondaryContainer: c.surfaceVariant,
    onSecondaryContainer: c.textPrimary,
    tertiary: c.accent,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textMuted,
    surfaceContainerHigh: c.surfaceElevated,
    surfaceContainerHighest: c.surfaceVariant,
    error: c.error,
    onError: c.onError,
    outline: c.borderDefault,
    outlineVariant: c.borderSubtle,
    shadow: c.brightness == Brightness.dark
        ? const Color(0xFF000000)
        : const Color(0x1F0B122A),
    scrim: const Color(0x660B122A),
  );

  return _buildTheme(colorScheme, background: c.background, c: c);
}

/// Turns a [ColorScheme] into the full [ThemeData]. Reads colours only
/// from [colorScheme] so the same component styling serves both surfaces.
ThemeData _buildTheme(
  ColorScheme colorScheme, {
  required Color background,
  required WpThemeColors c,
}) {
  final bg = background;
  final elevated = colorScheme.surfaceContainerHigh;
  final muted = colorScheme.onSurfaceVariant;
  // Build textTheme first so component themes can reference it (e.g. snackBar).
  final textTheme = _textTheme(colorScheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: bg,
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,

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
      color: elevated,
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
          fontFamily: kWpUiFont,
          fontFamilyFallback: kWpFontFallback,
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
          fontFamily: kWpUiFont,
          fontFamilyFallback: kWpFontFallback,
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
          fontFamily: kWpUiFont,
          fontFamilyFallback: kWpFontFallback,
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
          fontFamily: kWpUiFont,
          fontFamilyFallback: kWpFontFallback,
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
      fillColor: colorScheme.surfaceContainerHighest,
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
      hintStyle: TextStyle(color: muted, fontSize: WpTypography.body),
    ),

    // Switch / Toggle (ticket §4): petrol track when on, white thumb in both
    // states. The off track is the muted text tone rather than the hairline
    // border: a border sits at 1.3–1.8:1 against its surface, a switch needs
    // 3:1 as a UI component boundary (UX-008).
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(WpPalette.white),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.accent;
        return c.switchTrackOff;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),

    // Checkbox theme (ticket §4): 4 px corner, petrol fill with a contrasting tick.
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WpRadiusTokens.xs),
      ),
      side: BorderSide(color: c.borderDefault, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(
        c.brightness == Brightness.dark ? c.onAction : WpPalette.white,
      ),
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
        color: c.floatingSurface,
        borderRadius: WpRadius.borderSm,
        border: Border.all(color: c.cardEdgeHighlight),
      ),
      // Explicit family: a tooltip's text is not merged with DefaultTextStyle,
      // so it would otherwise fall back to the platform default.
      textStyle: textTheme.labelMedium?.copyWith(
        color: c.textPrimary,
        fontFamily: kWpUiFont,
        fontFamilyFallback: kWpFontFallback,
      ),
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
    ),

    // Popup menus share the floating-surface family of tooltips and dialogs.
    popupMenuTheme: PopupMenuThemeData(
      color: c.floatingSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: WpRadius.borderSm,
        side: BorderSide(color: c.cardEdgeHighlight),
      ),
      textStyle: textTheme.bodyMedium?.copyWith(
        color: c.textPrimary,
        fontFamily: kWpUiFont,
        fontFamilyFallback: kWpFontFallback,
      ),
    ),

    // Scrollbar
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(muted.withValues(alpha: 0.3)),
      radius: const Radius.circular(WpRadius.full),
      thickness: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return 6;
        return 3;
      }),
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: elevated,
      contentTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: elevated,
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
/// Hanken Grotesk for UI text, Bricolage Grotesque for the three title
/// roles (ADR 0018); all bundled, so they render identically on Windows,
/// macOS and Linux. Sizes are unchanged until the shell rework (ticket/21).
///
/// | Role           | Size | Weight | LS    | LH  |
/// |----------------|------|--------|-------|-----|
/// | headlineLarge  | 22   | 700    | -0.60 | 1.2 |
/// | headlineMedium | 16   | 600    | -0.35 | 1.3 |
/// | titleLarge     | 17   | 600    | -0.20 | 1.3 |
/// | titleMedium    | 14   | 600    | -0.20 | 1.2 |
/// | titleSmall     | 13   | 600    | -0.10 | 1.4 |
/// | bodyLarge      | 13   | 400    |  0    | 1.5 |
/// | bodyMedium     | 13   | 400    |  0    | 1.5 |
/// | bodySmall      | 12   | 400    |  0    | 1.4 |
/// | labelLarge     | 16   | 700    | -0.30 | 1.2 |
/// | labelMedium    | 13   | 500    |  0    | 1.4 |
/// | labelSmall     | 11   | 500    | +0.20 | 1.2 |
///
/// Two Hanken stages beyond Material's roles live in [WpTextStyles]: `lead`
/// (22/700, 1.3) and `figure` (28/700, 1.15, tabular). Bricolage stays with
/// the page title ([WpPageHeader]) and the section title (`WpSection`).
TextTheme _textTheme(ColorScheme cs) {
  return TextTheme(
    // Display → Page titles (22px / 700)
    headlineLarge: TextStyle(
      fontFamily: kWpDisplayFont,
      fontFamilyFallback: kWpFontFallback,
      fontSize: WpTypography.headline,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      letterSpacing: -0.6,
      height: 1.2,
    ),
    // Heading → Section headers (16px / 600)
    headlineMedium: TextStyle(
      fontFamily: kWpDisplayFont,
      fontFamilyFallback: kWpFontFallback,
      fontSize: WpTypography.heading,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      letterSpacing: -0.35,
      height: 1.3,
    ),
    // Dialog / panel title (17px / 600) — WpDialog, review prompts, export picker
    titleLarge: TextStyle(
      fontFamily: kWpDisplayFont,
      fontFamilyFallback: kWpFontFallback,
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
      // Pinned rather than left to the face's own line box (Hanken's is
      // 1.30 em), so layout budgets do not depend on font metrics.
      height: 1.2,
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
      // Pinned rather than left to the face's own line box (Hanken's is
      // 1.30 em), so layout budgets do not depend on font metrics.
      height: 1.2,
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
      // Pinned rather than left to the face's own line box (Hanken's is
      // 1.30 em), so layout budgets do not depend on font metrics.
      height: 1.2,
    ),
  );
}

/// Hanken stages the Material [TextTheme] has no role for. Sizes come from
/// [WpTypeScaleTokens], colours from the active set via [WpColors].
abstract final class WpTextStyles {
  /// The one page-title role: [WpPageHeader] and the onboarding page headings
  /// both use it, so a page title looks the same everywhere.
  static TextStyle get pageTitle => TextStyle(
    fontFamily: kWpDisplayFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypeScaleTokens.pageTitle,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.6,
    color: WpColors.textPrimary,
  );

  /// A sentence that opens a page under its title (the Overview greeting).
  static TextStyle get lead => TextStyle(
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypeScaleTokens.lead,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.3,
    color: WpColors.textPrimary,
  );

  /// The value of a key figure. Tabular digits keep a counting number from
  /// jittering sideways.
  /// The title of a row in a card or list (first steps, hints, recordings):
  /// 15/22, medium, primary text.
  static TextStyle get rowTitle => TextStyle(
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypography.rowTitle,
    fontWeight: FontWeight.w500,
    height: 22 / WpTypography.rowTitle,
    color: WpColors.textPrimary,
  );

  /// The explanation under a row title and row metadata: 13/18, secondary text.
  static TextStyle get rowNote => TextStyle(
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypography.body,
    height: 18 / WpTypography.body,
    color: WpColors.textSecondary,
  );

  static TextStyle get figure => TextStyle(
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypeScaleTokens.figure,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.15,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: WpColors.textPrimary,
  );
}
