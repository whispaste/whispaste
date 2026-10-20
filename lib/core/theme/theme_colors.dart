/// Runtime colour sets behind [WpColors] (ADR 0016, AR-21).
///
/// Three appearance modes share one shape: light (journal), dark
/// (navy working area) and navy (website language: navy frame, light
/// content). Existing call sites keep reading `WpColors.x`; the getters
/// resolve against the active set, which the app switches at runtime and
/// then rebuilds the tree. Light values resolve to [WpPalette] primitives
/// (i.e. `design-tokens/*.tokens.json`); dark reuses the navy stage palette.
///
/// Role split the dark palette did not need: [WpThemeColors.accent] is petrol
/// on light (text, icons, indicators, >= 4.5:1 on every light ground) while
/// [WpThemeColors.action] is the brand cyan used as a filled primary surface
/// with navy [WpThemeColors.onAction] text.
library;

import 'package:flutter/widgets.dart';

import 'colors_dark.dart';
import 'generated/wp_tokens.g.dart';

/// One complete colour set. Field names match the legacy `WpColors` roles.
@immutable
final class WpThemeColors {
  const WpThemeColors({
    required this.brightness,
    this.frameOverride,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceVariant,
    required this.hover,
    required this.hoverTransparent,
    required this.active,
    required this.borderSubtle,
    required this.borderDefault,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.switchTrackOff,
    required this.selectionBorder,
    required this.accent,
    required this.accentHover,
    required this.action,
    required this.onAction,
    required this.accentSubtle,
    required this.accentChipFill,
    required this.accentChipFillHover,
    required this.accentMiniTagFill,
    required this.accentBorder30,
    required this.accentButtonFill,
    required this.accentActiveFill,
    required this.accentBadgeFill,
    required this.accentBorder20,
    required this.accentRowHover,
    required this.surfaceChipFill,
    required this.surfaceMutedFill,
    required this.cardFill,
    required this.cardFillElevated,
    required this.cardEdgeHighlight,
    required this.floatingSurface,
    required this.decorativeGlyphWash,
    required this.success,
    required this.warning,
    required this.error,
    required this.onError,
    required this.errorRowHover,
    required this.errorButtonFill,
    required this.errorActiveFill,
    required this.errorBorder20,
    required this.errorBorder30,
    required this.mutedRowHover,
    required this.mutedActiveFill,
    required this.successActiveFill,
    required this.warningActiveFill,
    required this.accentLocatorRing,
    required this.recordingAccent,
    required this.recordingAccentGradient,
    required this.warningOrange,
    required this.warningOrangeBadgeFill,
    required this.warningOrangeBadgeBorder,
    required this.errorRed,
    required this.errorRedHover,
    required this.surfaceGradient,
    required this.warmSurfaceGradient,
    required this.frameGradient,
    required this.accentGradient,
    required this.accentWarmGradient,
    required this.navChipGradient,
    required this.navChipGradientHover,
    required this.navPillActiveGradient,
    required this.highlight,
    required this.highlightSoft,
    required this.highlightText,
    required this.primaryRecordFill,
    required this.primaryRecordHover,
    required this.onPrimaryRecord,
    required this.ctaFill,
    required this.ctaHover,
    required this.ctaPressed,
    required this.onCta,
    required this.controlEdge,
    required this.warningOrangeText,
    required this.shadow,
  });

  final Brightness brightness;

  /// Colours for the window frame (title bar, sidebar). Only the navy mode
  /// sets one; elsewhere the frame shares the content colours.
  final WpThemeColors? frameOverride;

  WpThemeColors get frame => frameOverride ?? this;

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceVariant;
  final Color hover;
  final Color hoverTransparent;
  final Color active;
  final Color borderSubtle;
  final Color borderDefault;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Off-state switch track. Value mirrors the `switch-track-off` token
  /// (app.tokens.json), pinned to the generated palette by the switch spec.
  final Color switchTrackOff;

