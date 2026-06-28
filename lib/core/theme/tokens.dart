/// WhisPaste design tokens — Single Source of Truth for all visual styling.
///
/// Premium design: clean depth via layered surfaces, crisp shadows, and
/// subtle gradients. No glow effects — restraint IS premium.
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

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

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
// ## Figma Motion Variable Mirror (doc-only; Figma has no animation-curve scope)
// Keep in sync with the Figma "Motion" variable collection:
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
  static const double breakpointTablet = 900;
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
