/// Single Source of Truth for the floating-overlay and floating-button look.
///
/// One Dart representation of every dimension, colour (dark/light),
/// typography, per-state layout, animation timing and waveform parameter.
/// This spec is the **only** source — the native
/// window shells and the shared `CustomPainter` (issues 05/07/08) consume it;
/// no renderer and no widget defines its own constants any more.
///
/// Binding decisions baked in here (PRD §D4, ADR 0002):
/// - **No Privacy-Badge** — the concept is anti-vocabulary and is absent from
///   this model.
/// - State colours (recording/transcribing/done/error) and the cyan accent
///   (dark `#38D9F0` / light `#0887A8`) are taken from the current macOS values
///   and finalised here.
/// - The done gradient's middle stop is the canonical green `#30C065`.
/// - **Compact = scaled, not reduced.** The waveform bar count is identical for
///   both sizes (no 8-vs-30 split); compact content metrics are derived from
///   the normal spec by [OverlayDesignSpec.compactScale].
/// - **Mini = reduced by design.** The third size ([OverlaySizeSpec.mini]) is
///   the sanctioned exception: a waveform-first micro capsule with explicit
///   hand-tuned anchors, extra-translucent chrome and minimal content.
///   **Nano** ([OverlaySizeSpec.nano]) reduces further: a 24 px status mark
///   with a shorter wave ([OverlaySizeSpec.waveformBarCount]) and no text.
///   Every size takes its bars from the same live levels; only the count
///   differs.
/// - **Notice card footer** (#781): size, gap and ink come from the
///   `noticeFooter*` tokens; the ink steps up until it reaches 4.5:1.
/// - **Calm UI** — no light effects, no harsh effects; soft/slow timings.
/// - **Accessibility:** the opacity setting affects ONLY the pill fill
///   ([OverlayDesignSpec.fillOpacityFactor] × opacity); text, icons and the
///   waveform stay fully opaque. The recommended slider floor is
///   [OverlayDesignSpec.minRecommendedOpacity].
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'colors_dark.dart';
import 'generated/wp_tokens.g.dart';

/// The four real recording states the overlay and button render.
///
/// Mirrors `OverlayVisualState` (recording/transcribing/done/error). There is
/// deliberately no `processing` state and no privacy badge.
enum OverlayDesignState { recording, transcribing, done, error }

/// The four overlay size variants.
///
/// - [normal]: the full pill (timer, waveform, close/stop, status text).
/// - [compact]: the same content scaled down ("scaled, not reduced").
/// - [mini]: the waveform-first variant — a small, extra-translucent capsule
///   whose content is deliberately REDUCED to (almost) only the waveform.
///   Status identity stays readable through the crisp content glyphs (live
///   waveform, transcribing spinner + status label, done/error status icons);
///   timer text, close glyph and stop square are omitted by design
///   ([OverlaySizeSpec.minimalContent]).
/// - [nano]: the smallest status mark. Only a short live wave and the state
///   glyph (spinner, check, error); no status text at all
///   ([OverlaySizeSpec.paintsStatusLabel] is false).
enum OverlaySizeVariant {
  /// Full-size pill.
  normal,

  /// Scaled-down pill with identical content.
  compact,

  /// Waveform-first micro pill (extra translucent, minimal content).
  mini,

  /// Waveform-only status mark: a short wave, no text.
  nano;

  /// Resolves a persisted/serialised name; unknown or null → [normal].
  static OverlaySizeVariant fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => OverlaySizeVariant.normal,
  );
}

/// Theme variants the spec provides a complete colour set for.
enum OverlayDesignTheme { dark, light }

/// The two chrome styles the overlay pill can render.
///
/// Background presets of the recording overlay and the floating button
/// (ticket, ADR 0024). Each preset is a flat token set from
/// `design-tokens/app.tokens.json` (`overlay.*`, [WpOverlayTokens]); its
/// [tone] decides which wave and signal values pair with it.
///
/// Replaces the old glass/solid chrome switch: both rendered the same opaque
/// fill, so the switch only toggled a faint highlight.
enum OverlayBackground {
  marine(
    'marine',
    OverlayDesignTheme.dark,
    WpOverlayTokens.overlayMarineSurface,
    WpOverlayTokens.overlayMarineInk,
    WpOverlayTokens.overlayMarineInkOutline,
    WpOverlayTokens.overlayMarineEdge,
  ),
  graphit(
    'graphit',
    OverlayDesignTheme.dark,
    WpOverlayTokens.overlayGraphitSurface,
    WpOverlayTokens.overlayGraphitInk,
    WpOverlayTokens.overlayGraphitInkOutline,
    WpOverlayTokens.overlayGraphitEdge,
  ),
  gletscher(
    'gletscher',
    OverlayDesignTheme.light,
    WpOverlayTokens.overlayGletscherSurface,
    WpOverlayTokens.overlayGletscherInk,
    WpOverlayTokens.overlayGletscherInkOutline,
    WpOverlayTokens.overlayGletscherEdge,
  ),

  /// Bernstein: the warm accent as a surface. Light tone, so the dark ink and
  /// the light wave/signal set apply; [OverlayThemeColors.resolve] keeps every
  /// foreground at 3:1 (dark ink takes over where it cannot).
  amber(
    'amber',
    OverlayDesignTheme.light,
    WpOverlayTokens.overlayAmberSurface,
    WpOverlayTokens.overlayAmberInk,
    WpOverlayTokens.overlayAmberInkOutline,
    WpOverlayTokens.overlayAmberEdge,
  ),

  /// Glass: a nearly colourless body. On macOS 26+ and Windows 11 the system
  /// backdrop (NSGlassEffectView, acrylic) shows through and the Flutter fill
  /// is skipped; elsewhere the fill is a faint neutral tint (see
  /// [glassFillFor]). Its tone follows the system appearance, so the ink is
  /// dark on a light glass and white on a dark one ([glassInkFor]). The rim
  /// light and highlight are painted by [WpOverlayPainter].
  glass(
    'glass',
    OverlayDesignTheme.dark,
    Color(0x26000000),
    Color(0xFFFFFFFF),
    Color(0x66000000),
    Color(0x33FFFFFF),
  );

  /// Body fill of the glass for [tone]: a faint dark tint (10-20 %) on dark,
  /// a faint white tint (8-18 %) on light. Used without a native backdrop.
  static Color glassFillFor(OverlayDesignTheme tone) => switch (tone) {
    OverlayDesignTheme.dark => const Color(0x26000000),
    OverlayDesignTheme.light => const Color(0x29FFFFFF),
  };

  /// Opaque, calm neutral body for [tone]: the fallback under "reduce
  /// transparency" and on Linux without blur. Not muddy grey.
  static Color glassOpaqueFor(OverlayDesignTheme tone) => switch (tone) {
    OverlayDesignTheme.dark => const Color(0xFF1C1F24),
    OverlayDesignTheme.light => const Color(0xFFF2F4F7),
  };

  /// Glyph colour for [tone]: white on dark glass, the Gletscher ink on light.
  static Color glassInkFor(OverlayDesignTheme tone) => switch (tone) {
    OverlayDesignTheme.dark => const Color(0xFFFFFFFF),
    OverlayDesignTheme.light => WpOverlayTokens.overlayGletscherInk,
  };

  /// Outline behind the glyphs for [tone].
  static Color glassInkOutlineFor(OverlayDesignTheme tone) => switch (tone) {
    OverlayDesignTheme.dark => const Color(0x66000000),
    OverlayDesignTheme.light => const Color(0x66FFFFFF),
  };

  const OverlayBackground(
    this.value,
    this.tone,
    this.surfaceStart,
    this.ink,
    this.inkOutline,
    this.edge,
  );

  /// Persisted name (`overlay_background`).
  final String value;

  /// Whether this background is dark or light; selects the wave and signal set.
  final OverlayDesignTheme tone;

  /// The flat pill and button fill (ticket flat pass: one colour, no gradient).
  final Color surfaceStart;

  /// Glyph fill (timer, status text, close glyph, stop square).
  final Color ink;

  /// Outline drawn behind the glyphs.
  final Color inkOutline;

  /// The 1 px outer edge of the pill and button (UX-048). Translucent white on
  /// the dark presets so they read on a dark desktop; transparent on the light
  /// presets, which need no edge.
  final Color edge;

  /// Resolves a persisted name; unknown or null falls back to [marine].
  static OverlayBackground fromValue(String? name) => values.firstWhere(
    (v) => v.value == name,
    orElse: () => OverlayBackground.marine,
  );
}

/// Wave colour presets (ticket, ADR 0024; palette and validity ticket). A wave
/// has one value per tone. A background × wave pairing is valid only when the
/// wave, or its darker light step, reaches 3:1 on the fill ([effectiveOn]).
/// Invalid pairings are disabled in the settings, never drawn in a stand-in
/// colour.
enum OverlayWave {
  cyan(
    'cyan',
    WpOverlayTokens.overlayWaveCyanDark,
    WpOverlayTokens.overlayWaveCyanLight,
    WpOverlayTokens.overlayWaveCyanLightStrong,
  ),
  violett(
    'violett',
    WpOverlayTokens.overlayWaveViolettDark,
    WpOverlayTokens.overlayWaveViolettLight,
    WpOverlayTokens.overlayWaveViolettLightStrong,
  ),

  /// Tinte: black, so it is valid only on the light backgrounds. (The former
  /// Neutral preset was retired on 2026-10-29 and loads as this one.)
  ink(
    'ink',
    WpOverlayTokens.overlayWaveInkDark,
    WpOverlayTokens.overlayWaveInkLight,
    WpOverlayTokens.overlayWaveInkLightStrong,
  ),

  /// White: the light counterpart of [ink], so it is valid only on the dark
  /// backgrounds.
  white(
    'white',
    WpOverlayTokens.overlayWaveWhiteDark,
    WpOverlayTokens.overlayWaveWhiteLight,
    WpOverlayTokens.overlayWaveWhiteLightStrong,
  ),

  /// Bernstein wave (ticket flat pass). Amber on dark, dark amber on light.
  amber(
    'amber',
    WpOverlayTokens.overlayWaveAmberDark,
    WpOverlayTokens.overlayWaveAmberLight,
    WpOverlayTokens.overlayWaveAmberLightStrong,
  ),

  /// Koralle (ticket).
  coral(
    'coral',
    WpOverlayTokens.overlayWaveCoralDark,
    WpOverlayTokens.overlayWaveCoralLight,
    WpOverlayTokens.overlayWaveCoralLightStrong,
  ),

  /// Mint (ticket).
  mint(
    'mint',
    WpOverlayTokens.overlayWaveMintDark,
    WpOverlayTokens.overlayWaveMintLight,
    WpOverlayTokens.overlayWaveMintLightStrong,
  );

  const OverlayWave(
    this.value,
    this._onDark,
    this._onLight,
    this._onLightStrong,
  );

