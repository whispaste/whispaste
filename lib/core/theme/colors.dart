/// WhisPaste color palette — dark & light theme color definitions.
///
/// Calm, quiet palette with warm materiality: deep rich surfaces with a
/// single cyan accent, opaque dual-tone gradients for chromatic depth (see
/// `warmSurfaceGradient`), soft glass hints and crisp borders. No harsh
/// glow anywhere — depth comes from layered surfaces, tonal temperature
/// shifts, and soft shadows, never from alpha-blended light.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'tokens.dart';

// ---------------------------------------------------------------------------
// Dark Theme Colors (Primary) — rich saturated navy tones, warm & unified
// ---------------------------------------------------------------------------
abstract final class WpColorsDark {
  /// Window frame — close to surface for unified monochrome feel
  static const Color background = Color(0xFF0F1320);

  /// Content surfaces — minimal step up from frame (≈ 2% lightness delta)
  static const Color surface = Color(0xFF141A29);

  /// Elevated panels, cards — richer blue tint
  static const Color surfaceElevated = Color(0xFF1B2336);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFF232C40);
  static const Color hover = Color(0xFF212A40);

  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents dark flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00212A40);
  static const Color active = Color(0xFF293352);

  /// Hairline borders — white at 11.8 % / 18.8 %, both a step *above* their
  /// light twins (7.8 % / 14.1 %). Not an oversight: see
  /// [WpColorsLight.borderSubtle] for the increment/decrement reasoning.
  static const Color borderSubtle = Color(0x1EFFFFFF);
  static const Color borderDefault = Color(0x30FFFFFF);

  /// Text — readable, not overly bright to avoid harshness
  static const Color textPrimary = Color(0xFFF0F4FA);
  static const Color textSecondary = Color(0xFFABB8CC);
  static const Color textMuted = Color(0xFF8A99B2);

  /// Vibrant cyan accent — highly saturated
  static const Color accent = Color(0xFF3CCBE6);
  static const Color accentHover = Color(0xFF66DBEE);

  /// Flat accent surface tint, 16.5 % — deliberately *above* its light twin
  /// (11 %). See [WpColorsLight.accentSubtle] for the increment/decrement
  /// reasoning shared by every structural translucent in this file.
  static const Color accentSubtle = Color(0x2A3CCBE6);

  /// Instance-safe tint tokens: translucent fills/borders whose alpha lives in
  /// the *value*, used inside components that get reused as nested instances.
  /// Prefer them over inline `colour.withValues(...)` for component
  /// fills/borders.
  static const Color accentChipFill = Color(0x1A3CCBE6); // accent @ 10%
  static const Color accentChipFillHover = Color(0x2E3CCBE6); // accent @ 18%
  static const Color accentMiniTagFill = Color(0x1F3CCBE6); // accent @ 12%
  static const Color accentBorder30 = Color(0x4D3CCBE6); // accent @ 30%
  static const Color accentButtonFill = Color(0x143CCBE6); // accent @ 8%
  static const Color accentActiveFill = Color(0x1F3CCBE6); // accent @ 12%
  static const Color accentBadgeFill = Color(0x263CCBE6); // accent @ 15%
  static const Color accentBorder20 = Color(0x333CCBE6); // accent @ 20%
  static const Color accentRowHover = Color(0x0F3CCBE6); // accent @ 6%
  static const Color surfaceChipFill = Color(0x80141A29); // surface @ 50%
  static const Color surfaceMutedFill = Color(0x148A99B2); // textMuted @ 8%

  /// Wash for a large decorative background glyph — its own category, *below*
  /// the 6/12/30% tint ladder above. See [WpColorsLight.decorativeGlyphWash]
  /// for why the two themes carry different alphas.
  static const Color decorativeGlyphWash = Color(0x0D3CCBE6); // accent @ 5%

  /// Saturated status colors — rich and warm
  static const Color success = Color(0xFF36D98B);
  static const Color warning = Color(0xFFF5C842);
  static const Color error = Color(0xFFFF7B7B);

  /// Danger/off-brand-neutral tint ladder — the same 6/8/12/20/30% alpha steps
  /// as the accent ladder above, keyed to [error]/[textMuted] instead, so a
  /// destructive or neutral control's hover, press and outline carry exactly
  /// the weight of an accent one's, only the hue differs.
  static const Color errorRowHover = Color(0x0FFF7B7B); // error @ 6%
  static const Color errorButtonFill = Color(0x14FF7B7B); // error @ 8%
  static const Color errorActiveFill = Color(0x1FFF7B7B); // error @ 12%
  static const Color errorBorder20 = Color(0x33FF7B7B); // error @ 20%
  static const Color errorBorder30 = Color(0x4DFF7B7B); // error @ 30%
  static const Color mutedRowHover = Color(0x0F8A99B2); // textMuted @ 6%
  static const Color mutedActiveFill = Color(0x1F8A99B2); // textMuted @ 12%

  /// The 12 % rung for the two remaining status hues, so the Quiet Status
  /// Rule's "tinted 32 px icon badge (status color at 12 % fill)" can be
  /// written as a token everywhere instead of a `withValues(alpha: 0.12)` at
  /// each call site. [error] already had its rung above; these complete the
  /// set. No 6 %/30 % rungs: success and warning never carry a hover state or
  /// an outline of their own — they only ever appear as a badge.
  static const Color successActiveFill = Color(0x1F36D98B); // success @ 12%
  static const Color warningActiveFill = Color(0x1FF5C842); // warning @ 12%

  /// Ring that marks the settings section a search hit jumped to — accent at
  /// 55 %, 2 px, painted in the foreground and cleared again after 1.5 s.
  ///
  /// Deliberately *above* the tint ladder's 30 % ceiling and named as its own
  /// category rather than as a stretched top rung, mirroring how
  /// [decorativeGlyphWash] sits below it: 30 % is calibrated for a *resting*
  /// outline the user is already looking at, while this ring has one job in
  /// the opposite direction — be caught in peripheral vision, once, before it
  /// disappears on its own. Nothing else may reach for it; a resting border
  /// that wants to be louder than 30 % is a hierarchy problem, not an alpha
  /// problem.
  ///
  /// Carries the same alpha in both themes, unlike the structural tints above
  /// (see [WpColorsLight.accentSubtle]). Left unsplit on purpose: this value
  /// is calibrated for the peak of something transient, so a per-theme split
  /// would have to be judged against a moving target. If it ever reads heavy
  /// on light, that is a maintainer call with the ring on screen, not a
  /// derivation from the rule.
  static const Color accentLocatorRing = Color(0x8C3CCBE6); // accent @ 55%

  /// Recording/listening family — the one meaning cyan keeps.
  ///
  /// Split off from [accent] so the palette can say two different things with
  /// two different hues: [accent] means "you can act on this", these mean "a
  /// recording or its transcription is in flight" (audio-level bars, the
  /// transcribing rung of the status chip, the onboarding sandbox's live
  /// border). The values below are copied byte-for-byte from [accent] and
  /// [accentWarmGradient] — deliberately *literals*, not aliases: when the
  /// generic family moves off cyan, the recording family must stay where it
  /// is, and an alias would drag it along.
  ///
  /// Every call site is classified in the split's audit table; anything that
  /// is merely tappable, selected, hovered or focused stays on [accent], and
  /// so does everything that reads a state other than the recording phase
  /// (microphone *permission*, STT subprocess boot, an idle mic affordance).
  /// The frozen floating overlay carries the same meaning in its own spec and
  /// is not wired through here.
  static const Color recordingAccent = Color(0xFF3CCBE6);

  /// Gradient twin of [recordingAccent] — cyan to teal, copied from
  /// [accentWarmGradient]. No main-app surface paints a recording gradient
  /// today (the overlay owns that job and keeps its own spec), so this is the
  /// family's reserved home rather than a live call site.
  // loam-ignore: unused-public-exports – required by Ticket 02 AC even
  // without a live call site, so the recording family's gradient home
  // exists before Ticket 04 repoints the generic accentWarmGradient.
  static const LinearGradient recordingAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3CCBE6), Color(0xFF14B8D4), Color(0xFF0A99B8)],
  );

  /// Preflight-screen palette — `WpInsufficientRamScreen` only.
  ///
  /// These three (plus the two badge tints below) are the sanctioned break of
  /// the Theme-Pair Rule and exist **without light counterparts on purpose**:
  /// the insufficient-RAM screen is shown *instead of* the app, never inside
  /// it, renders unconditionally in the dark identity theme and never reads
  /// `Theme` at all — so a light twin would have no code path that could ever
  /// resolve it. Off-limits everywhere else: in the app proper a warning is
  /// [warning] and a destructive action is [error], both theme-paired.
  /// Documented as *The Preflight-Screen Exception* in `lib/DESIGN.md`.
  ///
  /// Orange-600 — used for RAM/hardware preflight warnings.
  static const Color warningOrange = Color(0xFFEA580C);

  /// Fill and border of the preflight warning badge. Named rather than mixed
  /// at the call site, but *not* ladder rungs — the ladder is theme-paired and
  /// these are not, so they carry their own names at their own values.
  static const Color warningOrangeBadgeFill = Color(
    0x26EA580C,
  ); // warningOrange @ 15%
  static const Color warningOrangeBadgeBorder = Color(
    0x66EA580C,
  ); // warningOrange @ 40%

  /// Solid red shades for destructive action buttons (the preflight quit CTA).
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorRedHover = Color(0xFFB91C1C);

  /// Watermark line color — ~3% white for subtle topographic depth.
  static const Color watermark = Color(0x08FFFFFF);

  /// Visible gradient for premium card/container backgrounds
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C2640), Color(0xFF141A29)],
  );

  /// Dual-tone temperature wash — a cool navy top-left, the neutral `surface`
  /// anchor in the middle, and a bottom-right that turns ~34° toward violet
  /// while shedding saturation. Opaque tonal steps (no alpha glow): the three
  /// stops sit 1.08:1 apart in relative luminance, so the content panel reads
  /// as chromatic *temperature* under flat light, never as a lit edge.
  ///
  /// Measured, because the earlier note here was not: the stops are 225° /
  /// 223° / 257°, so the "warm" pole is violet rather than the rose-coral it
  /// was described as, it is no split-complement of `accent` (~190°), and it
  /// lands within a degree of the avatar palette's violet rather than clear of
  /// every avatar hue. What keeps it from reading as a second signal is its
  /// saturation floor — 21%, under half the accent's — not any hue distance.
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17203A), Color(0xFF141A29), Color(0xFF1E1A28)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Frame gradient — nearly flat, matching background for unified look
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF141928), Color(0xFF121726)],
  );

  /// Top accent line gradient
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF3CCBE6), Color(0xFF1AB5E0)],
  );

  /// Warm accent gradient — cyan to teal, rich and saturated
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3CCBE6), Color(0xFF14B8D4), Color(0xFF0A99B8)],
  );

  /// Nav-rail active pill — a *tonal* top-lit gradient on the existing accent,
  /// not a new hue: 20 % accent at the top stop falling to 12 % at the bottom.
  ///
  /// The mean (16 %) sits on top of the flat [accentSubtle] (16.5 %) it
  /// replaces, so the pill gains a lit top edge and a settled base without
  /// getting louder overall. Deliberately *not* [accentWarmGradient] — that
  /// one is opaque, and an opaque accent fill would swallow the accent-colored
  /// icon standing on it.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x333CCBE6), Color(0x1F3CCBE6)],
  );

  /// Glass tint — semi-transparent overlay for frosted panels
  static const Color glassTint = Color(0x18FFFFFF);

  /// Glass border — bright edge on frosted surfaces
  static const Color glassBorder = Color(0x24FFFFFF);
}

