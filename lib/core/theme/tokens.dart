/// WhisPaste design tokens — Single Source of Truth for all visual styling.
///
/// Premium design: clean depth via layered surfaces, crisp shadows, tonal
/// gradients, and warm materiality. Restraint means no glow and a single
/// brand accent (cyan/teal) — not bare/flat; warm, soft-shadowed depth is
/// equally premium.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// ---------------------------------------------------------------------------
// Spacing scale (px → logical pixels)
// ---------------------------------------------------------------------------
abstract final class WpSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ---------------------------------------------------------------------------
// Border radius
// ---------------------------------------------------------------------------
abstract final class WpRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double full = 9999;

  static final BorderRadius borderSm = BorderRadius.circular(sm);
  static final BorderRadius borderMd = BorderRadius.circular(md);
  static final BorderRadius borderLg = BorderRadius.circular(lg);
  static final BorderRadius borderXl = BorderRadius.circular(xl);
  static final BorderRadius borderFull = BorderRadius.circular(full);
}

// ---------------------------------------------------------------------------
// Shadows — clean layered depth, NO colored/glow shadows
// ---------------------------------------------------------------------------
abstract final class WpShadows {
  // Apple-grade ambient depth: soft, diffuse, low-opacity — larger blur,
  // gentler alpha than crisp/tight shadows.
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Same geometry as [subtle], alpha 0. Lets an AnimatedContainer fade the
  /// *alpha* channel when a shadow toggles off, instead of retargeting
  /// `subtle -> null`: `BoxShadow.lerpList` handles a null target by scaling
  /// blur/offset toward zero at *fixed* alpha, which concentrates the ink
  /// into a smaller, harder-edged patch for one frame before it's fully
  /// gone — a visible flash rather than a fade (most noticeable in light
  /// theme, where this shadow has real contrast against pearl surfaces).
  static const List<BoxShadow> subtleTransparent = [
    BoxShadow(color: Color(0x00000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  // -- Light-theme interaction shadows (history polish pass, 2026-07-28) -----
  //
  // Black-alpha shadows read much heavier over the pearl light surfaces than
  // over the dark navy ones: composited on `WpColorsLight.surface` (#F2F6FC,
  // rel. luminance 0.92) the dark-theme alphas produce a clearly visible dark
  // haze — [subtle] (12 % black) ≈ 1.32:1 and [card]'s first layer (20 %
  // black) ≈ 1.60:1 against the surface. The light variants halve the alpha,
  // landing at ≈ 1.14:1 and ≈ 1.26:1 — still a perceptible material lift,
  // no longer a dark halo. Same geometry, so Animated fades stay smooth.

  /// [subtle] at light-theme strength (6 % instead of 12 % black).
  static const List<BoxShadow> subtleLight = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// [card] at light-theme strength (10 % / 4 % instead of 20 % / 8 %).
  static const List<BoxShadow> cardLight = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 14, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Theme-resolved [subtle]: full strength on dark, halved on light.
  static List<BoxShadow> subtleFor(bool isDark) =>
      isDark ? subtle : subtleLight;

  /// Theme-resolved [card]: full strength on dark, halved on light.
  static List<BoxShadow> cardFor(bool isDark) => isDark ? card : cardLight;

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Warm inner shadow for glass panels — subtle top-light illusion
  static const List<BoxShadow> glassInner = [
    BoxShadow(
      color: Color(0x0AFFFFFF),
      blurRadius: 1,
      offset: Offset(0, 1),
      blurStyle: BlurStyle.inner,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Motion / Animation durations + easing
//
// ## Easing-Set Rules (Apple-grade premium motion — Phase A)
//
// | Slot             | Curve / Description              | Duration cap     | Use for                                      |
// |------------------|----------------------------------|------------------|----------------------------------------------|
// | defaultCurve     | Curves.easeOut                   | fast / normal    | All standard UI transitions                  |
// | smooth_          | Curves.easeInOut                 | smooth / dramatic | Enter/exit cross-fades, page transitions    |
// | spring           | easeOutCubic (no overshoot)      | smooth (300 ms)  | Signature recording-arc appear/dismiss ONLY  |
// | springDescription | SpringDescription 170/26        | physics-based    | Physics-spring consumers (SpringSimulation)  |
//
// Caps (Phase 0 measurements, macOS 60 Hz):
//   Signature transition  — Soft-Cap 300 ms / Hard-Cap 700 ms
//   All other motion      — ≤ 200–300 ms (defaultCurve / easeOut)
//   Hover in              — 0 ms (instant, prevents flicker between adjacent targets)
//   Hover out             — 80 ms
//
// Always prefer [durationFor] over raw Duration constants to respect the
// system "Reduce Motion" accessibility flag.
//
// ## Motion scale reference (doc-only)
//   fast            → 120 ms
//   normal          → 200 ms
//   smooth          → 300 ms
//   dramatic        → 500 ms
//   hoverIn         → 0 ms (instant)
//   hoverOut        → 80 ms
//   spring curve    → easeOutCubic (cubic-bezier 0.215, 0.61, 0.355, 1.0)
//   spring mass     → 1 | stiffness → 170 | damping → 26
// ---------------------------------------------------------------------------
abstract final class WpMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration smooth = Duration(milliseconds: 300);
  static const Duration dramatic = Duration(milliseconds: 500);

  /// Instant hover transitions — no animation prevents flicker when moving
  /// between adjacent items (Discord / Notion style).
  static const Duration hoverIn = Duration.zero;
  static const Duration hoverOut = Duration(milliseconds: 80);

  static const Curve defaultCurve = Curves.easeOut;

  /// Signature spring curve — critically-damped cubic-bezier approximation
  /// (no overshoot / bouncing). Approximates [springDescription] (Gentle
  /// 170/26, ratio ≈ 1.0). Replaces the former Curves.elasticOut.
  ///
  /// Use exclusively for the recording-arc (capsule appear / dismiss).
  /// For physics-based simulation, use [springDescription] instead.
  static const Curve spring = Curves.easeOutCubic;

  /// Critically-damped spring parameters (Phase-0 Gentle preset, ratio ≈ 1.0,
  /// no overshoot). For use with [SpringSimulation] in physics-based animations.
  /// Curve-based callers use [spring].
  static const SpringDescription springDescription = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 26,
  );

  static const Curve smooth_ = Curves.easeInOut;

  /// Returns [duration] as-is, unless the system accessibility flag
  /// "Reduce Motion" is active — in that case returns [Duration.zero]
  /// (immediate state change, no movement). Prefer this over raw constants
  /// in every animated widget.
  static Duration durationFor(BuildContext context, Duration duration) {
    if (MediaQuery.of(context).disableAnimations) return Duration.zero;
    return duration;
  }
}

// ---------------------------------------------------------------------------
// Layout dimensions
// ---------------------------------------------------------------------------
abstract final class WpLayout {
  static const double sidebarWidth = 72;
  static const double statusBarHeight = 48;
  static const double appBarHeight = 64;

  /// Material 3 minimum touch target — all interactive elements must meet this.
  static const double minTouchTarget = 48;

  /// Responsive breakpoints (mobile-first).
  static const double breakpointMobile = 600;
}

// ---------------------------------------------------------------------------
// Navigation rail geometry
//
// The icon-only sidebar's internal measurements. They used to sit inline in
// `sidebar.dart` *and* a second time in the now-deleted
// `sidebar_settings_button.dart`, where they had already drifted apart — the
// rail is chrome visible on every page, so a 1 px divergence between the nav
// items and the pinned settings entry shows up on every screen at once.
// Named here so both the rail and its screenshot shells read the same numbers.
// ---------------------------------------------------------------------------
abstract final class WpNavRail {
  /// Full width of one rail row — spans [WpLayout.sidebarWidth] so the whole
  /// row is the tap target, not just the pill.
  static const double itemWidth = WpLayout.sidebarWidth;

  /// Height of one rail row (pill plus its breathing room).
  static const double itemHeight = 42;

  /// The rounded square behind the icon; carries the active state's fill,
  /// hairline and elevation.
  static const double pillSize = 38;

  /// Active-item accent bar, flush with the reading-start window edge.
  static const double indicatorWidth = 3;
  static const double indicatorHeight = 22;

  /// Group-break hairline between nav sections. Deliberately narrower than
  /// [pillSize] so it reads as a quiet break, not a full-width rule.
  static const double dividerWidth = 36;
  static const double dividerThickness = 1;

  /// Unread/attention dot rendered at the pill's reading-end top corner.
  static const double badgeSize = 8;

  /// Inset of the badge from the pill's own top/end edge. The badge lives in
  /// the row-sized stack (like the indicator bar), so the offsets below add
  /// the pill's centering margin — that keeps the dot on the pill's corner
  /// instead of the rail's, and keeps it clear of the glyph.
  static const double badgeInset = 2;

  /// Badge offset from the row's top edge: pill centering margin + inset.
  static const double badgeTop = (itemHeight - pillSize) / 2 + badgeInset;

  /// Badge offset from the row's reading-end edge: same derivation.
  static const double badgeEnd = (itemWidth - pillSize) / 2 + badgeInset;
}

// ---------------------------------------------------------------------------
// Icon sizes
//
// Usage rules (mobile-first):
//   xs (14), sm (16) → Decorative/metadata icons ONLY (status dots, timestamps)
//   md (20)          → MINIMUM for interactive icons (buttons, chips, actions)
//   lg (24)          → Standard interactive (toolbar buttons, nav icons)
//   xl (32), xxl (48)→ Prominent / hero icons
// ---------------------------------------------------------------------------
abstract final class WpIconSize {
  static const double xs = 14;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ---------------------------------------------------------------------------
// Typography scale (px) — mirrors the roles `theme.dart`'s TextTheme already
// defines (headlineLarge 22, headlineMedium/labelLarge 16, titleLarge 17,
// titleMedium 14, titleSmall/bodyLarge/bodyMedium/labelMedium 13, bodySmall
// 12, labelSmall 11) plus `micro`, a smaller metadata/caption size already in
// consistent use across history, settings and analytics UI.
//
// Prefer `Theme.of(context).textTheme.<role>` for themed text. Reach for
// these named constants only where a bespoke `TextStyle` genuinely needs a
// literal size (e.g. it overrides color/weight/height so heavily that a
// `textTheme` base with `copyWith` isn't a faithful fit) — so the value stays
// traceable to the scale instead of a bare magic number.
// ---------------------------------------------------------------------------
abstract final class WpTypography {
  static const double micro = 10;
  static const double caption = 11;
  static const double small = 12;
  static const double body = 13;
  static const double subheading = 14;
  static const double heading = 16;
  static const double title = 17;
  static const double headline = 22;
}