  /// Persisted name (`overlay_wave`).
  final String value;

  final Color _onDark;
  final Color _onLight;

  /// Darker step of the same hue on a light background. Used only when the
  /// base light step falls below 3:1 on the fill.
  final Color _onLightStrong;

  /// The wave colour on a background of [tone].
  Color valueOn(OverlayDesignTheme tone) =>
      tone == OverlayDesignTheme.dark ? _onDark : _onLight;

  /// The colour this wave is drawn with on [background], or null when the
  /// pairing is invalid. Tries the base step first and, on a light tone, the
  /// darker step of the same hue second. The pill and the settings swatch both
  /// read this one value, so what the swatch shows is what gets drawn.
  Color? effectiveOn(OverlayBackground background) {
    final candidates = background.tone == OverlayDesignTheme.dark
        ? [_onDark]
        : [_onLight, _onLightStrong];
    for (final color in candidates) {
      if (contrastRatio(color, background.surfaceStart) >= 3.0) return color;
    }
    return null;
  }

  /// Whether this wave may be chosen on [background] (ticket).
  bool isValidOn(OverlayBackground background) =>
      effectiveOn(background) != null;

  /// The wave to use on [background]: this wave when valid, otherwise a fixed
  /// replacement. Every invalid wave becomes Cyan, and the first valid wave is
  /// the last resort. Deterministic, so a stored or switched choice always
  /// lands on the same wave.
  OverlayWave validOn(OverlayBackground background) {
    if (isValidOn(background)) return this;
    if (cyan.isValidOn(background)) return cyan;
    return OverlayWave.values.firstWhere((wave) => wave.isValidOn(background));
  }

  /// Resolves a persisted name; unknown or null falls back to [cyan].
  static OverlayWave fromValue(String? name) =>
      values.firstWhere((v) => v.value == name, orElse: () => OverlayWave.cyan);
}

/// WCAG 2.x contrast ratio of [a] over [b] (1:1 to 21:1). Shared with
/// `OverlayOpacityGate` in `overlay_customization.dart`.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A complete, resolved colour set for one background × wave pairing
/// (ticket, ADR 0024). Build it with [OverlayThemeColors.resolve] or
/// [OverlayDesignSpec.colorsFor]; every field is non-null for every pairing.
@immutable
class OverlayThemeColors {
  const OverlayThemeColors({
    required this.tone,
    required this.capsuleFill,
    required this.ink,
    required this.inkOutline,
    required this.edge,
    required this.shadow,
    required this.capsuleBorder,
    required this.accent,
    required this.transcribingAccent,
    required this.success,
    required this.warning,
    required this.error,
    this.glass = false,
    Color? opaqueFill,
  }) : opaqueFill = opaqueFill ?? capsuleFill;

  /// Resolves the colour set for [background] paired with [wave].
  factory OverlayThemeColors.resolve({
    required OverlayBackground background,
    required OverlayWave wave,
    OverlayDesignTheme glassTone = OverlayDesignTheme.dark,
  }) {
    final isGlass = background == OverlayBackground.glass;
    if (!isGlass) {
      assert(
        wave.isValidOn(background),
        '${wave.value} is not valid on ${background.value}: '
        'replace it with OverlayWave.validOn first',
      );
    }
    final tone = isGlass ? glassTone : background.tone;
    final dark = tone == OverlayDesignTheme.dark;
    final ink = isGlass ? OverlayBackground.glassInkFor(tone) : background.ink;
    final inkOutline = isGlass
        ? OverlayBackground.glassInkOutlineFor(tone)
        : background.inkOutline;
    final surface = isGlass
        ? OverlayBackground.glassFillFor(tone)
        : background.surfaceStart;
    // Legibility is judged on the opaque body: the faint glass tint is not
    // a stable reference, the backdrop behind it is unknown.
    final reference = isGlass
        ? OverlayBackground.glassOpaqueFor(tone)
        : background.surfaceStart;
    // Every non-text foreground (wave, signals) must reach 3:1 on the fill.
    // The wave steps down to the darker step of its own hue before it gives
    // way to the dark ink. Other signals fall straight back to the ink.
    Color legible(Color color) =>
        contrastRatio(color, reference) >= 3.0 ? color : ink;
    // Glass is monochrome: the wave, dot, timer and chips take the glyph
    // colour of the glass tone, so no coloured wave is lost on a coloured
    // backdrop. The wave preset does not apply to glass.
    final accent = isGlass
        ? ink
        : wave.effectiveOn(background) ?? wave.valueOn(background.tone);
    return OverlayThemeColors(
      tone: tone,
      capsuleFill: surface,
      ink: ink,
      inkOutline: inkOutline,
      edge: background.edge,
      shadow: dark
          ? WpOverlayTokens.overlayShadowDark
          : WpOverlayTokens.overlayShadowLight,
      capsuleBorder: accent.withValues(alpha: 0.2),
      accent: accent,
      transcribingAccent: isGlass
          ? ink
          : legible(
              dark
                  ? WpOverlayTokens.overlaySignalDarkTranscribing
                  : WpOverlayTokens.overlaySignalLightTranscribing,
            ),
      success: legible(
        dark
            ? WpOverlayTokens.overlaySignalDarkDone
            : WpOverlayTokens.overlaySignalLightDone,
      ),
      warning: legible(
        dark ? wpStagePalette.warning : wpJournalPalette.warning,
      ),
      error: legible(
        dark
            ? WpOverlayTokens.overlaySignalDarkError
            : WpOverlayTokens.overlaySignalLightError,
      ),
      glass: background == OverlayBackground.glass,
      opaqueFill: isGlass ? OverlayBackground.glassOpaqueFor(tone) : null,
    );
  }

  /// Dark or light: the tone of the chosen background.
  final OverlayDesignTheme tone;

  /// The flat pill and button fill (the background surface).
  final Color capsuleFill;

  /// Glyph fill: timer, status text, close glyph, stop square.
  final Color ink;

  /// Outline behind the glyphs; keeps them legible on any desktop.
  final Color inkOutline;

  /// The 1 px outer edge (UX-048); transparent on light presets.
  final Color edge;

  /// Painted drop shadow of the pill and the button, alpha included (UX-048).
  final Color shadow;

  /// Hairline border of the pill: the wave colour at 20 percent.
  final Color capsuleBorder;

  /// Wave colour: live waveform bars, the recording mark (pill dot and button
  /// mic while recording, ring) and progress timeline.
  final Color accent;

  /// Amber owned by the transcribing state (processing spinner and ripple).
  /// Fixed per tone, not themeable, so "working" stays distinct from
  /// "listening" by colour and motion.
  final Color transcribingAccent;

  /// Success colour: done check and message.
  final Color success;

  /// Warning colour: a finished run whose paste failed, as in the dock.
  final Color warning;

  /// Error colour: error icon and message.
  final Color error;

  /// Glass look: the painter adds the rim light and the top highlight.
  final bool glass;

  /// Fill used under "reduce transparency" (equals [capsuleFill] for the
  /// solid presets; the calm neutral body for glass).
  final Color opaqueFill;

  /// Status dot of the notice card (overlay F2) for an error: one path on
  /// every background, glass included. The tone's error signal, else the
  /// next red step that reaches 3:1 on the card's opaque body, else the ink.
  Color get noticeErrorDot => _firstLegible(
    tone == OverlayDesignTheme.dark
        ? const [WpOverlayTokens.overlaySignalDarkError, WpPalette.red400]
        : const [WpOverlayTokens.overlaySignalLightError, WpPalette.red800],
  );

  /// Status dot of the notice card for a hint or the duration limit: amber,
  /// resolved like [noticeErrorDot]. Unlike [transcribingAccent] it stays
  /// amber on glass, so the dot keeps its meaning there.
  Color get noticeHintDot => _firstLegible(
    tone == OverlayDesignTheme.dark
        ? const [
            WpOverlayTokens.overlaySignalDarkTranscribing,
            WpPalette.amber400,
          ]
        : const [
            WpOverlayTokens.overlaySignalLightTranscribing,
            WpPalette.amber800,
          ],
  );

  /// Ink of the key footer of the notice card (#781): the quietest ink step
  /// that still reaches 4.5:1 on the card's opaque body (small text), else the
  /// full ink. Resolved per preset, glass and marine included.
  Color get noticeFooterInk =>
      _quietestLegibleInk(OverlayDesignSpec.noticeFooterInkAlphas);

  /// Ink of the notice card body (#728): same contrast-checked step logic as
  /// [noticeFooterInk], starting one step higher than the footer.
  Color get noticeBodyInk =>
      _quietestLegibleInk(OverlayDesignSpec.noticeBodyInkAlphas);

  Color _quietestLegibleInk(List<double> alphas) {
    for (final a in alphas) {
      final c = ink.withValues(alpha: a);
      if (contrastRatio(Color.alphaBlend(c, opaqueFill), opaqueFill) >=
          OverlayDesignSpec.noticeFooterMinContrast) {
        return c;
      }
    }
    return ink;
  }

  Color _firstLegible(List<Color> steps) => steps.firstWhere(
    (c) => contrastRatio(c, opaqueFill) >= 3.0,
    orElse: () => ink,
  );

  /// Every colour in declaration order; equality and hashing run over this.
  List<Object> get _values => [
    tone,
    capsuleFill,
    ink,
    inkOutline,
    edge,
    shadow,
    capsuleBorder,
    accent,
    transcribingAccent,
    success,
    error,
    glass,
    opaqueFill,
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayThemeColors && listEquals(_values, other._values);

  @override
  int get hashCode => Object.hashAll(_values);
}

/// Waveform render parameters. Normal, compact and mini share the bar count
/// (compact shows the same bars as normal, just shorter, PRD §D4); nano draws
/// fewer bars from the same levels ([OverlaySizeSpec.waveformBarCount]).
@immutable
class WaveformSpec {
  const WaveformSpec({
    required this.barCount,
    required this.minBarHeightPx,
    required this.attackTimeConstantMs,
    required this.releaseTimeConstantMs,
  });

  /// Number of bars in the rendered snapshot. Normal, compact and mini draw
  /// all of them; nano draws fewer ([OverlaySizeSpec.waveformBarCount]).
  final int barCount;

  /// Hard floor for every bar in logical pixels.
  final double minBarHeightPx;

  /// Smoothing time constant (ms) for the **rising** edge of the live level —
  /// how fast a bar climbs when the speaker gets louder. Short, so loud onsets
  /// register promptly (volume-faithful amplitude).
  final double attackTimeConstantMs;