// ---------------------------------------------------------------------------
// Light Theme Colors
// ---------------------------------------------------------------------------
abstract final class WpColorsLight {
  /// Window frame — pearl-blue tint for brand identity; analogous to Dark's deep navy
  static const Color background = Color(0xFFE8EFF8);

  /// Content surfaces — cool pearl-white with visible cyan tint (not sterile white)
  static const Color surface = Color(0xFFF2F6FC);

  /// Elevated panels, cards — lighter than surface, still clearly tinted
  static const Color surfaceElevated = Color(0xFFF7FAFD);

  /// Variant surface for alternate rows, secondary panels
  static const Color surfaceVariant = Color(0xFFEBF1F8);
  static const Color hover = Color(0xFFE3EBF5);

  /// Transparent version of hover for smooth AnimatedContainer transitions
  /// (prevents flash when interpolating from transparent to hover)
  static const Color hoverTransparent = Color(0x00E3EBF5);
  static const Color active = Color(0xFFD5DFEE);

  /// Hairline borders — navy-ink at 7.8 % / 14.1 %, a step *under* dark's
  /// 11.8 % / 18.8 %. Same reason as [accentSubtle] below, and the reason is
  /// independent of size: an ink hairline on pearl is a decrement on a bright
  /// ground and reads harder per unit alpha than a white hairline does as an
  /// increment on navy. Matching the bytes would leave the light theme visibly
  /// more ruled than the dark one.
  static const Color borderSubtle = Color(0x140F172A);
  static const Color borderDefault = Color(0x24131F32);

