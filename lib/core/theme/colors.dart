/// WhisPaste color palette — dark & light theme color definitions.
///
/// Quiet, chromatic material. **Two accents, two jobs**: `accent` and its
/// ladder mean "you can act on this", `recordingAccent` means "a recording or
/// its transcription is in flight" — nothing else is allowed a saturated voice.
/// The two are one cyan family separated by *weight*, not by hue; the older
/// "each job owns its own hue" clause is retracted (ADR 0013 — see *The Two
/// Accent, Two Jobs Rule* in `lib/DESIGN.md` for the retraction note).
///
/// **The ambient is not a third voice, it is the room** (ADR 0012,
/// 2026-08-11). Frame, content plane and the whole opaque surface stack live
/// in the brand's blue/navy family (~218–226°), the hue the app icon, the
/// websites and every pre-Ticket-04 build already carried. Ticket 04 had moved
/// the ambient onto a violet pole together with the accent; neither half of
/// that move survives (ADR 0012 returned the ground, ADR 0013 the accent).
/// Violet stays as the sparing "here and there", outside both accents: the
/// far, deepest end of both ambient arcs, where it is a flush rather than a
/// ground, and the lavender cast of the frost fills.
///
/// The blue is the *hue* of the pre-Ticket-04 palette but deliberately not its
/// *bytes*. Restoring those verbatim also restored the flat, pre-"coloured
/// glass" ground that Tickets 04–07 existed to leave behind, so every ambient
/// and surface value here is re-solved at raised chroma with its luminance held
/// constant: the numbers the gates measure are unchanged, the colour the eye
/// sees is roughly twice as saturated.
///
/// What keeps a blue ambient from reading as the cyan recording signal is
/// **weight, not hue distance**. The frame's first stop sits 28° from
/// `recordingAccent` — inside any hue radius one could name — and is in no
/// danger of being mistaken for it, because every ambient stop is ≥ 7:1 darker
/// than the signal and carries no edge, no motion and no shape. That is the
/// gate (`Ambient vs. the recording signal`, `wcag_contrast_test.dart`), and it
/// replaced *The Cool-Shadow Exception*, whose 45° clearance was retracted with
/// the violet ground it was invented to survive.
///
/// Depth is *precomposited frost*, not a compositor effect: tinted translucent
/// card fills (`cardFill`, `cardFillElevated`) painted over one chromatic
/// ambient gradient (`warmSurfaceGradient`), plus a static 1px top-edge
/// highlight. Every fill carries its hue in the token — a neutral white/black
/// alpha over a chromatic ground desaturates it, which is exactly how the
/// earlier painted-glass attempt read grey. There is no `BackdropFilter` in
/// the app outside the modal dialog-barrier family (`dialog.dart`,
/// `export_format_picker.dart`, `hotkey_recorder.dart` — three call sites of
/// the same transient full-screen effect, which already has a Windows
/// fallback).
///
/// Depth comes from **one source**: the brightness delta between fills. No
/// card shadow token exists here at all. A colored shadow at offset 0
/// is not a depth source and stays out (UIA-VIS-12).
///
/// > **Retracted 2026-08-11 (dark-only build): the per-theme half of the depth
/// > rule, and *Theme asymmetry, sanctioned here* entirely.** Depth used to be
/// > "one source per *theme*" — the brightness delta on dark, a single soft,
/// > wide, violet-tinted shadow (`cardShadowLight`) on light. And the light
/// > stack's chroma was capped well below the dark stack's, because rotating a
/// > pearl toward violet drains the green channel that carries 71.5 % of
/// > relative luminance, so `textMuted` ran out of AA headroom before the dark
/// > side noticed anything. That was the *Increment–Decrement Rule*'s closing
/// > clause — "a new theme asymmetry is allowed, but it argues for itself at
/// > the token" — and the argument sat at `WpColorsLight.background`. With one
/// > stack left there is no asymmetry to sanction and no second depth source
/// > to choose between. Recorded rather than deleted: both clauses were
/// > argued-for positions, not defaults, and a rule that quietly disappears
/// > cannot be audited.
///
/// The two-accent and one-depth-source splits are stated in this file and
/// mirrored in `lib/DESIGN.md` (synced to this state 2026-08-16, Ticket 17).
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'colors_dark.dart';
import 'theme_colors.dart';

export 'colors_dark.dart';
export 'theme_colors.dart';

/// The palette the app paints from: the active [WpThemeColors] set.
///
/// Static getters so existing call sites stay as they are; they are not
/// `const` any more, because the set changes at runtime (AR-21). After
/// [activate] the caller rebuilds the widget tree.
abstract final class WpColors {
  static WpThemeColors _active = wpDarkColors;