  /// Smoothing time constant (ms) for the **falling** edge of the live level —
  /// how fast a bar decays toward the floor during a pause. Longer than
  /// [attackTimeConstantMs] so a pause visibly fades the waveform to the min
  /// height instead of snapping flat (silence → nearly flat, no floor jitter).
  final double releaseTimeConstantMs;
}

/// All geometry and typography for one overlay size (normal, compact or mini).
///
/// `width`/`height`/`cornerRadius` are deliberate per-size **anchors**.
/// All other (content) metrics of the compact variant are **derived** from the
/// normal variant by [OverlayDesignSpec.compactScale] — see
/// [OverlaySizeSpec.compact]. The mini variant is the sanctioned exception to
/// "scaled, not reduced": its content is REDUCED by design (waveform-first),
/// so its metrics are explicit hand-tuned anchors — see [OverlaySizeSpec.mini].
@immutable
class OverlaySizeSpec {
  const OverlaySizeSpec({
    required this.width,
    required this.height,
    required this.cornerRadius,
    required this.closeButtonSize,
    required this.stopButtonSize,
    required this.statusIconSize,
    required this.waveformMaxHeight,
    required this.waveformBarWidth,
    required this.waveformBarGap,
    required this.timerWaveformGap,
    required this.pillGap,
    required this.bottomProgressHeight,
    required this.timerFontSize,
    required this.primaryFontSize,
    this.minimalContent = false,
    this.paintsStatusLabel = true,
    this.waveformBarCount = OverlayDesignSpec.waveformBarCount,
    this.timelineInsetBottom = OverlayDesignSpec.timelineInsetBottom,
    this.timelineStrokeWidth = OverlayDesignSpec.timelineStrokeWidth,
    this.timelineLeadDotRadius = OverlayDesignSpec.timelineLeadDotRadius,
  });

  // -- Box anchors (per-size, not scaled) ------------------------------------

  /// Pill width.
  final double width;

  /// Pill height.
  final double height;

  /// Pill corner radius. A compact pill is deliberately rounder than the
  /// normal pill (relative to its size), so this is an anchor, not scaled.
  final double cornerRadius;

  // -- Content metrics (compact = normal × compactScale) ---------------------

  /// Close (cancel-X) button diameter.
  final double closeButtonSize;

  /// Stop button diameter (recording only).
  final double stopButtonSize;

  /// Done/error status icon size.
  final double statusIconSize;

  /// Maximum waveform bar height.
  final double waveformMaxHeight;

  /// Waveform bar width.
  final double waveformBarWidth;

  /// Minimum gap between waveform bars.
  final double waveformBarGap;

  /// Gap between the timer and the waveform.
  final double timerWaveformGap;

  /// Gap between the close button and the first content element.
  final double pillGap;

  /// Height of the bottom progress timeline.
  final double bottomProgressHeight;

  /// Recording timer font size (bold, tabular figures).
  final double timerFontSize;

  /// Primary label/done/error text font size.
  final double primaryFontSize;

  // -- Per-size derived chrome metrics (design layout pass) ------------------
  //
  // Fill alpha and the waveform alpha ladder are deliberately NOT per-size
  // any more: all three sizes share ONE fill and ONE ladder
  // ([OverlayDesignSpec.fillOpacityFactor] / the waveform*Opacity constants),
  // so the sizes read as one material — only geometry and content density
  // vary. The timeline metrics below scale per size because the shared
  // absolute values collided with the waveform inside the 28 px mini pill
  // (6 px inset = 21 % of mini's height vs. 9 % of normal's).

  /// Whether this size renders the reduced, waveform-first content set
  /// (mini): no close glyph, no timer, no stop square; the waveform is the
  /// dominant element and done/error collapse to a centred status icon.
  /// State identity stays on the content glyphs (dot/spinner/icons) plus —
  /// since the state-distinction pass — the transcribing status label, the
  /// one text mini does paint (the ever-moving waveform alone did not
  /// distinguish transcribing from recording there).
  final bool minimalContent;

  /// Whether the transcribing state paints its status label beside the
  /// spinner. False for nano, which shows the spinner alone. Only meaningful
  /// with [minimalContent]; the other sizes always paint their label.
  final bool paintsStatusLabel;

  /// Number of waveform bars drawn for this size. The live levels are reduced
  /// to this count (averaged, see `resampleWaveformLevels`), so the curve
  /// stays the same and only the resolution changes.
  final int waveformBarCount;

  /// Bottom inset of the progress timeline for this size.
  final double timelineInsetBottom;

  /// Stroke width of the progress timeline for this size.
  final double timelineStrokeWidth;

  /// Radius of the timeline's bright lead dot for this size.
  final double timelineLeadDotRadius;

  /// Capsule corner radius — the approved spike pill is a full capsule
  /// (`height / 2` → 32 normal, 20 compact, 17 mini), not the legacy
  /// [cornerRadius].
  double get capsuleRadius => height / 2;

  /// The full normal-size spec — the canonical base all compact values scale
  /// from. Dimensions finalised here per ADR 0002.
  static const OverlaySizeSpec normal = OverlaySizeSpec(
    width: 330,
    height: 64,
    cornerRadius: 18,
    closeButtonSize: 36,
    stopButtonSize: 36,
    statusIconSize: 16,
    waveformMaxHeight: 24,
    waveformBarWidth: 2.5,
    waveformBarGap: 1.5,
    timerWaveformGap: 18,
    pillGap: 14,
    bottomProgressHeight: 4,
    timerFontSize: 15,
    primaryFontSize: 13,
  );

  /// The compact spec: box anchors are explicit (220×40 r20); every
  /// content metric is [OverlayDesignSpec.compactScale] × the normal value, so
  /// compact is a true scaling of normal rather than a separate hand-tuned set.
  /// Timeline metrics overridden (quality-parity pass, 2026-07-29): with the
  /// shared 6 px inset the 2.2 px lead dot (top edge y 31.8) touched the
  /// 24 px waveform zone (bars end y 32). Inset 5 / dot 1.8 → line at 35,
  /// dot 33.2..36.8, clear of the bars.
  static final OverlaySizeSpec compact = normal._scaledContent(
    OverlayDesignSpec.compactScale,
    width: 220,
    height: 40,
    cornerRadius: 20,
    timelineInsetBottom: 5.0,
    timelineLeadDotRadius: 1.8,
  );

  /// The mini spec — the waveform-first third size, in
  /// WhisPaste's own design language: teal accent waveform, capsule chrome,
  /// fixed accent hairline border).
  ///
  /// Deliberately NOT derived via a scale factor: mini reduces content (no
  /// timer, no close glyph, no stop square), so a pure scaling of the normal
  /// metrics has nothing meaningful to scale. Every value here is an explicit
  /// hand-tuned anchor. Glass material and waveform alphas are the SHARED
  /// ones — one design language across all three sizes (design pass).
  ///
  /// Geometry sanity (mirrored-bars pass, 2026-07-29): pill raised 28 → 34
  /// so the mirrored bars can show real amplitude (Maintainer: "in der
  /// Nano-Darstellung … ein bisschen höher"). Waveform 18 px centred in
  /// 34 px → bars span y 8..26; timeline at `34 − 4 = 30` with a 1.6 px lead
  /// dot (28.4..31.6) → 2.4 px clearance.
  static const OverlaySizeSpec mini = OverlaySizeSpec(
    width: 150,
    height: 34,
    cornerRadius: 17,
    closeButtonSize: 18,
    stopButtonSize: 18,
    statusIconSize: 14,
    waveformMaxHeight: 18,
    waveformBarWidth: 2.0,
    waveformBarGap: 1.5,
    timerWaveformGap: 8,
    pillGap: 8,
    bottomProgressHeight: 2,
    timerFontSize: 10,
    primaryFontSize: 9,
    minimalContent: true,
    timelineInsetBottom: 4.0,
    timelineStrokeWidth: 1.5,
    timelineLeadDotRadius: 1.6,
  );

  /// The nano spec — the smallest status mark, waveform-only.
  ///
  /// Scale ladder: normal 64 → compact 40 → mini 34 → nano 24 px high. The
  /// 24 px pill is also the smallest hit area the overlay allows (the native
  /// window adds the shadow padding around it). Width 88 px: an 8 px inset on
  /// each side leaves a 72 px wave zone for [waveformBarCount] 12 bars, the
  /// same bar pitch as mini (~6 px). Content: the live wave (no timer, no
  /// close or stop glyph, no status text) and a centred state glyph for
  /// transcribing, done and error. The progress line stays, as on mini.
  /// The capsule collapses to the glyph width for the non-recording states,
  /// like mini does ([OverlayDesignSpec.minimalPillWidthRatio]).
  static const OverlaySizeSpec nano = OverlaySizeSpec(
    width: 88,
    height: 24,
    cornerRadius: 12,
    closeButtonSize: 12,
    stopButtonSize: 12,
    statusIconSize: 12,
    waveformMaxHeight: 12,
    waveformBarWidth: 1.5,
    waveformBarGap: 1.0,
    timerWaveformGap: 4,
    pillGap: 4,
    bottomProgressHeight: 1.5,
    timerFontSize: 8,
    primaryFontSize: 7,
    minimalContent: true,
    paintsStatusLabel: false,
    waveformBarCount: 12,
    timelineInsetBottom: 3.0,
    timelineStrokeWidth: 1.0,
    timelineLeadDotRadius: 1.2,
  );

  /// Returns a copy with all content metrics scaled by [s] and the box anchors
  /// overridden by the given values. [timelineInsetBottom] /
  /// [timelineLeadDotRadius] may be overridden where the shared absolute
  /// timeline metrics would collide with the waveform zone (see compact).
  OverlaySizeSpec _scaledContent(
    double s, {
    required double width,
    required double height,
    required double cornerRadius,
    double? timelineInsetBottom,
    double? timelineLeadDotRadius,
  }) {
    return OverlaySizeSpec(
      width: width,
      height: height,
      cornerRadius: cornerRadius,
      closeButtonSize: closeButtonSize * s,
      stopButtonSize: stopButtonSize * s,
      statusIconSize: statusIconSize * s,
      waveformMaxHeight: waveformMaxHeight * s,
      waveformBarWidth: waveformBarWidth * s,
      waveformBarGap: waveformBarGap * s,
      timerWaveformGap: timerWaveformGap * s,
      pillGap: pillGap * s,
      bottomProgressHeight: bottomProgressHeight * s,
      timerFontSize: timerFontSize * s,
      primaryFontSize: primaryFontSize * s,
      timelineInsetBottom:
          timelineInsetBottom ?? OverlayDesignSpec.timelineInsetBottom,
      timelineLeadDotRadius:
          timelineLeadDotRadius ?? OverlayDesignSpec.timelineLeadDotRadius,
    );
  }
}

/// Hand-tuned per-size content layout, taken verbatim from the approved spike
/// (`spike/lib/main.dart` `_drawPill`). These offsets are deliberately **not**
/// derived from [OverlayDesignSpec.compactScale] — the spike spacing is its own
/// approved truth, so the painter reads it from here instead of carrying magic
/// numbers. All values are logical pixels relative to the pill box.
@immutable
class OverlayLayoutSpec {
  const OverlayLayoutSpec({
    required this.padH,
    required this.closeArm,
    required this.closeStroke,
    required this.closeOffset,
    required this.dotInset,
    required this.dotRadius,
    required this.timerGap,
    required this.timerFontSize,
    required this.waveStartGap,
    required this.waveEndGap,
    required this.stopSize,
    required this.lineStrokeMin,
  });