  /// Unselected colour swatch boundary (app.tokens.json `selection-border`).
  final Color selectionBorder;
  final Color accent;
  final Color accentHover;
  final Color action;
  final Color onAction;
  final Color accentSubtle;
  final Color accentChipFill;
  final Color accentChipFillHover;
  final Color accentMiniTagFill;
  final Color accentBorder30;
  final Color accentButtonFill;
  final Color accentActiveFill;
  final Color accentBadgeFill;
  final Color accentBorder20;
  final Color accentRowHover;
  final Color surfaceChipFill;
  final Color surfaceMutedFill;
  final Color cardFill;
  final Color cardFillElevated;
  final Color cardEdgeHighlight;
  final Color floatingSurface;
  final Color decorativeGlyphWash;
  final Color success;
  final Color warning;
  final Color error;
  final Color onError;
  final Color errorRowHover;
  final Color errorButtonFill;
  final Color errorActiveFill;
  final Color errorBorder20;
  final Color errorBorder30;
  final Color mutedRowHover;
  final Color mutedActiveFill;
  final Color successActiveFill;
  final Color warningActiveFill;
  final Color accentLocatorRing;
  final Color recordingAccent;
  final LinearGradient recordingAccentGradient;
  final Color warningOrange;
  final Color warningOrangeBadgeFill;
  final Color warningOrangeBadgeBorder;
  final Color errorRed;
  final Color errorRedHover;
  final LinearGradient surfaceGradient;
  final LinearGradient warmSurfaceGradient;
  final LinearGradient frameGradient;
  final LinearGradient accentGradient;
  final LinearGradient accentWarmGradient;
  final LinearGradient navChipGradient;
  final LinearGradient navChipGradientHover;
  final LinearGradient navPillActiveGradient;

  /// Amber marker (favourite star, tag fill source): the warm accent for marks
  /// and hints. Deliberate accent surfaces (dock CTA, button colour option) use
  /// amber too, always under WCAG AA.
  final Color highlight;

  /// Amber chip background behind [highlightText].
  final Color highlightSoft;

  /// Amber text on [highlightSoft] (light: amber 800, dark: amber 400).
  final Color highlightText;

  /// Fill of the primary record button (dock dictate, start page). Cyan in
  /// light and dark; amber in navy, the one place amber is a fill. Text and
  /// icon on it use [onPrimaryRecord].
  final Color primaryRecordFill;

  /// Hover fill of the primary record button.
  final Color primaryRecordHover;

  /// Icon and label colour on [primaryRecordFill] (navy 900 in every mode).
  final Color onPrimaryRecord;

  /// Flat fill of the hero call to action (onboarding "Weiter"). Amber in
  /// every appearance; the same primitive as the navy dictate fill, but a
  /// separate role so the light and dark dock keep their cyan (UIA-CMP-01).
  final Color ctaFill;

  /// Hover fill of the hero call to action.
  final Color ctaHover;

  /// Pressed fill of the hero call to action.
  final Color ctaPressed;

  /// Label colour on [ctaFill], [ctaHover] and [ctaPressed] (navy 900).
  final Color onCta;

  /// Edge of an input or outlined button at rest. At least 3:1 against the
  /// surface it sits on (WCAG 1.4.11), so the control is findable without
  /// the focus ring.
  final Color controlEdge;

  /// Warning text (not the glyph or rim) on [warningOrangeBadgeFill].
  final Color warningOrangeText;

  /// Elevation shadow for raised rows and menus (navy 12 % on light).
  final Color shadow;
}