  static WpThemeColors get current => _active;

  /// Frame colours (title bar, sidebar) of the active set.
  static WpThemeColors get frame => _active.frame;

  static void activate(WpThemeColors colors) => _active = colors;

  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get surfaceElevated => _active.surfaceElevated;
  static Color get surfaceVariant => _active.surfaceVariant;
  static Color get hover => _active.hover;
  static Color get hoverTransparent => _active.hoverTransparent;
  static Color get active => _active.active;
  static Color get borderSubtle => _active.borderSubtle;
  static Color get borderDefault => _active.borderDefault;

  /// Border of an unselected colour swatch: a solid 3:1 boundary in both themes.
  static Color get selectionBorder => _active.selectionBorder;
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textMuted => _active.textMuted;
  static Color get accent => _active.accent;
  static Color get action => _active.action;
  static Color get onAction => _active.onAction;
  static Color get accentSubtle => _active.accentSubtle;
  static Color get accentChipFill => _active.accentChipFill;
  static Color get accentChipFillHover => _active.accentChipFillHover;
  static Color get accentMiniTagFill => _active.accentMiniTagFill;
  static Color get accentBorder30 => _active.accentBorder30;
  static Color get accentButtonFill => _active.accentButtonFill;
  static Color get accentActiveFill => _active.accentActiveFill;
  static Color get accentBadgeFill => _active.accentBadgeFill;
  static Color get accentBorder20 => _active.accentBorder20;
  static Color get accentRowHover => _active.accentRowHover;
  static Color get surfaceChipFill => _active.surfaceChipFill;
  static Color get surfaceMutedFill => _active.surfaceMutedFill;
  static Color get highlight => _active.highlight;
  static Color get highlightSoft => _active.highlightSoft;
  static Color get highlightText => _active.highlightText;
  static Color get primaryRecordFill => _active.primaryRecordFill;
  static Color get primaryRecordHover => _active.primaryRecordHover;
  static Color get onPrimaryRecord => _active.onPrimaryRecord;
  static Color get ctaFill => _active.ctaFill;
  static Color get ctaHover => _active.ctaHover;
  static Color get ctaPressed => _active.ctaPressed;
  static Color get onCta => _active.onCta;
  static Color get controlEdge => _active.controlEdge;
  static Color get cardFill => _active.cardFill;
  static Color get cardFillElevated => _active.cardFillElevated;
  static Color get cardEdgeHighlight => _active.cardEdgeHighlight;
  static Color get floatingSurface => _active.floatingSurface;
  static Color get decorativeGlyphWash => _active.decorativeGlyphWash;
  static Color get accentLocatorRing => _active.accentLocatorRing;
  static Color get success => _active.success;
  static Color get warning => _active.warning;
  static Color get error => _active.error;
  static Color get onError => _active.onError;
  static Color get errorRowHover => _active.errorRowHover;
  static Color get errorButtonFill => _active.errorButtonFill;
  static Color get errorActiveFill => _active.errorActiveFill;
  static Color get errorBorder20 => _active.errorBorder20;
  static Color get errorBorder30 => _active.errorBorder30;
  static Color get mutedRowHover => _active.mutedRowHover;
  static Color get mutedActiveFill => _active.mutedActiveFill;
  static Color get warningActiveFill => _active.warningActiveFill;
  static Color get recordingAccent => _active.recordingAccent;
  static Color get errorRed => _active.errorRed;
  static LinearGradient get surfaceGradient => _active.surfaceGradient;
  static LinearGradient get warmSurfaceGradient => _active.warmSurfaceGradient;
}

// ---------------------------------------------------------------------------
// Reusable glass decoration builder
// ---------------------------------------------------------------------------

/// Theme-independent accents used identically in light and dark — a sanctioned
/// exception to the per-theme token split above, for colors chosen for
/// user-facing variety/recognition rather than surface hierarchy.
abstract final class WpSharedColors {
  /// Pinned/favorited-item accent (star icon, toggle). Amber reads as
  /// "favorite" cross-platform regardless of theme, like a star rating.
  static const Color pinnedAccent = Color(0xFFFFB300); // Colors.amber.shade600

  /// Sponsor heart glyph (`Icons.favorite_rounded`, website Tailwind
  /// `pink-400`). Sanctioned exception for the support chip only: the heart
  /// glyph, never text, a background or a button (decision 4, 2026-10-07).
  static const Color supportHeart = Color(0xFFF472B6);
}

// ---------------------------------------------------------------------------
// Category slots — the nominal color layer
// ---------------------------------------------------------------------------