  /// Inner horizontal padding (left/right), from the pill edge.
  final double padH;

  /// Half-length of one stroke of the close (✕) glyph.
  final double closeArm;

  /// Close-glyph stroke width (spike `1.6` normal / `1.4` compact).
  final double closeStroke;

  /// Close-glyph centre, measured from `left + padH`.
  final double closeOffset;

  /// Status-icon / spinner centre, measured from `left + padH`.
  final double dotInset;

  /// Radius of the transcribing spinner and the done/error icons.
  final double dotRadius;

  /// Gap from the status glyph (or close glyph) to the timer/label left edge.
  final double timerGap;

  /// Timer/label font size (semibold).
  final double timerFontSize;

  /// Gap from the timer/label right edge to the waveform left edge.
  final double waveStartGap;

  /// Gap kept between the waveform right edge and the stop square.
  final double waveEndGap;

  /// Stop-square side length (recording only).
  final double stopSize;

  /// Minimum visual waveform bar width (the filled bar is the wider of this
  /// and `slot × waveformBarFillFactor`).
  final double lineStrokeMin;

  /// Normal-size layout (spike values, `_drawPill` non-compact branch).
  static const OverlayLayoutSpec normal = OverlayLayoutSpec(
    padH: 22,
    closeArm: 4.0,
    closeStroke: 1.6,
    closeOffset: 5,
    dotInset: 28,
    dotRadius: 4.5,
    timerGap: 16,
    timerFontSize: 14,
    waveStartGap: 18,
    waveEndGap: 16,
    stopSize: 12,
    lineStrokeMin: 2.0,
  );

  /// Compact-size layout (spike values, `_drawPill` compact branch).
  /// Wave gaps trimmed 12/10 → 10/8 (quality-parity pass, 2026-07-29): +4 px
  /// waveform width in the tightest size, so compact bars keep pace with
  /// normal/mini.
  static const OverlayLayoutSpec compact = OverlayLayoutSpec(
    padH: 16,
    closeArm: 3.5,
    closeStroke: 1.4,
    closeOffset: 5,
    dotInset: 20,
    dotRadius: 3.5,
    timerGap: 12,
    timerFontSize: 12,
    waveStartGap: 10,
    waveEndGap: 8,
    stopSize: 10,
    lineStrokeMin: 1.5,
  );

  /// Mini-size layout. The mini painter branch renders the waveform while
  /// recording, spinner + status label while transcribing (which consumes
  /// [dotInset]/[timerGap]/[timerFontSize]) and a centred status icon for
  /// done/error; the close/stop values here are conservative fallbacks that
  /// are never drawn in practice.
  static const OverlayLayoutSpec mini = OverlayLayoutSpec(
    padH: 12,
    closeArm: 3.0,
    closeStroke: 1.2,
    closeOffset: 0,
    dotInset: 4,
    dotRadius: 2.5,
    timerGap: 8,
    timerFontSize: 10,
    waveStartGap: 8,
    waveEndGap: 0,
    stopSize: 8,
    lineStrokeMin: 1.5,
  );

  /// Nano-size layout. Only the waveform (while recording) and the centred
  /// spinner / done / error glyph are drawn; [dotRadius] sizes the spinner
  /// (×[OverlayDesignSpec.transcribingSpinnerRadiusFactor]), the rest of the
  /// values are fallbacks that never reach the screen.
  static const OverlayLayoutSpec nano = OverlayLayoutSpec(
    padH: 8,
    closeArm: 2.5,
    closeStroke: 1.0,
    closeOffset: 0,
    dotInset: 4,
    dotRadius: 3.2,
    timerGap: 4,
    timerFontSize: 8,
    waveStartGap: 4,
    waveEndGap: 0,
    stopSize: 6,
    lineStrokeMin: 1.5,
  );
}

/// Platform vibrancy material for the overlay native window.
///
/// Decided in Phase-0 spike (spike-notes.md 2026-06-29):
/// - macOS: `hudWindow` — real NSVisualEffectView blur, perf ~1 ms/frame avg.
/// - Windows: `acrylic` — flutter_acrylic Acrylic (pending Windows test).
/// - Linux / unknown: `flat` — tinted capsule fill, no OS-level blur.
enum OverlayVibrancyMaterial {
  /// macOS NSVisualEffectMaterial.hudWindow (Phase-0 approved, best optics).
  hudWindow,

  /// Windows Acrylic via flutter_acrylic (planned).
  acrylic,

  /// Windows Mica via flutter_acrylic (alternative to acrylic).
  mica,

  /// Tinted flat fill, no OS blur — Linux default / universal fallback.
  flat,
}

/// Platform-aware vibrancy material selection for the overlay window.
///
/// Consumed by the platform controllers (Swift / C++ / Linux) to configure
/// the native window's visual effect layer. The Flutter widget consumes
/// [forPlatform] to select the correct fill opacity.
@immutable
class OverlayVibrancySpec {
  const OverlayVibrancySpec({
    required this.macOS,
    required this.windows,
    required this.linux,
  });

  /// Material for macOS overlay windows.
  final OverlayVibrancyMaterial macOS;

  /// Material for Windows overlay windows.
  final OverlayVibrancyMaterial windows;

  /// Material for Linux overlay windows (always flat — no OS blur available).
  final OverlayVibrancyMaterial linux;

  /// Resolves the material for the given [platform] string
  /// (`'macos'`, `'windows'`, `'linux'`). Anything unknown → [flat].
  OverlayVibrancyMaterial forPlatform(String platform) => switch (platform) {
    'macos' => macOS,
    'windows' => windows,
    'linux' => linux,
    _ => OverlayVibrancyMaterial.flat,
  };
}

/// Signature arc motion parameters.
///
/// Govern the two animated events in the recording arc:
/// 1. **Appear**: capsule springs in from [appearScale] → 1.0 + opacity 0 → 1.
///    Curve = easeOutCubic (WpMotion.spring), no overshoot, gentle.
/// 2. **State-transition crossfade**: brief opacity fade between arc states.
///
/// All durations are subject to `MediaQuery.disableAnimations` — callers must
/// use `WpMotion.durationFor(context, duration)` so reduced-motion collapses
/// everything to Duration.zero (instant state change, no movement).
@immutable
class OverlayArcMotion {
  const OverlayArcMotion({
    required this.appearDuration,
    required this.appearCurve,
    required this.appearScale,
    required this.stateTransitionDuration,
    required this.stateTransitionCurve,
    required this.releaseOutDuration,
    this.statusRevealDuration = const Duration(milliseconds: 280),
  });

  /// Duration of the crossfade OUT of the recording state into transcribing.
  ///
  /// Longer than the generic [stateTransitionDuration] on purpose: the
  /// service feeds the waveform pipeline decaying samples for
  /// [OverlayDesignSpec.waveformReleaseOutMs] after that transition, and the
  /// outgoing (recording) crossfade layer is what paints them. A shorter
  /// crossfade drops that layer mid-decay and hands over to the flat rest
  /// waveform — the abrupt waveform stop reported on the mini overlay. Keep
  /// this equal to the release-out window.
  final Duration releaseOutDuration;

  /// Duration of the crossfade INTO the done/error end states (design
  /// pass). The generic 150 ms crossfade left the done check — the emotional
  /// pay-off of the whole product — half-formed; 280 ms gives the stroke-
  /// first draw-on room to land while staying inside the calm soft-cap.
  /// Recording/transcribing transitions keep [stateTransitionDuration].
  final Duration statusRevealDuration;

  /// Duration of the capsule spring-in (appear).
  ///
  /// Phase-0 cap: Soft-Cap 300 ms / Hard-Cap 700 ms. Set to [smooth] (300 ms)
  /// so the perceived snap is ~250 ms.
  final Duration appearDuration;

  /// Easing for the spring-in. Must be non-overshooting.
  ///
  /// Phase-0 decision: easeOutCubic (mirrors `WpMotion.spring`).
  final Curve appearCurve;

  /// Initial scale from which the capsule springs in (e.g. 0.88 → 1.0).
  ///
  /// Subtle — the viewer notices movement, not a dramatic jump-cut.
  final double appearScale;

  /// Duration of the state-transition crossfade (recording→transcribing etc.).
  final Duration stateTransitionDuration;

  /// Easing for the state-transition crossfade.
  final Curve stateTransitionCurve;

  /// Gentle spring for the pill-width morph (issue 10 — dynamic pill growth).
  ///
  /// Critically-damped Gentle preset (mass=1, stiffness=170, damping=26 ≈ 2√170).
  /// No overshoot; a clean, soft width transition between recording-arc states.
  /// Identical parameters to [WpMotion.springDescription]; mirrored here so
  /// [OverlayDesignSpec] consumers need only one import.
  static const SpringDescription pillSpring = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 26,
  );
}

/// Mic-glyph geometry for the floating button, expressed as **ratios of the
/// disc diameter** so the glyph scales identically across the settings-owned
/// button sizes (44/56/80). Every ratio is the approved spike value
/// (`spike/lib/main.dart` `_mic`, tuned at a 56 px disc) divided by 56, so a
/// 56 px disc reproduces the spike pixel-for-pixel and the painter carries no
/// magic numbers.
@immutable
class FloatingButtonMicSpec {
  const FloatingButtonMicSpec({
    required this.bodyWidthRatio,
    required this.bodyHeightRatio,
    required this.bodyRadiusRatio,
    required this.bodyCenterDyRatio,
    required this.arcRadiusRatio,
    required this.arcCenterDyRatio,
    required this.arcStartAngle,
    required this.arcSweepAngle,
    required this.strokeRatio,
    required this.stemTopDyRatio,
    required this.stemBottomDyRatio,
  });

  /// Mic-capsule body width ÷ diameter (spike `9` in a 56 disc).
  final double bodyWidthRatio;

  /// Mic-capsule body height ÷ diameter (spike `14`).
  final double bodyHeightRatio;

  /// Mic-capsule corner radius ÷ diameter (spike `4.5`).
  final double bodyRadiusRatio;

  /// Body-centre vertical offset from the disc centre ÷ diameter (spike `-4`,
  /// i.e. the capsule sits above centre).
  final double bodyCenterDyRatio;

  /// Cradle-arc radius ÷ diameter (spike `8.5`).
  final double arcRadiusRatio;

  /// Cradle-arc centre vertical offset from the disc centre ÷ diameter
  /// (spike `-1`).
  final double arcCenterDyRatio;