  /// Strong text contrast for light theme
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF44556E);
  static const Color textMuted = Color(0xFF5B697E);

  /// Deep teal accent — analogous to Dark's #3CCBE6, darkened for WCAG AA on
  /// light (≥5.4:1 against both `surface` and `background`; the previous
  /// #0887A8 only reached ≈3.6-3.8:1, under the 4.5:1 AA floor for normal text).
  static const Color accent = Color(0xFF06678A);

  /// Flat accent surface tint, 11 % — a step under dark's 16.5 %, and the
  /// canonical statement of why every *structural* translucent in this file
  /// runs lighter on light (*The Increment–Decrement Rule*, `lib/DESIGN.md`).
  ///
  /// A tint does not buy the same presence in both themes. On light it lands
  /// *darker* than its ground — a decrement, resolved at full contrast against
  /// a bright surface; on dark it lands *lighter* — an increment against a
  /// near-black surface, where the display's black floor and any reflected
  /// room light eat most of the difference. Equal alpha bytes therefore read
  /// visibly unequal, light heavier, so the light side is tuned down instead
  /// of copied across. Same argument, already applied: [navPillActiveGradient]
  /// (16 % → 11 % mean, pinned to exactly this token) and
  /// [decorativeGlyphWash] (5 % → 3 %).
  ///
  /// The tint ladder is the deliberate carve-out: its rungs stay byte-identical
  /// across themes because they are a cross-hue *semantic* scale — 6 % is
  /// "hover" and 30 % is "outline" whatever the hue, whatever the theme — and
  /// re-tuning them per theme would break the guarantee that a destructive
  /// control's states carry exactly the weight of an accent one's.
  static const Color accentSubtle = Color(0x1C06678A); // accent @ 11%

  /// Instance-safe tint tokens — see [WpColorsDark.accentChipFill] for rationale.
  static const Color accentChipFill = Color(0x1A06678A); // accent @ 10%
  static const Color accentChipFillHover = Color(0x2E06678A); // accent @ 18%
  static const Color accentMiniTagFill = Color(0x1F06678A); // accent @ 12%
  static const Color accentBorder30 = Color(0x4D06678A); // accent @ 30%
  static const Color accentButtonFill = Color(0x1406678A); // accent @ 8%
  static const Color accentActiveFill = Color(0x1F06678A); // accent @ 12%
  static const Color accentBadgeFill = Color(0x2606678A); // accent @ 15%
  static const Color accentBorder20 = Color(0x3306678A); // accent @ 20%
  static const Color accentRowHover = Color(0x0F06678A); // accent @ 6%
  static const Color surfaceChipFill = Color(0x80F2F6FC); // surface @ 50%
  static const Color surfaceMutedFill = Color(0x145B697E); // textMuted @ 8%

  /// Transient settings-search locator ring — see
  /// [WpColorsDark.accentLocatorRing], including why this one alpha is *not*
  /// tuned down for light the way the structural tints are.
  static const Color accentLocatorRing = Color(0x8C06678A); // accent @ 55%

  /// Recording/listening family — see [WpColorsDark.recordingAccent] for the
  /// split's rationale. Same deal on light: byte-for-byte copies of [accent]
  /// and [accentWarmGradient], written as literals so the recording signal
  /// stays put when the generic accent family changes hue.
  static const Color recordingAccent = Color(0xFF06678A);

  /// Gradient twin of [recordingAccent] — teal to deep teal, copied from
  /// [accentWarmGradient]. See [WpColorsDark.recordingAccentGradient] for why
  /// the family reserves a gradient it does not paint yet.
  // loam-ignore: unused-public-exports – see WpColorsDark.recordingAccentGradient.
  static const LinearGradient recordingAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06678A), Color(0xFF0E7490), Color(0xFF155E75)],
  );

  /// Wash for a large decorative background glyph — its own category, *below*
  /// the 6/12/30% tint ladder above, because that ladder is defined for
  /// badges, chips and borders: small, bounded shapes the user is meant to
  /// read. A 140px glyph bleeding out of a card corner is neither, and the
  /// ladder's bottom rung is too loud once it covers that much area.
  ///
  /// The alpha is lower here than on dark, and deliberately so — the same
  /// alpha does not buy the same presence in both themes. On light the wash
  /// lands *darker* than its ground (a decrement, which the eye resolves at
  /// lower contrast); on dark it lands *lighter* (an increment), against a
  /// near-black surface where a display's black floor and any reflected room
  /// light eat most of the difference. Equal alphas therefore read unequal —
  /// light visibly stronger — which is exactly what the model step showed.
  /// Both values still sit clearly under the ladder's 6% floor.
  static const Color decorativeGlyphWash = Color(0x0806678A); // accent @ 3%

  /// Danger/off-brand-neutral tint ladder — see [WpColorsDark.errorRowHover]
  /// for rationale.
  static const Color errorRowHover = Color(0x0FCC1C1C); // error @ 6%
  static const Color errorButtonFill = Color(0x14CC1C1C); // error @ 8%
  static const Color errorActiveFill = Color(0x1FCC1C1C); // error @ 12%
  static const Color errorBorder20 = Color(0x33CC1C1C); // error @ 20%
  static const Color errorBorder30 = Color(0x4DCC1C1C); // error @ 30%
  static const Color mutedRowHover = Color(0x0F5B697E); // textMuted @ 6%
  static const Color mutedActiveFill = Color(0x1F5B697E); // textMuted @ 12%

  static const Color success = Color(0xFF05875C);
  static const Color warning = Color(0xFFC97A06);
  static const Color error = Color(0xFFCC1C1C);

  /// 12 % status badge rungs — see [WpColorsDark.successActiveFill].
  static const Color successActiveFill = Color(0x1F05875C); // success @ 12%
  static const Color warningActiveFill = Color(0x1FC97A06); // warning @ 12%

  /// Premium pearl-blue card gradient — subtle diagonal wash
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5F9FD), Color(0xFFEDF3FA)],
  );

  /// Dual-tone temperature wash — cool pearl top-left, neutral anchor,
  /// near-neutral pearl bottom-right. Mirrors [WpColorsDark.warmSurfaceGradient]
  /// in shape only: R/G/B stay within a few points of each other at every
  /// stop, so the drift reads as a tonal-luminance shift, not a color cast —
  /// neither a yellow/beige pole (B as channel minimum) nor a rose/magenta
  /// pole (G as channel minimum) survives here. Drift stays shallow,
  /// luminance flat: opaque tonal steps, no alpha glow.
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF2F7FC), Color(0xFFEFF3F9), Color(0xFFF1F1F5)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Frame gradient — matches background pearl-blue, subtle depth
  static const LinearGradient frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEAF1F9), Color(0xFFE6EDF7), Color(0xFFE5ECF6)],
    stops: [0.0, 0.48, 1.0],
  );

  /// Warm accent gradient — teal to deep teal, consistent with accent
  static const LinearGradient accentWarmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06678A), Color(0xFF0E7490), Color(0xFF155E75)],
  );

  /// Nav-rail active pill — see [WpColorsDark.navPillActiveGradient].
  ///
  /// Light keeps its own, lower alpha pair (14 % → 8 %, mean 11 %) rather than
  /// reusing the dark stops: the deep-teal accent on a near-white pearl
  /// surface reads heavier per unit alpha than cyan on navy does. The mean
  /// again matches the flat [accentSubtle] (11 %) it replaces.
  static const LinearGradient navPillActiveGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x2406678A), Color(0x1406678A)],
  );

  /// Glass tint — soft white overlay for light frosted panels
  static const Color glassTint = Color(0x80FFFFFF);

  /// Glass border — bright edge on frosted surfaces
  static const Color glassBorder = Color(0x40FFFFFF);

  /// Watermark line color — very faint slate tint for subtle topographic depth.
  static const Color watermark = Color(0x0A243B53);
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
}