/// The nine category slots, in palette order — eight interchangeable *category*
/// hues plus one dedicated [neutral] fallback.
///
/// **The contract.** A category color is never picked at a call site. A widget
/// asks [categorySlotForModel] or [categorySlotForTag] for a slot, or reaches
/// for [neutral] when the thing it paints has no category at all — and only
/// then resolves the slot to a [Color] through [color]. The indirection *is*
/// the feature: it makes a hue a statement about the data rather than
/// decoration, and it is the thing a later reader can grep to find out what a
/// color means. Painting one of the constants below directly is the same defect
/// as hand-rolling an alpha.
///
/// **The one sanctioned decorative user** is the history-entry avatar, which
/// indexes [categories] with the slot persisted on the entry. It is bounded the
/// same way: no call site picks the hue there either, and the hue claims no
/// meaning at all — see `historyAvatarSlot` and *The Categorical vs. Sequential
/// Rule* in `lib/DESIGN.md`.
///
/// **Why a slot and not a [Color].** The slot is theme-independent, the color
/// is not. Anything that caches an identity's color must cache the *slot* and
/// resolve it inside `build()`; caching the resolved color leaves the old
/// theme's hue on screen after a runtime theme switch.
///
/// **[neutral] is not a ninth category.** Untitled/uncategorised is the *normal*
/// case in a dictation app, not an edge case, and it must not disguise itself
/// as a category — so it gets its own near-achromatic slot and is deliberately
/// excluded from [categories], i.e. from every hash. Nothing ever lands on
/// neutral by accident; a call site asks for it explicitly.
enum WpCategorySlot {
  iris,
  ember,
  fern,
  orchid,
  brass,
  azure,
  plum,
  moss,
  neutral;

  /// The eight hashable category slots — [neutral] excluded on purpose.
  static const List<WpCategorySlot> categories = [
    iris,
    ember,
    fern,
    orchid,
    brass,
    azure,
    plum,
    moss,
  ];

  /// Resolves this slot to a paintable color — the only sanctioned way from a
  /// slot to one.
  ///
  /// Took an `isDark` flag while the slots were a theme pair. It resolves
  /// against the one palette now, so the flag is gone rather than ignored: a
  /// parameter a caller can still pass but that cannot change the answer is a
  /// standing invitation to thread state that does not exist.
  ///
  /// Resolves against the active appearance (ADR 0023): the dark slots on a
  /// dark set, their light twins on every light-content set.
  Color color() => (_isDarkSet
      ? WpCategoryColorsDark.slots
      : WpCategoryColorsLight.slots)[index];

  /// *The Tint Ladder Rule*'s 12 % fill rung, in this slot's hue.
  ///
  /// A rung rather than a call-site alpha, but computed rather than declared:
  /// the ladder's other hues are one token family each because they are one
  /// hue each — nine slots × two rungs × two themes would be 36 constants
  /// restating one number. The ladder's guarantee is that the *weight* is
  /// shared across hues, and that is exactly what these two methods carry.
  Color chipFill() => color().withValues(alpha: 0.12);

  /// *The Tint Ladder Rule*'s 30 % outline rung, in this slot's hue. See
  /// [chipFill].
  Color chipBorder() => color().withValues(alpha: 0.30);