  /// Cradle-arc start angle in radians (spike `0.35`); scale-free.
  final double arcStartAngle;

  /// Cradle-arc sweep angle in radians (spike `π − 0.7`); scale-free.
  final double arcSweepAngle;

  /// Glyph stroke width ÷ diameter (spike `2`).
  final double strokeRatio;

  /// Stem top endpoint vertical offset ÷ diameter (spike `7.5`).
  final double stemTopDyRatio;

  /// Stem bottom endpoint vertical offset ÷ diameter (spike `11`).
  final double stemBottomDyRatio;

  /// The approved spike mic geometry (`_mic`), referenced to a 56 px disc.
  static const FloatingButtonMicSpec spike = FloatingButtonMicSpec(
    bodyWidthRatio: 9 / 56,
    bodyHeightRatio: 14 / 56,
    bodyRadiusRatio: 4.5 / 56,
    bodyCenterDyRatio: -4 / 56,
    arcRadiusRatio: 8.5 / 56,
    arcCenterDyRatio: -1 / 56,
    arcStartAngle: 0.35,
    arcSweepAngle: math.pi - 0.7,
    strokeRatio: 2 / 56,
    stemTopDyRatio: 7.5 / 56,
    stemBottomDyRatio: 11 / 56,
  );
}

/// Floating-button appearance — the V2 style (ADR 0002): a white disc with a
/// dark mic glyph and a hairline border. No accent ring, no light effect.
///
/// The button diameter is fixed at [buttonDiameter] (56 dp) — the approved
/// design-token value. The former size picker (Small/Normal/Large) was removed
/// in issue 11 because the Zielgruppe does not benefit from micro-tuning the
/// button chrome. Per-state icon tinting reuses
/// [OverlayDesignSpec.glyphStopsFor] (consumed in issue 08).
@immutable
class FloatingButtonSpec {
  /// Fixed button disc diameter in logical pixels (design-token value, ADR 0002).
  ///
  /// Formerly `FloatingButtonSize.normal.pixels` (56); the user-facing size
  /// picker was removed in issue 11. All rendering code should reference this
  /// constant instead of a hard-coded literal.
  static const double buttonDiameter = 56.0;

  const FloatingButtonSpec({
    required this.discColor,
    required this.discFillOpacity,
    required this.borderColor,
    required this.borderWidth,
    required this.borderInset,
    required this.iconRatio,
    required this.mic,
    required this.edgeColor,
    required this.shadowColor,
  });

  /// 1 px outer edge of the disc (UX-048); transparent on light presets.
  final Color edgeColor;

  /// Painted drop shadow of the disc, alpha included (UX-048).
  final Color shadowColor;

  /// Flat disc fill (ticket flat pass: no tint gradient). White on the default
  /// button; the preset's surface colour for a background.
  final Color discColor;

  /// Base opacity of the flat disc fill (spike `0.95`). The opacity setting
  /// scales the disc chrome (fill + shadow) by `discFillOpacity × opacity`; the
  /// mic glyph stays fully opaque (accessibility, mirrors the overlay).
  final double discFillOpacity;

  /// Hairline border `#1A101828`.
  final Color borderColor;

  /// Border stroke width (logical pixels, pre-DPR).
  final double borderWidth;

  /// Border inset from the disc radius (spike draws the stroke at `r − 0.5`).
  final double borderInset;

  /// Glyph size as a fraction of the disc diameter (24 in a 56 disc).
  final double iconRatio;

  /// Mic-glyph geometry (ratios of the disc diameter).
  final FloatingButtonMicSpec mic;
}

/// The overlay/button design Single Source of Truth.
abstract final class OverlayDesignSpec {
  /// Factor by which every compact content metric is scaled down from normal.
  /// `2/3` maps the normal 24 px waveform to the compact 16 px and the normal
  /// 15 pt timer to the compact 10 pt.
  static const double compactScale = 2 / 3;

  /// Base alpha of the capsule's tint gradient fill.
  ///
  /// **Dock-glass decision (Maintainer, 2026-07-29):** lowered from `0.66` to
  /// `0.35` so the capsule reads as "im Grunde bloß ein Glaskörper drumrum" —
  /// like the macOS Dock. The researched no-blur glass recipe (Liquid-Glass /
  /// glassmorphism analyses): without a compositor blur the FILL cannot carry
  /// the glass identity — it only tints; the identity moves to the highlight
  /// layer (Fresnel rim light, inner edge band, specular top streak — see the
  /// glass constants below). Cross-platform (pure Dart in [WpOverlayPainter],
  /// identical on macOS/Windows/Linux); no OS-level blur is used.
  ///
  /// Trade-off, explicitly sanctioned: below the old text-safety product
  /// (`0.66 × opacity`), worst-case timer/status-text contrast now depends on
  /// the desktop behind the capsule. The content layer itself stays fully
  /// opaque, and the waveform/icons carry their own ≥3:1 guarantees.
  ///
  /// The opacity setting scales ONLY the translucent pill chrome (fill gradient,
  /// painted shadow, border) by `fillOpacityFactor × opacity`; the content layer
  /// (text, icons, dot, waveform, stop, timeline) always stays fully opaque
  /// (accessibility, ADR 0002).
  /// (0.35 → 0.22 → 0.14 across the Dock-glass rounds, 2026-07-29 —
  /// together with the shadow knock-out under the capsule, see
  /// [WpOverlayPainter], the pill now reads as a bare glass body. The content
  /// no longer depends on the fill at all: every dark-ink glyph became a
  /// white glyph with a dark outline — see [OverlayBackground.ink].)
  /// Superseded for the fill by the opaque flat fill (UX-013, 2026-10-17; ticket
  /// flat pass): no longer applied to any painted layer; kept only as a
  /// documented value.
  static const double fillOpacityFactor = 0.14;

  /// One slow overlay cycle. Phase-locks the transcribing bars and the
  /// silhouette wobble; phase 0 renders the static frame (reduced motion and
  /// the goldens live there).
  static const Duration liquidDriftPeriod = Duration(seconds: 8);

  // -- Liquid-glass silhouette wobble (Maintainer-Interview 2026-07-30) ------
  //
  // The capsule OUTLINE itself deforms — the "flüssiges Gummibärchen im
  // Windhauch": a continuous, barely-perceptible base undulation plus a
  // slightly stronger deformation on loud speech (audio level — explicitly
  // requested in the interview). Construction: the capsule perimeter is
  // sampled into [liquidWobbleSamples] equidistant points, each displaced
  // along its outward normal by two counter-travelling low-spatial-frequency
  // waves (2 and 3 periods around the perimeter; 1 and 2 time-cycles per
  // [liquidDriftPeriod] loop, so the motion is seamless at the wrap), then
  // closed with Catmull-Rom smoothing — organic bulges, never jitter.
  //
  // Calibration (round 2, "eingeschlossenes Wasser"): base ±1.2 px; the
  // audio share adds up to ±2.4 px at full level AND runs as its OWN wave
  // shape — a faster, finer ripple (5 perimeter periods, 6 time-cycles per
  // loop) so the voice reaction reads as a distinct component, not just
  // "more wind". Total ≤ 3.6 px, comfortably inside the 8 px
  // [shadowPadding] so the native window never clips. Reduced-motion and
  // the settings preview render the perfectly rigid capsule (amplitude 0).

  /// Base ("Windhauch") wobble amplitude in logical pixels.
  static const double liquidWobbleBaseAmplitudePx = 1.2;

  /// Additional ripple amplitude at full audio level (own, finer waveform —
  /// see [WpOverlayPainter]).
  static const double liquidWobbleAudioAmplitudePx = 2.4;

  /// Number of perimeter sample points (Catmull-Rom smoothed).
  static const int liquidWobbleSamples = 28;

  /// Recommended slider floor for the opacity setting (ADR 0002). Guidance
  /// for the USER opacity slider only — it scales the whole chrome by
  /// `fillOpacityFactor × opacity`. Since the Dock-glass decision
  /// (2026-07-29) the base [fillOpacityFactor] itself sits below the old
  /// text-safety product by explicit maintainer choice; this floor keeps the
  /// slider from thinning the glass body further into invisibility.
  static const double minRecommendedOpacity = 0.65;

  // -- Universal-legibility glyph scheme (final: soft shadow, 2026-07-30) ----
  //
  // The overlay floats over ARBITRARY desktop content, and the painter has
  // no backdrop sampling and no OS blur — so no single ink colour can work
  // on both light and dark desktops. All neutral glyphs (timer/status text,
  // close ✕, stop square) render WHITE over a soft blurred dark drop shadow
  // (subtitle technique; Maintainer-Entscheid nach dem Varianten-Vergleich —
  // softShadow schlug gradientScrim und hairlineOutline). The dot, waveform
  // and done/error icons keep their semantic mid-tone colours (mid-tones
  // hold ≥3:1 against both white and black extremes and need no shadow).
  // Since the opaque presets (ticket) the glyphs sit on the pill's own fill,
  // so the shadow is drawn only where the desktop shows through: glass or a
  // fill below full opacity (north-star review #25).

  /// Shadow alpha.
  static const double glyphShadowOpacity = 0.85;

  /// Gaussian blur sigma of the glyph shadow (soft, no hard ring).
  static const double glyphShadowBlurSigma = 1.75;

  /// Offset of the glyph shadow (slightly downward, like cast light).
  static const Offset glyphShadowOffset = Offset(0, 0.75);

  // -- Capsule chrome (painted shadow + capsule shape) -----------------------

  /// Painted soft-shadow colour (cross-platform, no OS blur). Alpha is applied
  /// at paint time as `shadowOpacity × opacity`.
  static const Color shadowColor = Color(0xFF000000);

  /// Painted-shadow opacity at full master opacity (spike `0.20`).
  static const double shadowOpacity = 0.20;

  /// Painted-shadow Gaussian blur sigma, shared by the pill and the floating
  /// button. A Gaussian stays visible up to about three sigma, and the native
  /// windows reserve only [shadowPadding] around the shape — the former 9.0
  /// reached about 27 px and ended in a hard edge at the window border. 2.0
  /// plus [shadowOffset] fades out inside the padding.
  static const double shadowBlur = 2.0;

  /// Painted-shadow offset (cast downward; the spike's `(0, 3)` shortened so
  /// the shadow stays inside [shadowPadding]).
  static const Offset shadowOffset = Offset(0, 1.25);

  /// Second, tight contact-shadow layer painted beneath [shadowBlur]/
  /// [shadowOpacity] (cross-platform glass polish pass) — the small-blur half
  /// of the same two-layer shadow language [WpShadows.card] already uses
  /// elsewhere in the app, so the overlay's depth matches the rest of the
  /// product instead of standing alone on a single soft shadow.
  static const double contactShadowOpacity = 0.12;