// ---------------------------------------------------------------------------
// Category slots — the nominal color layer
// ---------------------------------------------------------------------------

/// The nine category slots, in palette order — eight interchangeable *category*
/// hues plus one dedicated [neutral] fallback.
///
/// **The contract.** A category color is never picked at a call site. A widget
/// asks [categorySlotForModel], [categorySlotForTag] or
/// [categorySlotForAvatarRule] for a slot, or reaches for [neutral] when the
/// thing it paints has no category at all — and only then resolves the slot to
/// a [Color] through [color]. The indirection *is* the feature: it makes a hue
/// a statement about the data rather than decoration, and it is the thing a
/// later reader can grep to find out what a color means. Painting one of the
/// constants below directly is the same defect as hand-rolling an alpha.
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

  /// Resolves this slot against the active theme. The only sanctioned way from
  /// a slot to a paintable color.
  Color color(bool isDark) => (isDark
      ? WpCategoryColorsDark.slots
      : WpCategoryColorsLight.slots)[index];

  /// *The Tint Ladder Rule*'s 12 % fill rung, in this slot's hue.
  ///
  /// A rung rather than a call-site alpha, but computed rather than declared:
  /// the ladder's other hues are one token family each because they are one
  /// hue each — nine slots × two rungs × two themes would be 36 constants
  /// restating one number. The ladder's guarantee is that the *weight* is
  /// shared across hues, and that is exactly what these two methods carry.
  Color chipFill(bool isDark) => color(isDark).withValues(alpha: 0.12);

  /// *The Tint Ladder Rule*'s 30 % outline rung, in this slot's hue. See
  /// [chipFill].
  Color chipBorder(bool isDark) => color(isDark).withValues(alpha: 0.30);

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
  /// On dark it lightens, on light it darkens — which means every rung clears
  /// the surfaces by at least as much as the base slot does, and the 3:1 floor
  /// for a graphical object is inherited rather than re-argued per rung. A ramp
  /// laid symmetrically around the slot would sink its low end under that floor
  /// on light.
  ///
  /// **The axis is luminance, not HSL lightness**, because the palette itself is
  /// built on equal relative luminance (see [WpCategoryColorsDark]). Each rung
  /// sits a fixed [_rampStepContrast] contrast ratio from the one before it, so
  /// the rungs are exactly as separable in `moss` as in `plum` — equal steps of
  /// HSL lightness are not, and collapse into each other on the slots that
  /// already sit low. Solving in linear light also makes the step a closed form
  /// instead of a search.
  ///
  /// The two themes mirror rather than share, as everywhere else in this file:
  /// lightening on dark blends toward white and therefore desaturates a little,
  /// while darkening on light is a pure luminance scale that leaves the
  /// chromaticity — and so the hue's identity — untouched.
  ///
  /// Verified per slot, per theme and per step count in
  /// `test/core/theme/wcag_contrast_test.dart`: neighbouring rungs stay ≥ 1.2:1
  /// apart and every rung clears every surface by ≥ 3:1.
  List<Color> ramp(int steps, bool isDark) {
    assert(
      steps >= 3 && steps <= 5,
      'a sequential ramp carries 3–5 steps (The Categorical vs. Sequential '
      'Rule); $steps rungs is a scale the eye can no longer order',
    );
    final base = color(isDark);
    final baseLuminance = base.computeLuminance();
    final r = _srgbToLinear(base.r);
    final g = _srgbToLinear(base.g);
    final b = _srgbToLinear(base.b);

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
        // Scaling every linear channel by the same factor scales Y by it too.
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
/// running out of room: from the palette's Y ≈ 0.30 (dark) / 0.19 (light) base,
/// four steps of 1.22 land at Y ≈ 0.72 and Y ≈ 0.05 — pale and deep, but still
/// hue-bearing rather than white or black.
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
/// **Excluded hue bands, on purpose.** Cyan/teal 165–215° belongs to the brand
/// accent alone (*The Single Accent Rule*); ~30–55° is Pin Amber and `warning`;
/// ~350–15° is `error`; ~145–165° is `success`. A category may not borrow a hue
/// that already means something else in this app.
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

/// Light-theme category slots — the pearl-ground twins of
/// [WpCategoryColorsDark], same hues and saturation (≈58 %), lightness
/// re-solved against the light stack so all nine sit at Y ≈ 0.19: ≈4.0:1
/// against `surface`, over the 3:1 floor and under the light accent's 5.8:1.
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

/// Deterministic slot for an STT model, keyed by its `SttModelInfo.id`.
///
/// Stable across restarts and across model-list edits: the identity is the id,
/// never the list position, so adding a model never re-colors the others.
///
/// **A table, not a hash**, for the same reason as [categorySlotForAvatarRule]:
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

/// Deterministic slot for an avatar rule, keyed by the rule's own identifier
/// (the keyword family that matched, e.g. `'meeting'` or `'email'`).
///
/// The *rule* is the identity, not the entry: two meeting entries get the same
/// hue because they are the same kind of thing, which is precisely what the
/// incumbent title hash could not express. An entry that matches no rule has no
/// category and takes [WpCategorySlot.neutral] — it does not hash.
///
/// **A table, not a hash.** Unlike models and tags, the avatar rules are a
/// closed set of eight known keys facing eight slots, so the assignment can be
/// — and therefore must be — a bijection. A hash cannot promise that over a
/// small domain, and this one does not: `blog` and `personal` both sum onto
/// slot 4, which would paint two categories the same hue while `fern` was never
/// used at all. A key the table does not know still hashes, so a ninth rule
/// keeps working; it just no longer gets the bijection guarantee.
WpCategorySlot categorySlotForAvatarRule(String ruleKey) =>
    _avatarRuleSlots[ruleKey] ?? _categorySlotForIdentity(ruleKey);

/// The eight avatar rules of `history_helpers.dart`, one slot each. Hue affinity
/// is a memory aid, not meaning: the scale is nominal, so any bijection would do.
const Map<String, WpCategorySlot> _avatarRuleSlots = {
  'meeting': WpCategorySlot.azure,
  'email': WpCategorySlot.iris,
  'blog': WpCategorySlot.ember,
  'personal': WpCategorySlot.plum,
  'feedback': WpCategorySlot.orchid,
  'project': WpCategorySlot.fern,
  'idea': WpCategorySlot.brass,
  'reminder': WpCategorySlot.moss,
};

/// The one hash behind the mappers — sum of code units, modulo the slot count —
/// so the repo keeps a single, recognisable "identity → slot" idiom. Sound for
/// user-typed tags, whose domain is genuinely open; the closed sets (avatar
/// rules, model ids) are tabled instead, because over a small domain the hash
/// collides and a bijection is both possible and owed. See
/// [categorySlotForAvatarRule] and [categorySlotForModel] — for those two the
/// hash is only the fallback for a key the table has not met.
///
/// Distributes over [WpCategorySlot.categories] only; [WpCategorySlot.neutral]
/// is unreachable from here by design. An empty identity is a caller bug, not a
/// fallback: it hashes to 0 like any other string. Callers that mean "no
/// category" say so with [WpCategorySlot.neutral].
WpCategorySlot _categorySlotForIdentity(String identity) {
  final hash = identity.codeUnits.fold<int>(0, (a, b) => a + b);
  return WpCategorySlot.categories[hash % WpCategorySlot.categories.length];
}

/// Theme-paired rendering recipe for the history-entry avatar disc.
///
/// The base is a [WpCategorySlot] color, so it already darkens per theme — but
/// the disc is a *translucent* tint over its ground, and a theme pair solved for
/// equal luminance is not the same thing as a pair solved for equal presence
/// through 20–36 % alpha. Every value below is therefore still mirrored rather
/// than merely scaled: on dark the hue is pushed **toward light** and the fill
/// kept thin; on light it is pushed **toward ink** and the fill made *denser*.
/// The denser light fill is the opposite of the usual "light theme needs less
/// ink" compensation, and it is what the measurement asks for: a light slot
/// clears its pearl ground by ≈4.0:1 where a dark one clears navy by ≈5.8:1, so
/// equal alpha would leave the light disc the weaker of the two.
///
/// The lightness shifts are clamped into a legibility band. The band is what
/// keeps the recipe hue-agnostic: a pure shift drives already-dark hues to
/// near-black glyphs on light and washes pale hues out on dark, so the band
/// caps both ends without flattening the hues that sit in between. On today's
/// slots the light bands hold `fern`, `brass`, `moss` and `ember` — the four
/// whose light twins already sit low — while the dark bands never bind at all.
///
/// Calibrated against two contrast targets, verified per slot and per theme in
/// `test/core/theme/wcag_contrast_test.dart`:
/// * disc vs. `surface`/`surfaceElevated` ≥ 1.5:1 (WCAG 1.4.11, graphical
///   object) — the disc has to be *seen*;
/// * glyph vs. disc ≥ 3:1 — the icon has to be *read*.
///
/// Both targets pull against each other on light (a denser disc drags the glyph
/// further toward ink), which is why they are calibrated together.
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
  /// Positive on dark, negative on light — the mirror that makes the fill
  /// separate from its ground instead of dissolving into it.
  final double fillLightnessShift;

  /// Legibility band for the shifted fill lightness.
  final double fillLightnessMin;
  final double fillLightnessMax;

  /// Extra lightness delta of the lit stop over the shaded one. Carries the
  /// same sign as [fillLightnessShift]: "lit" means away from the ground.
  final double topStopLightnessDelta;

  /// Lightness shift applied to the palette hue for the glyph. Same sign as
  /// [fillLightnessShift] but larger, so the icon separates from the disc it
  /// sits on. Keep it clear of `fillLightnessShift + topStopLightnessDelta` —
  /// at equality the glyph and the lit stop collapse onto the same color and
  /// only their alphas still tell them apart.
  final double glyphLightnessShift;

  /// Legibility band for the shifted glyph lightness.
  final double glyphLightnessMin;
  final double glyphLightnessMax;

  /// Dark theme: thin fill, hue pushed lighter, glyph lighter still.
  static const WpAvatarTint dark = WpAvatarTint._(
    fillTopAlpha: 0.28,
    fillBottomAlpha: 0.20,
    edgeAlpha: 0.30,
    glyphAlpha: 0.95,
    fillLightnessShift: 0.12,
    fillLightnessMin: 0.45,
    fillLightnessMax: 0.86,
    topStopLightnessDelta: 0.12,
    glyphLightnessShift: 0.20,
    glyphLightnessMin: 0.55,
    glyphLightnessMax: 0.92,
  );

  /// Light theme: denser fill (not thinner), hue pushed toward ink, glyph
  /// darker still — every sign mirrored against [dark].
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

  static WpAvatarTint of(bool isDark) => isDark ? dark : light;

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
// Decorative layer — chrome surfaces, no meaning
// ---------------------------------------------------------------------------

/// Dark-theme decorative source — *Quartz*, a 314° mauve at ≈52 % saturation.
///
/// **Its own layer, and the third hue family outside the accent** (after Pin
/// Amber and the category slots). It exists to make the app's *chrome* — the
/// nav rail, the settings ground — a distinguishable plate rather than the
/// same flat field as the content, and it carries no information whatsoever.
/// See *The Decorative Color Rule* in `lib/DESIGN.md`, which is what sanctions
/// it (maintainer decision ④ = b, 2026-08-11).
///
/// **Never cyan.** Cyan/teal stays the brand accent alone (decision ② = b), so
/// the decorative layer may not borrow from it — otherwise the one voice the
/// app has would also be its wallpaper.
///
/// **Why hue proximity is not the guarantee.** 314° sits 18° from `orchid`
/// (296°) and 18° from `plum` (332°), stated rather than argued away: every
/// gap left on the wheel by the accent band, the status hues and the eight
/// slots is about that wide. What keeps this layer apart from the nominal one
/// is *form*, and form is testable — a category slot is an opaque, bounded
/// mark you are meant to read, while this hue only ever appears as a ≤5 %
/// field over a whole surface, at a contrast under the 1.5:1 a graphical
/// object has to clear to register as an object at all. The same argument the
/// [WpColorsDark.warmSurfaceGradient] comment already makes: what keeps a
/// large low-chroma field from reading as a second signal is its weight, not
/// its hue distance.
abstract final class WpDecorativeColorsDark {
  /// The single decorative hue. Never painted at full strength — the app only
  /// ever sees it through [chromeWash].
  static const Color source = Color(0xFFDA8BC8);

  /// The one decorative fill: [source] at 5 %, flat, over a whole surface.
  ///
  /// Below the tint ladder, where *The Decorative Glyph Rule* already puts the
  /// large-area washes, and per theme like everything down there (*The
  /// Increment–Decrement Rule*) — but the light value is **measured, not
  /// inherited**; see [WpDecorativeColorsLight.chromeWash].
  static const Color chromeWash = Color(0x0DDA8BC8); // source @ 5%
}

/// Light-theme decorative source — the pearl-ground twin of
/// [WpDecorativeColorsDark], same 314° hue at ≈58 % saturation with its
/// lightness re-solved toward ink so the wash lands *darker* than its ground.
abstract final class WpDecorativeColorsLight {
  static const Color source = Color(0xFFA12B86);

  /// [source] at 2 % — a third of the dark twin's presence, and the one value
  /// in this file that a *legibility* budget sets rather than an optical one.
  ///
  /// The chrome wash lies under the page ground, which is where a settings row
  /// puts its `textMuted` subtitle. On the pearl frame that pairing starts at
  /// 4.69:1 — 0.19 over AA — so every point the wash darkens the ground comes
  /// straight out of that margin: at the glyph rule's 3 % it lands on 4.48:1
  /// and the decoration has cost legibility, which is the one thing it may
  /// never do. 2 % holds 4.56:1. On dark the same text starts at 6.19:1 and
  /// has room to spare, so that side is optically tuned as usual.
  ///
  /// The per-theme direction is still *The Increment–Decrement Rule*'s — light
  /// under dark — the size of the step is simply not free here.
  static const Color chromeWash = Color(0x05A12B86); // source @ 2%
}

/// The only sanctioned way to a decorative color.
///
/// It takes `isDark` and **nothing else** — no id, no index, no identity —
/// which is the executable half of the rule: a call site physically cannot
/// vary the decorative hue per nav item or per settings section, so the layer
/// cannot grow into a category scale. That is the mirror image of
/// [categorySlotForModel] and friends, whose *parameter* is the evidence that
/// a category color means something.
Color wpDecorativeChromeWash(bool isDark) => isDark
    ? WpDecorativeColorsDark.chromeWash
    : WpDecorativeColorsLight.chromeWash;

/// The translucent scrim behind a [BackdropFilter]-blurred dialog barrier.
///
/// Needs true black/white rather than a themed surface token — the blur
/// already carries the surface tint, this only needs to darken/lighten what
/// shows through it. Was duplicated verbatim across five dialog widgets.
Color wpDialogBarrierColor(bool isDark) {
  return (isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
      .withValues(alpha: isDark ? 0.45 : 0.35);
}

/// Creates a frosted-glass [BoxDecoration] suitable for cards and panels.
///
/// Subtle, not heavy — just enough to hint at depth and translucency.
/// Use with [ClipRRect] + [BackdropFilter] for the full glass effect.
BoxDecoration wpGlassDecoration({
  required bool isDark,
  BorderRadius? borderRadius,
  double borderOpacity = 1.0,
}) {
  return BoxDecoration(
    color: isDark ? WpColorsDark.glassTint : WpColorsLight.glassTint,
    borderRadius: borderRadius ?? WpRadius.borderMd,
    border: Border.all(
      color: (isDark ? WpColorsDark.glassBorder : WpColorsLight.glassBorder)
          .withValues(alpha: borderOpacity * (isDark ? 0.094 : 0.251)),
    ),
  );
}

/// A widget that applies a subtle frosted-glass effect to its child.
///
/// Wraps content in [ClipRRect] + [BackdropFilter] with a translucent tint.
/// The blur is deliberately light (sigmaX/Y = 12) for a premium, soft look.
class WpGlassPanel extends StatelessWidget {
  const WpGlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma = 12.0,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final br = borderRadius ?? WpRadius.borderMd;

    // On Windows frameless windows, BackdropFilter + ImageFilter.blur is
    // broken, so fall back to a solid opaque panel fill.
    final bool useBlur = !Platform.isWindows;

    final decoration = useBlur
        ? wpGlassDecoration(isDark: isDark, borderRadius: br)
        : wpGlassDecoration(isDark: isDark, borderRadius: br).copyWith(
            color: isDark
                ? WpColorsDark.surfaceElevated
                : WpColorsLight.surfaceElevated,
          );

    final content = Container(
      decoration: decoration,
      padding: padding,
      child: child,
    );

    return ClipRRect(
      borderRadius: br,
      child: useBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: content,
            )
          : content,
    );
  }
}