  /// A [steps]-step **sequential** ramp in this slot's hue — the ordinal half
  /// of *The Categorical vs. Sequential Rule*.
  ///
  /// Ordered data (a duration distribution, a ranked tier) gets one hue at
  /// several weights, never several hues: a reader who sees eight hues on a
  /// ranked axis has to learn an arbitrary order, where one hue at rising
  /// weight already carries it. `steps` is capped at the rule's own 3–5 so the
  /// cap is executable rather than advisory.
  ///
  /// **Step 0 is the slot itself, and the ramp climbs *away* from the ground.**
  /// It lightens, blending toward white — which means every rung clears the
  /// surfaces by at least as much as the base slot does, and the 3:1 floor for
  /// a graphical object is inherited rather than re-argued per rung. A ramp
  /// laid symmetrically around the slot would sink its low end under that
  /// floor.
  ///
  /// **The axis is luminance, not HSL lightness**, because the palette itself is
  /// built on equal relative luminance (see [WpCategoryColorsDark]). Each rung
  /// sits a fixed [_rampStepContrast] contrast ratio from the one before it, so
  /// the rungs are exactly as separable in `moss` as in `plum` — equal steps of
  /// HSL lightness are not, and collapse into each other on the slots that
  /// already sit low. Solving in linear light also makes the step a closed form
  /// instead of a search.
  ///
  /// > **Retracted 2026-08-11 (dark-only build): the mirrored light branch.**
  /// > This ramp used to derive two ways — lightening on dark by blending
  /// > toward white, darkening on light by a pure luminance scale that left
  /// > the chromaticity untouched. Only the blend survives. The light branch
  /// > was not merely unreachable once [color] stopped answering per theme: it
  /// > was actively *wrong*, because it would have scaled an already-dark base
  /// > further down instead of climbing away from the ground the ramp is
  /// > solved against.
  ///
  /// Verified per slot and per step count in
  /// `test/core/theme/wcag_contrast_test.dart`: neighbouring rungs stay ≥ 1.2:1
  /// apart and every rung clears every surface by ≥ 3:1.
  List<Color> ramp(int steps) {
    assert(
      steps >= 3 && steps <= 5,
      'a sequential ramp carries 3–5 steps (The Categorical vs. Sequential '
      'Rule); $steps rungs is a scale the eye can no longer order',
    );
    final base = color();
    final baseLuminance = base.computeLuminance();
    final r = _srgbToLinear(base.r);
    final g = _srgbToLinear(base.g);
    final b = _srgbToLinear(base.b);

    final isDark = _isDarkSet;
    final rungs = <Color>[base];
    var offsetLuminance = baseLuminance + 0.05;
    for (var i = 1; i < steps; i++) {
      offsetLuminance = isDark
          ? offsetLuminance * _rampStepContrast
          : offsetLuminance / _rampStepContrast;
      final target = offsetLuminance - 0.05;
      if (isDark) {
        // Blend toward white in linear light: Y rises linearly with the blend
        // factor, so the factor that hits `target` is a division, not a search.
        final t = ((target - baseLuminance) / (1 - baseLuminance)).clamp(
          0.0,
          1.0,
        );
        rungs.add(
          Color.from(
            alpha: 1,
            red: _linearToSrgb(r + t * (1 - r)),
            green: _linearToSrgb(g + t * (1 - g)),
            blue: _linearToSrgb(b + t * (1 - b)),
          ),
        );
      } else {
        // On a light ground the ramp climbs away by darkening: scaling every
        // linear channel by one factor scales Y by it and keeps the hue.
        final k = (target / baseLuminance).clamp(0.0, 1.0);
        rungs.add(
          Color.from(
            alpha: 1,
            red: _linearToSrgb(r * k),
            green: _linearToSrgb(g * k),
            blue: _linearToSrgb(b * k),
          ),
        );
      }
    }
    return rungs;
  }
}

/// Contrast ratio between two neighbouring rungs of [WpCategorySlot.ramp].
///
/// Chosen as the largest step a five-rung ramp can afford without its far end
/// running out of room: from the palette's Y ≈ 0.30 base, four steps of 1.22
/// land at Y ≈ 0.72 — pale, but still hue-bearing rather than white. (The
/// second figure this note used to carry, Y ≈ 0.05 from the light base, went
/// with the light stack on 2026-08-11.)
const double _rampStepContrast = 1.22;

/// The sRGB transfer function and its inverse — the same one
/// [Color.computeLuminance] applies, restated here because [WpCategorySlot.ramp]
/// has to leave linear light again after doing its arithmetic there.
double _srgbToLinear(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) =>
    c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

/// Dark-theme category slots — one recipe, nine outcomes.
///
/// Every slot is a **solid tone**, not a translucent fill: hue spaced around
/// the wheel, HSL saturation held at ≈52 %, and lightness solved *per hue* so
/// all nine land on the same relative luminance (Y ≈ 0.30). Equal luminance is
/// what makes the set read as one categorical scale — no slot volunteers
/// itself as "the important one", which is exactly what a nominal scale must
/// not do. It also puts every slot at ≈5.8:1 against `surface`, comfortably
/// over the 3:1 floor for a graphical object and comfortably *under* the
/// accent's 9.0:1 — the palette is quieter than the brand voice by
/// construction, not by luck. Gated in `test/core/theme/wcag_contrast_test.dart`.
///
/// Because these are opaque tones, *The Increment–Decrement Rule* does not
/// apply — there is no alpha to tune down. The theme pair still mirrors its
/// direction for the same optical reason: on navy a slot resolves *lighter*
/// than its ground, on pearl its light twin resolves *toward ink*, same hue,
/// same saturation, luminance re-solved against the other ground.
///
/// **Excluded hue bands, on purpose.** Cyan/teal 165–215° belongs to the
/// recording family alone; ~30–55° is Pin Amber and
/// `warning`; ~350–15° is `error`; ~145–165° is `success`. A category may not
/// borrow a hue that already means something else in this app.
abstract final class WpCategoryColorsDark {
  static const Color iris = Color(0xFFA486D9); // 262° violet
  static const Color ember = Color(0xFFCB855B); // 22° terracotta
  static const Color fern = Color(0xFF36AA53); // 135° leaf green
  static const Color orchid = Color(0xFFCD74D3); // 296° purple-magenta
  static const Color brass = Color(0xFF979B31); // 62° olive-gold
  static const Color azure = Color(0xFF8092D7); // 228° blue
  static const Color plum = Color(0xFFD477A3); // 332° rose-plum
  static const Color moss = Color(0xFF5EA735); // 98° yellow-green