  /// Contact-shadow blur sigma — tight, grounds the capsule against the
  /// desktop directly beneath it.
  static const double contactShadowBlur = 2.0;

  /// Contact-shadow offset.
  static const Offset contactShadowOffset = Offset(0, 1);

  /// Padding reserved on every side of the pill inside the native window so the
  /// painted shadow is not clipped (spike: a 64 px pill in an 80 px window →
  /// 8 px each side). [windowSize] adds this; the native shells must match it.
  static const double shadowPadding = 8.0;

  /// Resolves the hand-tuned layout for [variant].
  static OverlayLayoutSpec layoutFor(OverlaySizeVariant variant) =>
      switch (variant) {
        OverlaySizeVariant.normal => OverlayLayoutSpec.normal,
        OverlaySizeVariant.compact => OverlayLayoutSpec.compact,
        OverlaySizeVariant.mini => OverlayLayoutSpec.mini,
        OverlaySizeVariant.nano => OverlayLayoutSpec.nano,
      };

  /// Full native-window size for one pill = pill box + [shadowPadding] on every
  /// side. The pill itself is painted at `Offset(shadowPadding, shadowPadding)`.
  ///
  /// Legacy two-size convenience — see [windowSizeFor].
  static Size windowSize({required bool compact}) => windowSizeFor(
    compact ? OverlaySizeVariant.compact : OverlaySizeVariant.normal,
  );

  /// Full native-window size for [variant] = pill box + [shadowPadding] on
  /// every side. Normal `346 × 80`, compact `236 × 56`, mini `166 × 50`,
  /// nano `104 × 40` — the native shells must mirror these exactly.
  static Size windowSizeFor(OverlaySizeVariant variant) {
    final s = sizeFor(variant);
    return Size(s.width + 2 * shadowPadding, s.height + 2 * shadowPadding);
  }

  /// Smallest comfortable pointer target of the close glyph, per axis. The
  /// glyph itself is only 5 to 8 px wide; a click on it must still land.
  static const double closeHitMinExtent = 32.0;

  /// Window-local hit area of the pill's close glyph (the X), or null when
  /// the pill paints none.
  ///
  /// Single source for the geometry `WpOverlayPainter._drawContent` uses to
  /// place the X: centre at `pill.left + padH + closeOffset`, vertically the
  /// pill centre, where the pill is centred in the window at [pillWidth]
  /// (default: the full size width). The painted X shows only when the look
  /// has [showCancel] and the size paints full content (mini and nano do
  /// not). The rect is widened to [closeHitMinExtent] on both axes and
  /// extends to the pill's left edge, so a click beside the glyph still
  /// cancels, never toggles recording.
  static Rect? closeHitRect({
    required OverlaySizeVariant variant,
    required bool showCancel,
    double? pillWidth,
  }) {
    final spec = sizeFor(variant);
    if (!showCancel || spec.minimalContent) return null;
    final layout = layoutFor(variant);
    final width = pillWidth ?? spec.width;
    final pillLeft = shadowPadding + (spec.width - width) / 2;
    final centerX = pillLeft + layout.padH + layout.closeOffset;
    final centerY = shadowPadding + spec.height / 2;
    final halfW = math.max(closeHitMinExtent, 2 * layout.closeArm) / 2;
    final halfH = math.max(closeHitMinExtent, spec.height) / 2;
    return Rect.fromLTRB(
      math.min(pillLeft, centerX - halfW),
      centerY - halfH,
      centerX + halfW,
      centerY + halfH,
    );
  }

  // -- Notice card (overlay F2) -----------------------------------------------

  /// Family of all overlay text (pill and notice card); [kWpFontFallback]
  /// follows it.
  static const String fontFamily = 'Inter';

  /// The notice card at its smallest: as wide as the normal pill, tall
  /// enough for a title, two body lines and one row of buttons, with air
  /// between body and buttons (120 clipped the buttons when the body wrapped,
  /// e.g. in Russian). It replaces the pill of any size while a microphone
  /// problem or the duration limit needs a decision. A card whose text or
  /// buttons need more room grows taller (#1845, [noticeWindowSizeFor]).
  static const Size noticeCardSize = Size(330, 148);

  /// Native-window size of the smallest notice card (`346 × 164`).
  static Size get noticeWindowSize =>
      noticeWindowSizeFor(noticeCardSize.height);

  /// Native-window size of a notice card [cardHeight] tall. The snapshot
  /// sends its height as `noticeHeight` with the size class `notice`; the
  /// shells size their window from it and fall back to 164 without it.
  static Size noticeWindowSizeFor(double cardHeight) => Size(
    noticeCardSize.width + 2 * shadowPadding,
    cardHeight + 2 * shadowPadding,
  );

  /// Gap between stacked notice buttons and between body and footer.
  static const double noticeStackGap = 8.0;

  /// Corner radius of the notice card.
  static const double noticeCardRadius = 16.0;

  /// Inner padding of the notice card.
  static const double noticeCardPadding = 14.0;

  /// Title and body font sizes of the notice card.
  static const double noticeTitleFontSize = 14.0;
  static const double noticeBodyFontSize = 12.0;

  /// Height of a notice card button; at least the 32 pt hit target.
  static const double noticeButtonHeight = 32.0;

  /// Footer of the notice card (#781): font size, gap to the buttons, ink
  /// steps tried from quiet to full (see [OverlayThemeColors.noticeFooterInk])
  /// and the contrast the footer must reach on the card body. The font is the
  /// small type step and never shrinks below it (#1845): a long footer wraps
  /// and the card grows instead.
  static const double noticeFooterFontSize = WpTypography.small;
  static const double noticeFooterGap = 6.0;
  static const List<double> noticeFooterInkAlphas = [0.65, 0.82, 1.0];
  static const double noticeFooterMinContrast = 4.5;

  /// Ink steps of the notice card body (#728), tried like the footer's.
  static const List<double> noticeBodyInkAlphas = [0.82, 1.0];

  /// Largest text scale the notice card follows (system font size, #728).
  /// The card text grows with the system font up to this factor; the card
  /// grows with it (#1845).
  static const double noticeMaxTextScale = 1.3;

  /// Height of the close cross of the notice card (width follows its label).
  static const double noticeCloseHeight = 24.0;

  // -- Stop square (recording only) ------------------------------------------

  /// Stop-square corner radius (spike `2`).
  static const double stopSquareRadius = 2.0;

  /// Corner radius of the rounded-rect form as a share of its height
  /// (ticket). A fixed radius turned the small sizes into near-pills (12 px on
  /// a 34 px mini is 35 %); a constant share keeps the same silhouette in
  /// every size — 12 px at the normal 64 px. The pill uses half its height.
  static const double roundedRectRadiusShare = 0.1875;

  /// Rounded-rect corner radius for a capsule of [height].
  static double roundedRectRadiusFor(double height) =>
      height * roundedRectRadiusShare;

  /// Stop-square fill opacity over the content colour (spike `0.9`).
  static const double stopSquareOpacity = 0.9;

  // -- Bottom progress timeline (inset hairline) -----------------------------

  /// Timeline inset from the pill bottom edge (spike `bottom − 6`).
  static const double timelineInsetBottom = 6.0;

  /// Timeline stroke width (spike `2`).
  static const double timelineStrokeWidth = 2.0;

  /// Trailing-stop opacity of the timeline accent gradient (spike `0.25`).
  static const double timelineEndOpacity = 0.25;

  /// Radius of the small bright leading dot drawn at the current progress
  /// position on the timeline (cross-platform glass polish pass) — pinpoints
  /// "you are here" more precisely than the fading line end alone.
  static const double timelineLeadDotRadius = 2.2;

  // -- Waveform line rendering (thin accent lines) ---------------------------

  // Mirrored-bar waveform (Maintainer decision, 2026-07-29): the bars are
  // FULLY OPAQUE filled capsules, mirrored around the centre axis
  // (Spotify/Voice-Memos register, in WhisPaste's own accent language) —
  // no alpha wash, no light effect (explicitly rejected: "macht das nur
  // schwammiger"), hard crisp edges. Identity lives in the "energy axis":
  // every bar carries a vertical in-bar gradient that is brightest at the
  // centre line and shades toward the tips, so quiet bars still show a
  // bright core and loud bars grow dark-tipped amplitude. The recency
  // "playhead" (trailing bars) is encoded through a wider bar plus a hotter
  // core — never through washing the history out.

  /// Alpha of the recording bars — fully opaque, maximum contrast
  /// (accent `#0887A8` over worst-case white ≈ 4.2:1).
  static const double waveformActiveOpacity = 1.0;

  /// Alpha of the leading (history) bars while recording — also fully
  /// opaque; active vs. muted reads through width + core brightness.
  static const double waveformMutedLineOpacity = 1.0;

  /// Alpha of the waveform shown outside recording (transcribing's processing
  /// ripple included — decorative rest/processing state, deliberately
  /// quieter than the live bars).
  static const double waveformInactiveStateOpacity = 0.5;

  /// Visual bar width as a fraction of the per-bar slot (the remainder is
  /// the gap) — chunky enough to read as a bar, open enough to stay a
  /// rhythm, never a solid block.
  static const double waveformBarFillFactor = 0.62;

  /// Slot fraction for the trailing active bars — the playhead is wider.
  static const double waveformActiveBarFillFactor = 0.74;

  /// White fraction mixed into the accent at the CENTRE of the bar gradient
  /// for the muted (history) bars — the "energy axis" core.
  static const double waveformCoreMutedLightFraction = 0.10;

  /// White fraction at the centre for the active trailing bars — the hotter
  /// playhead core.
  static const double waveformCoreActiveLightFraction = 0.35;

  /// Black fraction mixed into the accent at BOTH bar tips — mirrored
  /// shading that grounds the bars and adds contrast at the extremes.
  static const double waveformTipShadeFraction = 0.15;

  /// Fraction of the pill height the loudest bar may reach (spike `0.6`).
  static const double waveformHeightFactor = 0.60;

  /// Recording chips (SW-10, ticket 13 part 3): the language and the effective
  /// profile sit in one outlined pill badge right after the timer, e.g.
  /// `0:07 · DE · Schnell`. Only the normal pill is tall enough
  /// ([chipMinPillHeight]); compact and mini stay unchanged.
  static const double chipFontSize = 11.0;

  static const double chipMinPillHeight = 64.0;
  static const double chipHeight = 16.0;
  static const double chipPadH = 6.0;
  static const double chipGap = 6.0;
  static const double chipOutlineWidth = 1.0;
  static const double chipOutlineOpacity = 0.4;

  /// The waveform keeps at least this width. A chip only takes the space the
  /// timer leaves beyond it; a long profile name is shortened with an ellipsis
  /// first, and the chip is dropped when even the language would not fit.
  static const double chipMinWaveWidth = 88.0;