/// Light journal.
const WpThemeColors wpLightColors = WpThemeColors(
  brightness: Brightness.light,
  background: WpPalette.glacier100,
  surface: WpPalette.glacier50,
  surfaceElevated: WpPalette.white,
  surfaceVariant: WpPalette.glacier100,
  hover: Color(0x0F0B122A),
  hoverTransparent: Color(0x000B122A),
  active: WpPalette.glacier200,
  borderSubtle: Color(0x1F0B122A),
  borderDefault: WpPalette.glacier300,
  textPrimary: WpPalette.glacier900,
  textSecondary: WpPalette.glacier700,
  textMuted: WpPalette.glacier600,
  switchTrackOff: WpPalette.glacier600,
  selectionBorder: Color(0xFF6B7A96),
  accent: WpPalette.cyan700,
  accentHover: WpPalette.cyan600,
  action: WpPalette.cyan300,
  onAction: WpPalette.navy900,
  accentSubtle: Color(0x2A0BAACC),
  accentChipFill: Color(0x1A0BAACC),
  accentChipFillHover: Color(0x2E0BAACC),
  accentMiniTagFill: Color(0x1F0BAACC),
  accentBorder30: Color(0x4D005F73),
  accentButtonFill: Color(0x140BAACC),
  accentActiveFill: Color(0x240BAACC),
  accentBadgeFill: Color(0x260BAACC),
  accentBorder20: Color(0x33005F73),
  accentRowHover: Color(0x0F0BAACC),
  surfaceChipFill: WpPalette.glacier100,
  surfaceMutedFill: Color(0x1452607A),
  // Resting cards sit a step below white; hover and selection lift to white.
  cardFill: WpPalette.glacier50,
  cardFillElevated: WpPalette.white,
  cardEdgeHighlight: Color(0x1F0B122A),
  floatingSurface: WpPalette.white,
  decorativeGlyphWash: Color(0x0D005F73),
  success: WpPalette.green800,
  warning: WpPalette.yellow800,
  error: WpPalette.red800,
  onError: WpPalette.white,
  errorRowHover: Color(0x0FB42318),
  errorButtonFill: Color(0x14B42318),
  errorActiveFill: Color(0x1FB42318),
  errorBorder20: Color(0x33B42318),
  errorBorder30: Color(0x4DB42318),
  mutedRowHover: Color(0x0F52607A),
  mutedActiveFill: Color(0x1F52607A),
  successActiveFill: Color(0x1F0B6B40),
  warningActiveFill: Color(0x33F5C842),
  accentLocatorRing: Color(0x8C005F73),
  recordingAccent: WpPalette.cyan500,
  recordingAccentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.cyan400, WpPalette.cyan500, WpPalette.cyan600],
  ),
  warningOrange: Color(0xFFC2410C),
  warningOrangeBadgeFill: Color(0x1FC2410C),
  warningOrangeBadgeBorder: Color(0x66C2410C),
  errorRed: WpPalette.red800,
  errorRedHover: Color(0xFF912018),
  surfaceGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.white, WpPalette.glacier50],
  ),
  warmSurfaceGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.glacier50, WpPalette.glacier50, WpPalette.glacier50],
    stops: [0.0, 0.5, 1.0],
  ),
  frameGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      WpPalette.glacier100,
      WpPalette.glacier100,
      WpPalette.glacier100,
      WpPalette.glacier200,
    ],
    stops: [0.0, 0.42, 0.74, 1.0],
  ),
  accentGradient: LinearGradient(
    colors: [WpPalette.cyan300, WpPalette.cyan400],
  ),
  accentWarmGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.cyan500, WpPalette.cyan600, WpPalette.cyan700],
  ),
  navChipGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x000B122A), Color(0x000B122A), Color(0x000B122A)],
    stops: [0.0, 0.1, 1.0],
  ),
  navChipGradientHover: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0F0B122A), Color(0x0F0B122A), Color(0x0F0B122A)],
    stops: [0.0, 0.1, 1.0],
  ),
  navPillActiveGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x2E0BAACC), Color(0x240BAACC), Color(0x240BAACC)],
    stops: [0.0, 0.1, 1.0],
  ),
  highlight: WpPalette.amber400,
  highlightSoft: Color(0x33FFB547),
  highlightText: WpPalette.amber800,
  primaryRecordFill: WpPalette.cyan300,
  primaryRecordHover: WpPalette.cyan200,
  onPrimaryRecord: WpPalette.navy900,
  ctaFill: WpPalette.amber400,
  ctaHover: WpPalette.amber200,
  ctaPressed: Color(0xFFE39A2D),
  onCta: WpPalette.navy900,
  controlEdge: WpPalette.glacier500,
  warningOrangeText: Color(0xFF9A3412),
  shadow: Color(0x1F0B122A),
);