  /// The dedicated fallback for "no category" — same luminance as the eight,
  /// chroma dropped to ≈20 % so it reads as *absence of a category* rather than
  /// as a ninth one. Never returned by a hash.
  static const Color neutral = Color(0xFF8A95B1);

  /// Indexed by [WpCategorySlot.index] — same order as the enum, neutral last.
  static const List<Color> slots = [
    iris,
    ember,
    fern,
    orchid,
    brass,
    azure,
    plum,
    moss,
    neutral,
  ];
}

/// Light-ground category slots (ADR 0023) — the twins of
/// [WpCategoryColorsDark], same hues, lightness re-solved so all nine sit at
/// Y ≈ 0.19 and clear the glacier surfaces by more than 3:1.
abstract final class WpCategoryColorsLight {
  static const Color iris = Color(0xFF8C62D5); // 262° violet
  static const Color ember = Color(0xFFB76231); // 22° terracotta
  static const Color fern = Color(0xFF258A3E); // 135° leaf green
  static const Color orchid = Color(0xFFC23CCB); // 296° purple-magenta
  static const Color brass = Color(0xFF7A7D21); // 62° olive-gold
  static const Color azure = Color(0xFF5A72D3); // 228° blue
  static const Color plum = Color(0xFFCE4585); // 332° rose-plum
  static const Color moss = Color(0xFF488824); // 98° yellow-green

  /// See [WpCategoryColorsDark.neutral].
  static const Color neutral = Color(0xFF68789F);

  /// Indexed by [WpCategorySlot.index] — same order as the enum, neutral last.
  static const List<Color> slots = [
    iris,
    ember,
    fern,
    orchid,
    brass,
    azure,
    plum,
    moss,
    neutral,
  ];
}

/// Whether the active appearance paints on a dark ground.
bool get _isDarkSet => WpColors.current.brightness == Brightness.dark;

/// Deterministic slot for an STT model, keyed by its `SttModelInfo.id`.
///
/// Stable across restarts and across model-list edits: the identity is the id,
/// never the list position, so adding a model never re-colors the others.
///
/// **A table, not a hash**, because the domain is closed and small enough that a
/// bijection is both possible and owed:
/// the shipped ids are a small closed set, and the sum-of-code-units hash is not
/// injective over it — `whisper-small` and `whisper-medium` both sum onto slot 0
/// and would paint the two most-used models the same hue. An id the table does
/// not know still hashes, so an unreleased model keeps working; a test pins that
/// every id the app actually ships is tabled.
WpCategorySlot categorySlotForModel(String modelId) =>
    _modelSlots[modelId] ?? _categorySlotForIdentity(modelId);

/// The STT model ids the app can show, one slot each.
///
/// The four selectable models take the four most widely separated hues on the
/// wheel; the three legacy ids — `_migrateModelId` rewrites the *setting*, so
/// history rows written before it still carry them — take what remains. Which
/// key gets which hue means nothing, the scale is nominal.
///
/// [WpCategorySlot.iris] is deliberately absent: it is the source of the
/// analytics duration ramp (see [WpCategorySlot.ramp]), which sits one panel
/// away from the model bars, and one hue should not mean two things on a screen.
const Map<String, WpCategorySlot> _modelSlots = {
  'whisper-small': WpCategorySlot.fern,
  'whisper-medium': WpCategorySlot.azure,
  'whisper-large-v3-turbo': WpCategorySlot.orchid,
  'parakeet-tdt-0.6b-v3': WpCategorySlot.ember,
  'whisper-tiny': WpCategorySlot.moss,
  'whisper-base': WpCategorySlot.brass,
  'whisper-large-v3': WpCategorySlot.plum,
};

/// Deterministic slot for a tag, keyed by its name.
///
/// The name is case- and whitespace-normalised first — tags are user-typed, and
/// "Meeting" and "meeting " must not land on two different hues.
WpCategorySlot categorySlotForTag(String tagName) =>
    _categorySlotForIdentity(tagName.trim().toLowerCase());