  /// Flat rest level used for the faint waveform outside recording (spike
  /// `0.06`) — the baseline the transcribing ripple (below) oscillates
  /// around.
  static const double waveformRestLevel = 0.06;

  /// Peak amplitude added on top of [waveformRestLevel] for the transcribing
  /// bar ripple (`WpOverlayPainter.transcribingBarLevel`) — the "processing"
  /// signal for the state that otherwise has no live audio to visualise.
  /// Deliberately far below a live recording bar's headroom (which reaches
  /// up to `1.0`) so transcribing never reads as "still listening".
  static const double waveformTranscribingRippleAmplitude = 0.40;

  /// Length of the waveform release-out that follows `recording →
  /// transcribing`, in milliseconds.
  ///
  /// Single source of truth for the two halves that have to agree on it:
  /// `FloatingOverlayService.releaseOutDurationMs` keeps ticking the pipeline
  /// with silence for exactly this long (so the bars decay instead of
  /// freezing), and [OverlayArcMotion.releaseOutDuration] keeps the content
  /// crossfade — the only path through which those decaying bars reach the
  /// canvas — alive for the same span. When the two drifted apart the
  /// waveform visibly snapped to the flat [waveformRestLevel] frame halfway
  /// through the decay.
  static const int waveformReleaseOutMs = 300;

  // -- Transcribing state identity (state-distinction pass, 2026-08-17) ------
  //
  // Recording and transcribing used to share the cyan accent and the pulsing
  // dot; over the always-moving waveform the two states were hard to tell
  // apart at a glance (maintainer report), loudest on mini where no text is
  // painted. Transcribing now owns a distinct identity, identical across all
  // three sizes: the amber [OverlayThemeColors.transcribingAccent] on the
  // ripple, plus a small rotating open arc (the classic "working" glyph)
  // where recording pulses its dot. The arc is driven by the existing
  // liquid-glass phase — [transcribingSpinnerTurnsPerLoop] integer turns per
  // [liquidDriftPeriod] loop keep the rotation seamless at the phase wrap
  // and add NO new AnimationController; reduced-motion/preview rest at the
  // static phase-0 frame like every other phase-driven motion.

  /// Spinner arc radius as a factor of the per-size [OverlayLayoutSpec.
  /// dotRadius], so the glyph scales with the size variant exactly like the
  /// recording dot it replaces.
  static const double transcribingSpinnerRadiusFactor = 1.7;

  /// Spinner stroke width as a factor of the per-size dot radius.
  static const double transcribingSpinnerStrokeFactor = 0.55;

  /// Hard floor for the spinner stroke width in logical pixels.
  static const double transcribingSpinnerMinStrokePx = 1.5;

  /// Arc sweep — 270°, open enough to read as motion, closed enough to read
  /// as a ring.
  static const double transcribingSpinnerSweep = 1.5 * math.pi;

  /// Full rotations per [liquidDriftPeriod] loop (integer → seamless wrap).
  /// 10 turns / 8 s = 1.25 rev/s — clearly "working", still calm.
  static const int transcribingSpinnerTurnsPerLoop = 10;

  /// Alpha of the faint full-circle track beneath the bright arc — anchors
  /// the arc as a spinner (not a stray crescent) over busy desktops. Same
  /// trailing-alpha register as [timelineEndOpacity].
  static const double transcribingSpinnerTrackOpacity = 0.25;

  // Label-in-the-stream composition (waveform+text pass, 2026-08-17): the
  // first cut of the state-distinction pass replaced the mini/compact
  // waveform with the status label alone, which read as "nur reiner Text"
  // (maintainer feedback). Transcribing now composes BOTH in every size:
  // the amber ripple waveform spans the full zone behind the label, and the
  // bars directly beneath the label sink toward the rest baseline through a
  // smoothstep envelope — the stream visibly parts around the label and
  // the travelling ripple flows through the notch. The label keeps its full
  // measured width (no ellipsis pressure from a reserved wave zone), and
  // the notch needs no new controller — it is a pure per-bar attenuation.

  /// Remaining fraction of the processing-ripple amplitude directly beneath
  /// the status label. Deliberately > 0: the bars sink to calm amber beads,
  /// never to a dead gap — the stream stays continuous under the label.
  static const double transcribingWaveNotchFloor = 0.18;

  /// Width of the smoothstep ramp on each side of the label notch, in
  /// logical pixels — soft shoulders, no hard cut into the ripple.
  static const double transcribingWaveNotchRampPx = 12.0;

  /// Horizontal clearance between the label's measured edge and the start
  /// of the notch ramp.
  static const double transcribingWaveNotchPadPx = 6.0;

  // -- Secondary text line (guided-sequence frames) --------------------------

  /// Font-size factor of the secondary line relative to the layout's
  /// `timerFontSize` (14 px normal → ~11 px). Used identically by the
  /// painter and by [pillWidthForText]'s measurement so the sizing never
  /// drifts from what gets drawn.
  static const double secondaryTextScale = 0.78;

  /// Vertical offset of the primary line's centre above the pill centre
  /// when a secondary line is painted (two-line transcribing composition).
  static const double secondaryTextPrimaryDy = -8.0;

  /// Vertical offset of the secondary line's centre below the pill centre.
  static const double secondaryTextSecondaryDy = 10.0;

  /// Opacity of the secondary line's white fill — quieter than the primary
  /// instruction, still readable over the glass.
  static const double secondaryTextOpacity = 0.78;

  // -- Font weights (theme-wide, not scaled) ---------------------------------

  /// Primary label/done/error weight (semibold).
  static const FontWeight primaryFontWeight = FontWeight.w600;

  // -- Status-icon reveal (cross-platform glass polish pass) -----------------

  /// Initial scale of the error status icon's fade-in-and-settle entrance —
  /// the same calm, no-overshoot register as [OverlayArcMotion.appearScale],
  /// applied to a single icon instead of the whole capsule. Driven by the
  /// existing state-transition crossfade fraction; adds no new controller.
  static const double errorIconRevealScaleStart = 0.85;

  // -- Chrome neutrality (maintainer decision, 2026-07-28) -------------------
  //
  // The capsule CHROME (fill, sheen, border, shadow) is strictly state-
  // neutral: fill/sheen are the fixed tint gradient + white sheen, the border
  // is always the fixed accent hairline [OverlayThemeColors.capsuleBorder],
  // and the shadow is always neutral black. A per-state border re-hue
  // (formerly `borderColorFor`) was removed after live feedback: over a small
  // translucent capsule the red recording stroke read as a diffuse pink
  // "light effect" — exactly the effect ADR 0002 forbids. State identity lives ONLY
  // in crisp content glyphs: the live waveform, the done
  // check (green) and the error icon/text (red).

  // -- Theme colours ---------------------------------------------------------

  /// The colour set for [background] paired with [wave] (ticket, ADR 0024).
  static OverlayThemeColors colorsFor({
    OverlayBackground background = OverlayBackground.marine,
    OverlayWave wave = OverlayWave.cyan,
    OverlayDesignTheme glassTone = OverlayDesignTheme.dark,
  }) => OverlayThemeColors.resolve(
    background: background,
    wave: wave,
    glassTone: glassTone,
  );

  /// Glyph colour stops of the floating button's mic for [state], taken from
  /// the resolved [colors] of the background, so an amber background gets the
  /// legible signal (ticket). Flat: both stops are the same colour (ADR 0024).
  ///
  /// While recording the mic takes the wave colour, like the dot in the pill
  /// (ADR 0024, Nachtrag 2026-10-22). Only where the wave is not legible on the
  /// fill (3:1) does it fall back to the ink, the same rule the signals use.
  static List<Color> glyphStopsFor(
    OverlayDesignState state,
    OverlayThemeColors colors,
  ) {
    final color = switch (state) {
      OverlayDesignState.recording =>
        contrastRatio(colors.accent, colors.capsuleFill) >= 3.0
            ? colors.accent
            : colors.ink,
      OverlayDesignState.transcribing => colors.transcribingAccent,
      OverlayDesignState.done => colors.success,
      OverlayDesignState.error => colors.error,
    };
    return [color, color];
  }

  // -- Waveform --------  // -- Waveform --------------------------------------------------------------

  /// Bars of the live waveform before any size reduces them (see [waveform]).
  static const int waveformBarCount = 22;

  /// Waveform parameters. The live levels come in at [waveformBarCount]; the
  /// sizes that draw fewer bars reduce them ([OverlaySizeSpec.waveformBarCount]).
  static const WaveformSpec waveform = WaveformSpec(
    barCount: waveformBarCount,
    minBarHeightPx: 3.0,
    attackTimeConstantMs: 20,
    // Short enough that the gap between syllables (~150–250 ms) shows as a
    // dip, so speech moves the bars instead of holding them near the top.
    releaseTimeConstantMs: 120,
  );

  // -- Sizes -----------------------------------------------------------------

  /// Normal (full) pill spec.
  static const OverlaySizeSpec normalSize = OverlaySizeSpec.normal;

  /// Compact (small) pill spec — content derived from [normalSize].
  static final OverlaySizeSpec compactSize = OverlaySizeSpec.compact;

  /// Mini (waveform-first) pill spec — explicit anchors, minimal content.
  static const OverlaySizeSpec miniSize = OverlaySizeSpec.mini;

  /// Nano (waveform-only status mark) pill spec — explicit anchors.
  static const OverlaySizeSpec nanoSize = OverlaySizeSpec.nano;

  /// Resolves the size spec for the compact flag.
  ///
  /// Legacy two-size convenience — see [sizeFor].
  static OverlaySizeSpec size({required bool compact}) =>
      compact ? compactSize : normalSize;

  /// Resolves the size spec for [variant].
  static OverlaySizeSpec sizeFor(OverlaySizeVariant variant) =>
      switch (variant) {
        OverlaySizeVariant.normal => normalSize,
        OverlaySizeVariant.compact => compactSize,
        OverlaySizeVariant.mini => miniSize,
        OverlaySizeVariant.nano => nanoSize,
      };

  // -- Motion ----------------------------------------------------------------

  /// Signature recording-arc motion parameters (Phase-0, issue 09).
  ///
  /// - [OverlayArcMotion.appearDuration]: 300 ms (WpMotion.smooth soft-cap).
  /// - [OverlayArcMotion.appearCurve]: easeOutCubic (= WpMotion.spring).
  /// - [OverlayArcMotion.appearScale]: 0.88 — subtle spring-in, not dramatic.
  /// - [OverlayArcMotion.stateTransitionDuration]: 150 ms — calm crossfade.
  ///
  /// All durations are gated by `WpMotion.durationFor` in callers so that
  /// `MediaQuery.disableAnimations = true` collapses them to Duration.zero.
  static const OverlayArcMotion arc = OverlayArcMotion(
    appearDuration: Duration(milliseconds: 300),
    appearCurve: Curves.easeOutCubic, // WpMotion.spring — no overshoot
    appearScale: 0.88,
    stateTransitionDuration: Duration(milliseconds: 150),
    stateTransitionCurve: Curves.easeOut,
    releaseOutDuration: Duration(milliseconds: waveformReleaseOutMs),
  );