/// Dark: the navy stage palette as working area.
const WpThemeColors wpDarkColors = WpThemeColors(
  brightness: Brightness.dark,
  background: WpColorsDark.background,
  surface: WpColorsDark.surface,
  surfaceElevated: WpColorsDark.surfaceElevated,
  surfaceVariant: WpColorsDark.surfaceVariant,
  hover: WpColorsDark.hover,
  hoverTransparent: WpColorsDark.hoverTransparent,
  active: WpColorsDark.active,
  borderSubtle: WpColorsDark.borderSubtle,
  borderDefault: WpColorsDark.borderDefault,
  textPrimary: WpColorsDark.textPrimary,
  textSecondary: WpColorsDark.textSecondary,
  textMuted: WpColorsDark.textMuted,
  switchTrackOff: WpPalette.glacier500,
  selectionBorder: Color(0xFF6B7A96),
  accent: WpColorsDark.accent,
  accentHover: WpColorsDark.accentHover,
  action: WpColorsDark.action,
  onAction: WpColorsDark.onAction,
  accentSubtle: WpColorsDark.accentSubtle,
  accentChipFill: WpColorsDark.accentChipFill,
  accentChipFillHover: WpColorsDark.accentChipFillHover,
  accentMiniTagFill: WpColorsDark.accentMiniTagFill,
  accentBorder30: WpColorsDark.accentBorder30,
  accentButtonFill: WpColorsDark.accentButtonFill,
  accentActiveFill: WpColorsDark.accentActiveFill,
  accentBadgeFill: WpColorsDark.accentBadgeFill,
  accentBorder20: WpColorsDark.accentBorder20,
  accentRowHover: WpColorsDark.accentRowHover,
  surfaceChipFill: WpColorsDark.surfaceChipFill,
  surfaceMutedFill: WpColorsDark.surfaceMutedFill,
  cardFill: WpColorsDark.cardFill,
  cardFillElevated: WpColorsDark.cardFillElevated,
  cardEdgeHighlight: WpColorsDark.cardEdgeHighlight,
  floatingSurface: WpColorsDark.floatingSurface,
  decorativeGlyphWash: WpColorsDark.decorativeGlyphWash,
  success: WpColorsDark.success,
  warning: WpColorsDark.warning,
  error: WpColorsDark.error,
  onError: WpColorsDark.onError,
  errorRowHover: WpColorsDark.errorRowHover,
  errorButtonFill: WpColorsDark.errorButtonFill,
  errorActiveFill: WpColorsDark.errorActiveFill,
  errorBorder20: WpColorsDark.errorBorder20,
  errorBorder30: WpColorsDark.errorBorder30,
  mutedRowHover: WpColorsDark.mutedRowHover,
  mutedActiveFill: WpColorsDark.mutedActiveFill,
  successActiveFill: WpColorsDark.successActiveFill,
  warningActiveFill: WpColorsDark.warningActiveFill,
  accentLocatorRing: WpColorsDark.accentLocatorRing,
  recordingAccent: WpColorsDark.recordingAccent,
  recordingAccentGradient: WpColorsDark.recordingAccentGradient,
  warningOrange: WpColorsDark.warningOrange,
  warningOrangeBadgeFill: WpColorsDark.warningOrangeBadgeFill,
  warningOrangeBadgeBorder: WpColorsDark.warningOrangeBadgeBorder,
  errorRed: WpColorsDark.errorRed,
  errorRedHover: WpColorsDark.errorRedHover,
  surfaceGradient: WpColorsDark.surfaceGradient,
  warmSurfaceGradient: WpColorsDark.warmSurfaceGradient,
  frameGradient: WpColorsDark.frameGradient,
  accentGradient: WpColorsDark.accentGradient,
  accentWarmGradient: WpColorsDark.accentWarmGradient,
  navChipGradient: WpColorsDark.navChipGradient,
  navChipGradientHover: WpColorsDark.navChipGradientHover,
  navPillActiveGradient: WpColorsDark.navPillActiveGradient,
  highlight: WpPalette.amber400,
  highlightSoft: Color(0x29FFB547),
  highlightText: WpPalette.amber400,
  primaryRecordFill: WpColorsDark.action,
  primaryRecordHover: WpColorsDark.accentHover,
  onPrimaryRecord: WpColorsDark.onAction,
  ctaFill: WpPalette.amber400,
  ctaHover: WpPalette.amber200,
  ctaPressed: Color(0xFFE39A2D),
  onCta: WpPalette.navy900,
  controlEdge: Color(0xFF6A7DA6),
  warningOrangeText: Color(0xFFFDBA74),
  shadow: Color(0x4D000000),
);