/// The one hash behind the mappers — sum of code units, modulo the slot count —
/// so the repo keeps a single, recognisable "identity → slot" idiom. Sound for
/// user-typed tags, whose domain is genuinely open; the closed set of shipped
/// model ids is tabled instead, because over a small domain the hash collides
/// and a bijection is both possible and owed. See [categorySlotForModel] —
/// there the hash is only the fallback for an id the table has not met.
///
/// Distributes over [WpCategorySlot.categories] only; [WpCategorySlot.neutral]
/// is unreachable from here by design. An empty identity is a caller bug, not a
/// fallback: it hashes to 0 like any other string. Callers that mean "no
/// category" say so with [WpCategorySlot.neutral].
WpCategorySlot _categorySlotForIdentity(String identity) {
  final hash = identity.codeUnits.fold<int>(0, (a, b) => a + b);
  return WpCategorySlot.categories[hash % WpCategorySlot.categories.length];
}

/// Rendering recipe for the history-entry avatar disc.
///
/// The base is a [WpCategorySlot] color, so it already darkens per theme — but
/// the disc is a *translucent* tint over its ground, and a pair solved for equal
/// luminance is not the same thing as a pair solved for equal presence through
/// alpha. The theme pair is gone (see the retraction below); what outlived it is
/// the reason these values were never a scale of one another — presence has to
/// be solved against the ground the tint actually stands on, and the answer for
/// navy is a *dense* fill whose hue runs **toward ink**, not the thin one pushed
/// toward light this recipe shipped with. Ticket 32/B2 turned it; the paragraph
/// on [dark] carries the measurement.
///
/// The lightness shifts are clamped into a legibility band. The band is what
/// keeps the recipe hue-agnostic: a pure shift drives already-dark hues to
/// near-black and washes pale ones out, so the band caps both ends without
/// flattening the hues that sit in between. On today's slots [fillLightnessMin]
/// holds `fern`, `brass` and `moss` — the three that already sit lowest — and
/// the glyph band binds at both ends (`brass` at the floor, `iris`, `azure`,
/// `plum` and `orchid` at the ceiling). [fillLightnessMax] binds on nothing:
/// with the shift running toward ink the fill cannot reach it, and it is kept
/// as the guard against a future edit turning the shift back around.
///
/// Calibrated against two contrast targets, verified per slot and per ground in
/// `test/core/theme/wcag_contrast_test.dart`:
/// * disc vs. `surface`/`surfaceElevated` ≥ 1.5:1 (WCAG 1.4.11, graphical
///   object) — the disc has to be *seen*;
/// * glyph vs. disc ≥ 3:1 — the icon has to be *read*.
///
/// The two pull against each other — every step that makes the disc denser
/// moves the floor the glyph has to clear — which is why they are calibrated
/// together rather than one after the other.
///
/// **The disc is a tonal circle on the content plane.** It carries no light
/// source of its own (UIA-VIS-12). The ground is the content plane
/// ([WpColorsDark.warmSurfaceGradient]), the brighter and therefore tighter
/// ground, and the disc clears it with margin.
final class WpAvatarTint {
  const WpAvatarTint._({
    required this.fillTopAlpha,
    required this.fillBottomAlpha,
    required this.edgeAlpha,
    required this.glyphAlpha,
    required this.fillLightnessShift,
    required this.fillLightnessMin,
    required this.fillLightnessMax,
    required this.topStopLightnessDelta,
    required this.glyphLightnessShift,
    required this.glyphLightnessMin,
    required this.glyphLightnessMax,
  });

  /// Alpha of the lit (top-left) gradient stop.
  final double fillTopAlpha;

  /// Alpha of the shaded (bottom-right) gradient stop.
  final double fillBottomAlpha;

  /// Alpha of the 1px hue-tinted rim.
  final double edgeAlpha;

  /// Alpha of the icon glyph.
  final double glyphAlpha;

  /// Lightness shift applied to the palette hue before it fills the disc.
  ///
  /// **Negative** — the fill runs toward ink. It read "positive on dark,
  /// negative on light" while the disc was a veil and the ground did most of
  /// the work; Ticket 32/B2 inverted it, because a dense fill pushed toward
  /// white leaves the glyph, which owes it 3:1, nowhere left to go. Separation
  /// from the ground is not this dial's job any more — the composite still
  /// lands lighter than the plane by construction, and the density does the
  /// rest.
  final double fillLightnessShift;

  /// Legibility band for the shifted fill lightness.
  final double fillLightnessMin;
  final double fillLightnessMax;

  /// Extra lightness delta of the lit stop over the shaded one. Always
  /// **positive**, whatever [fillLightnessShift] does: "lit" means lit, and the
  /// lit stop has to come out brighter than the shaded one. It used to be stated as "carries the same sign as
  /// [fillLightnessShift]", which said the same thing only for as long as that
  /// shift was positive and became wrong the moment Ticket 32/B2 turned it.
  final double topStopLightnessDelta;