  // -- Vibrancy --------------------------------------------------------------

  /// Fill opacity used on platforms where no OS blur is available (flat
  /// fallback — Linux and any unsupported runtime). Higher than
  /// [fillOpacityFactor] because without a blur layer the capsule needs more
  /// opaque chrome to remain readable over any desktop background.
  static const double flatFallbackFillOpacity = 1.0;

  /// Platform-aware vibrancy material selection.
  ///
  /// macOS = `hudWindow` (Phase-0 GO, 1.0 ms avg, best optics confirmed).
  /// Windows = `acrylic` (pending Windows measurement).
  /// Linux = `flat` (no OS blur — tinted flat fill via [flatFallbackFillOpacity]).
  static const OverlayVibrancySpec vibrancy = OverlayVibrancySpec(
    macOS: OverlayVibrancyMaterial.hudWindow,
    windows: OverlayVibrancyMaterial.acrylic,
    linux: OverlayVibrancyMaterial.flat,
  );

  // -- Dynamic pill-width (issue 10) -----------------------------------------

  /// Width ratio for the pill at each design state, relative to
  /// [OverlaySizeSpec.width].
  ///
  /// | State        | Ratio  | Normal px (≈) |
  /// |---|---|---|
  /// | recording    | 1.000  | 330           |
  /// | transcribing | 1.000  | 330           |
  /// | done         | 0.606  | 200           |
  /// | error        | 0.758  | 250           |
  ///
  /// Transcribing keeps the recording stage (waveform+text pass, 2026-08-17):
  /// the label-in-the-stream composition needs the full waveform zone, and a
  /// widthless `recording → transcribing` hand-over lets the bars stay in
  /// place while the content crossfade re-colours them cyan → amber — the
  /// collapse morph is saved for the done/error end states.
  ///
  /// Both normal (330) and compact (220) sizes scale automatically because the
  /// ratio is applied against [OverlaySizeSpec.width], not a literal pixel value.
  static double pillWidthRatio(OverlayDesignState state) => switch (state) {
    OverlayDesignState.recording => 1.0,
    OverlayDesignState.transcribing => 1.0,
    OverlayDesignState.done => 0.606,
    OverlayDesignState.error => 0.758,
  };

  /// Width ratio for a [OverlaySizeSpec.minimalContent] pill (mini, nano).
  ///
  /// While the live waveform runs (recording) the pill keeps its full width.
  /// Transcribing keeps it too when the state paints a status label
  /// ([labelled], mini): the label floats inside the full-width amber
  /// processing stream (waveform+text pass, 2026-08-17 — the earlier fitted
  /// text-only pill read as "nur reiner Text"). A label-less transcribing
  /// (nano) has only the spinner, so it shrinks like the end states. For
  /// done/error the capsule shrinks around the single centred status icon
  /// (design pass) — a 150 px capsule holding one 14 px glyph read as an
  /// empty shell, and the width-morph spring is the overlay's most elegant
  /// motion; mini and nano share it there.
  static double minimalPillWidthRatio(
    OverlayDesignState state, {
    bool labelled = true,
  }) => switch (state) {
    OverlayDesignState.recording => 1.0,
    OverlayDesignState.transcribing => labelled ? 1.0 : 0.42,
    OverlayDesignState.done => 0.42,
    OverlayDesignState.error => 0.42,
  };

  /// Target pill width in logical pixels for [state] at the given [sizeSpec].
  ///
  /// Convenience wrapper: `sizeSpec.width × pillWidthRatio(state)` (minimal
  /// sizes: [minimalPillWidthRatio]). Callers pass this directly as
  /// `pillWidth` to [WpOverlayPainter].
  static double pillWidthFor(
    OverlayDesignState state,
    OverlaySizeSpec sizeSpec,
  ) => sizeSpec.minimalContent
      ? sizeSpec.width *
            minimalPillWidthRatio(state, labelled: sizeSpec.paintsStatusLabel)
      : sizeSpec.width * pillWidthRatio(state);

  /// [pillWidthFor], grown just enough to fit [text] without an ellipsis —
  /// e.g. a long done/error status message that does not fit the narrow
  /// `done`/`error`/`transcribing` ratio widths (issue: overlay text
  /// truncated even though the native window has room, both on Windows and
  /// macOS). Clamped to [sizeSpec.width] (the `recording`-state/full width,
  /// which is also what [windowSize] sizes the native host window to) so the
  /// pill never exceeds the space the native shell actually reserves —
  /// pathologically long text still falls back to [WpOverlayPainter]'s
  /// ellipsis at that point.
  static double pillWidthForText(
    OverlayDesignState state,
    OverlaySizeSpec sizeSpec,
    OverlayLayoutSpec layout,
    String text, {
    String secondaryText = '',
  }) {
    final baseWidth = pillWidthFor(state, sizeSpec);
    // Mini paints status text only while transcribing (state-distinction
    // pass); its other states stay glyph-only, and nano paints no text at
    // all — nothing to grow for.
    final paintsText =
        sizeSpec.paintsStatusLabel &&
        (!sizeSpec.minimalContent || state == OverlayDesignState.transcribing);
    if (!paintsText) return baseWidth;
    if (text.isEmpty && secondaryText.isEmpty) return baseWidth;
    // Mirrors WpOverlayPainter._drawContent's textLeft/maxTextWidth geometry.
    // Recording has no lead dot, so its timer starts after the close glyph;
    // the other states keep the status icon slot (dotInset). The text
    // starts at padH + that slot + timerGap from the pill's left edge,
    // and padH is reserved again on the right — solved for the pill width
    // that gives the measured text exactly enough room. A secondary line
    // (guided-sequence frames) shares the same left edge at its smaller
    // font; whichever line measures wider drives the pill.
    final measuredTextWidth = _measureTextWidth(text, layout.timerFontSize);
    final measuredSecondaryWidth =
        secondaryText.isEmpty || sizeSpec.minimalContent
        ? 0.0
        : _measureTextWidth(
            secondaryText,
            layout.timerFontSize * secondaryTextScale,
          );
    final widestLine = measuredTextWidth > measuredSecondaryWidth
        ? measuredTextWidth
        : measuredSecondaryWidth;
    final leadSlot = state == OverlayDesignState.recording
        ? layout.closeOffset + layout.closeArm
        : layout.dotInset;
    final requiredWidth =
        widestLine + 2 * layout.padH + leadSlot + layout.timerGap;
    return requiredWidth.clamp(baseWidth, sizeSpec.width);
  }

  /// Natural (untruncated) single-line width of [text] at [fontSize], using
  /// the same style [WpOverlayPainter._drawText] paints status/done/error text
  /// with (weight + tabular figures both affect layout width).
  static double _measureTextWidth(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: primaryFontWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  // -- Floating button -------------------------------------------------------

  /// V2 floating-button appearance.
  static const FloatingButtonSpec button = FloatingButtonSpec(
    discColor: Color(0xFFFFFFFF),
    discFillOpacity: 0.95,
    borderColor: Color(0x1A101828),
    borderWidth: 1.0,
    borderInset: 0.5,
    iconRatio: 24 / 56,
    mic: FloatingButtonMicSpec.spike,
    edgeColor: Color(0x00000000),
    shadowColor: WpOverlayTokens.overlayShadowLight,
  );

  /// Width of the recording ring (BTN-REC). The ring is painted outside the
  /// disc edge, so the disc keeps its diameter and the footprint does not move.
  static const double buttonRingWidth = 2.0;

  /// Side of the recording stop square as a share of the disc diameter (BTN-REC,
  /// replaces the mic while recording).
  static const double buttonStopSquareRatio = 0.36;

  /// Corner radius of the stop square as a share of its side.
  static const double buttonStopSquareCornerRatio = 0.2;

  /// The surface the button ring is checked against: the settings stage
  /// backdrop, the nearest fixed backdrop the ring sits on (WCAG 1.4.11).
  static const Color buttonRingBackdrop = WpColorsDark.background;

  /// Colour of the recording ring for [colors]. The ring must stand out from
  /// the disc it surrounds and, where possible, from [buttonRingBackdrop]
  /// (3:1 each). The wave colour comes first, then the ink. A light disc
  /// (amber, gletscher) has no colour that reaches 3:1 on both; there the ring
  /// takes the first colour that stands out from the disc, because half the
  /// stroke lies on the disc. It never takes the disc colour itself, which
  /// made the ring invisible on light backgrounds (#369).
  static Color _ringColorFor(OverlayThemeColors colors) {
    final disc = colors.capsuleFill;
    final candidates = [colors.accent, colors.ink];
    for (final c in candidates) {
      if (contrastRatio(c, disc) >= 3.0 &&
          contrastRatio(c, buttonRingBackdrop) >= 3.0) {
        return c;
      }
    }
    for (final c in candidates) {
      if (contrastRatio(c, disc) >= 3.0) return c;
    }
    return colors.ink;
  }

  /// The floating button's appearance for [colors] (ticket, ADR 0024): disc
  /// from the background, mic glyph in its ink, and while [ringed] (recording)
  /// a [buttonRingWidth] ring at the disc edge (see [_ringColorFor]).
  ///
  /// The ring uses a negative [FloatingButtonSpec.borderInset], which moves the
  /// stroke centre outwards: half the stroke lies beyond the disc radius, half
  /// on the disc.
  static FloatingButtonSpec buttonSpecFor(
    OverlayThemeColors colors, {
    bool ringed = false,
  }) => FloatingButtonSpec(
    discColor: colors.capsuleFill,
    discFillOpacity: button.discFillOpacity,
    borderColor: ringed
        ? _ringColorFor(colors)
        : colors.ink.withValues(alpha: 0.1),
    borderWidth: ringed ? buttonRingWidth : button.borderWidth,
    borderInset: ringed ? -buttonRingWidth / 2 : button.borderInset,
    iconRatio: button.iconRatio,
    mic: button.mic,
    edgeColor: colors.edge,
    shadowColor: colors.shadow,
  );

  /// Full native-window size for a button disc of [diameter] = disc +
  /// [shadowPadding] on every side, so the painted soft shadow is not clipped
  /// (mirrors [windowSize] for the overlay). The disc centre is painted at
  /// `Offset(shadowPadding + diameter / 2, shadowPadding + diameter / 2)`.
  /// Corner radius of the rounded-square button, as a share of its half
  /// diameter (0 = square, 1 = disc). ticket button shape.
  static const double buttonSquareCornerRatio = 0.45;

  static Size buttonWindowSize(double diameter) =>
      Size(diameter + 2 * shadowPadding, diameter + 2 * shadowPadding);
}