/// Navy: website language, navy frame around light content, amber primary
/// record button (WP-50).
const WpThemeColors wpNavyColors = WpThemeColors(
  brightness: Brightness.light,
  frameOverride: wpDarkColors,
  background: WpPalette.glacier100,
  surface: WpPalette.glacier50,
  surfaceElevated: WpPalette.white,
  surfaceVariant: WpPalette.glacier100,
  hover: Color(0x0F0B122A),
  hoverTransparent: Color(0x000B122A),
  active: WpPalette.glacier200,
  borderSubtle: Color(0x1F0B122A),
  borderDefault: WpPalette.glacier300,
  textPrimary: WpPalette.glacier900,
  textSecondary: WpPalette.glacier700,
  textMuted: WpPalette.glacier600,
  switchTrackOff: WpPalette.glacier600,
  selectionBorder: Color(0xFF6B7A96),
  accent: WpPalette.cyan700,
  accentHover: WpPalette.cyan600,
  action: WpPalette.cyan300,
  onAction: WpPalette.navy900,
  accentSubtle: Color(0x2A0BAACC),
  accentChipFill: Color(0x1A0BAACC),
  accentChipFillHover: Color(0x2E0BAACC),
  accentMiniTagFill: Color(0x1F0BAACC),
  accentBorder30: Color(0x4D005F73),
  accentButtonFill: Color(0x140BAACC),
  accentActiveFill: Color(0x240BAACC),
  accentBadgeFill: Color(0x260BAACC),
  accentBorder20: Color(0x33005F73),
  accentRowHover: Color(0x0F0BAACC),
  surfaceChipFill: WpPalette.glacier100,
  surfaceMutedFill: Color(0x1452607A),
  // Resting cards sit a step below white; hover and selection lift to white.
  cardFill: WpPalette.glacier50,
  cardFillElevated: WpPalette.white,
  cardEdgeHighlight: Color(0x1F0B122A),
  floatingSurface: WpPalette.white,
  decorativeGlyphWash: Color(0x0D005F73),
  success: WpPalette.green800,
  warning: WpPalette.yellow800,
  error: WpPalette.red800,
  onError: WpPalette.white,
  errorRowHover: Color(0x0FB42318),
  errorButtonFill: Color(0x14B42318),
  errorActiveFill: Color(0x1FB42318),
  errorBorder20: Color(0x33B42318),
  errorBorder30: Color(0x4DB42318),
  mutedRowHover: Color(0x0F52607A),
  mutedActiveFill: Color(0x1F52607A),
  successActiveFill: Color(0x1F0B6B40),
  warningActiveFill: Color(0x33F5C842),
  accentLocatorRing: Color(0x8C005F73),
  recordingAccent: WpPalette.cyan500,
  recordingAccentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.cyan400, WpPalette.cyan500, WpPalette.cyan600],
  ),
  warningOrange: Color(0xFFC2410C),
  warningOrangeBadgeFill: Color(0x1FC2410C),
  warningOrangeBadgeBorder: Color(0x66C2410C),
  errorRed: WpPalette.red800,
  errorRedHover: Color(0xFF912018),
  surfaceGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.white, WpPalette.glacier50],
  ),
  warmSurfaceGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.glacier50, WpPalette.glacier50, WpPalette.glacier50],
    stops: [0.0, 0.5, 1.0],
  ),
  frameGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      WpPalette.glacier100,
      WpPalette.glacier100,
      WpPalette.glacier100,
      WpPalette.glacier200,
    ],
    stops: [0.0, 0.42, 0.74, 1.0],
  ),
  accentGradient: LinearGradient(
    colors: [WpPalette.cyan300, WpPalette.cyan400],
  ),
  accentWarmGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [WpPalette.cyan500, WpPalette.cyan600, WpPalette.cyan700],
  ),
  navChipGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x000B122A), Color(0x000B122A), Color(0x000B122A)],
    stops: [0.0, 0.1, 1.0],
  ),
  navChipGradientHover: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0F0B122A), Color(0x0F0B122A), Color(0x0F0B122A)],
    stops: [0.0, 0.1, 1.0],
  ),
  navPillActiveGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x2E0BAACC), Color(0x240BAACC), Color(0x240BAACC)],
    stops: [0.0, 0.1, 1.0],
  ),
  highlight: WpPalette.amber400,
  highlightSoft: Color(0x33FFB547),
  highlightText: WpPalette.amber800,
  // Navy only: amber as the primary record fill (WP-50, a deliberate accent
  // surface under the amber rule, WCAG AA). The light and dark values mirror the
  // primary-record roles in app.tokens.json; navy has no generated surface.
  primaryRecordFill: WpPalette.amber400,
  primaryRecordHover: WpPalette.amber200,
  onPrimaryRecord: WpPalette.navy900,
  ctaFill: WpPalette.amber400,
  ctaHover: WpPalette.amber200,
  ctaPressed: Color(0xFFE39A2D),
  onCta: WpPalette.navy900,
  controlEdge: WpPalette.glacier500,
  warningOrangeText: Color(0xFF9A3412),
  shadow: Color(0x1F0B122A),
);