  /// Lightness shift applied to the palette hue for the glyph. Runs *against*
  /// [fillLightnessShift] and far enough past it that the icon clears the disc
  /// it sits on by 3:1 — the fill is pushed toward ink precisely so the glyph
  /// has somewhere to go. Keep it clear of
  /// `fillLightnessShift + topStopLightnessDelta` —
  /// at equality the glyph and the lit stop collapse onto the same color and
  /// only their alphas still tell them apart.
  final double glyphLightnessShift;

  /// Legibility band for the shifted glyph lightness.
  final double glyphLightnessMin;
  final double glyphLightnessMax;

  /// Dense fill, hue pushed toward ink, glyph lifted clear of it.
  ///
  /// **Recalibrated 2026-08-16 — Ticket 32/B2, "the eight hues collapse into
  /// one".** The disc was a 0.28/0.20 veil, and at that alpha the navy plane
  /// under it, not the slot, decided what the eye got. Composited on the
  /// content plane the eight slots came out **0.4° apart at the worst pair**
  /// (`ember`/`plum`, 247.9° and 247.5° — a terracotta and a pink, both
  /// rendering as the plane's own violet), `moss` **0.7° from
  /// [WpColorsDark.recordingAccent]** —
  /// the cyan *Two Accents, Two Jobs* reserves for "recording" — and as low as
  /// **7.4 % saturation** (`brass`). The worst slot landed **161° from its own
  /// palette hue**: `brass`, a gold, was painting a blue-grey. A rotation whose
  /// only job is to keep a long list scannable was rendering as one hue with a
  /// wobble.
  ///
  /// Density is the fix. Composite hue follows the chroma vectors, roughly
  /// `w_f·C_f / (w_f·C_f + w_g·C_g)`, so the dial that moves all three numbers
  /// the same way is the fill's share of the sum: 0.70/0.62 puts the slot in
  /// the majority instead of the fifth it held. The same three measurements
  /// become **27.2°** (`iris`/`azure`), **35.1°** (`fern` against the accent)
  /// and **26.8 %** (`brass`), while drift falls to 20.4° — and the tightest of
  /// the two older floors is the glyph at 3.45:1 against its 3:1. Every one of
  /// those is read off a `reason:` string, gated per slot and per plane stop in
  /// `test/core/theme/wcag_contrast_test.dart`; only the drift figure is a
  /// diagnostic rather than a gate.
  ///
  /// *Why not lay the tint on an opaque neutral bed first* — the other
  /// direction the ticket offered: measured, it loses on the very check it was
  /// meant to win. The plane is chromatic, and a thin tint over it *borrows*
  /// that chroma; a grey bed takes the loan away before the tint is laid on. A
  /// full sweep (bed alpha 0.55–0.88 × bed lightness 0.10–0.22 × tint alpha
  /// 0.28–0.46) returned **no** feasible combination — composited saturation
  /// came out at 3–8 %, at or below the 7.4 % this ticket exists to fix, even
  /// where the hue gap passed.
  ///
  /// What density costs, and what pays for it:
  /// * [fillLightnessShift] turns negative and the glyph band climbs to
  ///   0.74–0.95. At a veil's alpha the disc's own lightness barely reached the
  ///   surface, so pushing the hue up was free; at 0.70 the disc *is* the
  ///   surface, and a hue pushed toward white leaves nothing above it for the
  ///   icon. The composite still sits lighter than the plane (L ≈ 26–45 % over
  ///   its 19 %) — the disc separates by density and chroma now, not by being
  ///   the palest thing in the row.
  /// * [edgeAlpha] follows the shaded stop up by the same +0.10 it always
  ///   carried over it (0.20/0.30 became 0.62/0.72). Left at 0.30 the rim would
  ///   have been the thinnest paint on a dense disc — a groove cut toward the
  ///   ground rather than the hue-tinted edge it is meant to be.
  /// * The plane still shows through, 30 % of it, so the disc keeps reading
  ///   against the ambient instead of punching a sticker into it. That is why
  ///   this stops at 0.70 and not at the 0.80 the sweep also cleared.
  ///
  /// Left standing, and outside this ticket: composited `ember` (≈11.5°) and
  /// `fern` (≈150–155°) still fall inside hue bands this file reserves for
  /// error and success. Nothing gates that — the reserved band the tests do
  /// gate is `recordingAccent`'s, and the disc clears it by 35° — but the drift
  /// is real, it shrinks as density rises, and closing it the rest of the way
  /// would mean moving base hexes that Ticket 32 freezes.
  ///
  /// Superseded: the predecessor ticket's figures for this defect (261.7°,
  /// 254.0°, an occupied band of 244–285°) were taken against the violet
  /// ambient. Ticket 33 put ambient and accent back on navy/cyan, so every
  /// number above is re-measured against the plane that actually ships.
  static const WpAvatarTint dark = WpAvatarTint._(
    fillTopAlpha: 0.70,
    fillBottomAlpha: 0.62,
    edgeAlpha: 0.72,
    glyphAlpha: 0.95,
    fillLightnessShift: -0.16,
    fillLightnessMin: 0.30,
    fillLightnessMax: 0.62,
    topStopLightnessDelta: 0.08,
    glyphLightnessShift: 0.32,
    glyphLightnessMin: 0.74,
    glyphLightnessMax: 0.95,
  );

  /// Light ground (ADR 0023): [dark] with every sign mirrored — denser fill,
  /// hue pushed toward ink, glyph darker still. The lit top stop is deliberately not
  /// mirrored: "lit" means lit from above on every ground, so light pays with
  /// a paler source and slightly more of it instead.
  static const WpAvatarTint light = WpAvatarTint._(
    fillTopAlpha: 0.36,
    fillBottomAlpha: 0.26,
    edgeAlpha: 0.44,
    glyphAlpha: 0.95,
    fillLightnessShift: -0.20,
    fillLightnessMin: 0.22,
    fillLightnessMax: 0.56,
    topStopLightnessDelta: -0.12,
    glyphLightnessShift: -0.36,
    glyphLightnessMin: 0.14,
    glyphLightnessMax: 0.34,
  );

  /// The tint for the active appearance.
  static WpAvatarTint get current => _isDarkSet ? dark : light;

  /// Lit (top-left) gradient stop for [base], alpha included.
  Color fillTop(Color base) => _shift(
    base,
    fillLightnessShift + topStopLightnessDelta,
    fillLightnessMin + topStopLightnessDelta,
    fillLightnessMax + topStopLightnessDelta,
  ).withValues(alpha: fillTopAlpha);

  /// Shaded (bottom-right) gradient stop for [base], alpha included.
  Color fillBottom(Color base) =>
      _fillBase(base).withValues(alpha: fillBottomAlpha);

  /// Hue-tinted rim for [base], alpha included.
  Color edge(Color base) => _fillBase(base).withValues(alpha: edgeAlpha);

  /// Icon color for [base], alpha included.
  Color glyph(Color base) => _shift(
    base,
    glyphLightnessShift,
    glyphLightnessMin,
    glyphLightnessMax,
  ).withValues(alpha: glyphAlpha);

  /// The whole disc as one gradient — lit top stop, shaded bottom stop.
  ///
  /// Vertical, so the lit top stop sits on the axis the disc is lit from.
  LinearGradient discGradient(Color base) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [fillTop(base), fillBottom(base)],
    stops: const [0.0, 1.0],
  );

  Color _fillBase(Color base) =>
      _shift(base, fillLightnessShift, fillLightnessMin, fillLightnessMax);

  static Color _shift(Color base, double delta, double min, double max) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(min, max).clamp(0.0, 1.0))
        .toColor();
  }
}

// ---------------------------------------------------------------------------
// Decorative layer — retracted 2026-08-11
//
// `WpDecorativeColorsDark` (*Quartz*, a 314° mauve) and its resolver
// `wpDecorativeChromeWash()` lived here. The layer's whole job was to make the
// settings page read as its own plate, and it was already down to that one
// call site after Ticket 06 took it off the nav rail. The maintainer reported
// that the plate is exactly the defect: Settings looked unlike every other
// page, most visibly in the band under the page header. With the wash gone the
// layer has no surface left, so the tokens are removed rather than kept as an
// unused hue family a future call site could rediscover.
//
// Recorded rather than deleted, per this file's audit convention — the
// reasoning is written up under *The Decorative Color Rule* in `lib/DESIGN.md`,
// which keeps the retracted rule with its retraction note. Not to be confused
// with `decorativeGlyphWash` (accent-tinted, on a single card), which is a
// different token under a different rule and stays.
// ---------------------------------------------------------------------------

/// The flat scrim behind every dialog barrier (no blur, no glass).
///
/// Needs true black/white rather than a themed surface token: it only has to
/// darken/lighten what shows behind the dialog. Was duplicated verbatim across
/// five dialog widgets.
Color wpDialogBarrierColor() {
  // Light grounds dim toward the navy ink rather than toward black, so the
  // scrim stays in the journal's colour family (ADR 0023).
  return _isDarkSet
      ? const Color(0xFF000000).withValues(alpha: 0.45)
      : const Color(0xFF0B122A).withValues(alpha: 0.32);
}
