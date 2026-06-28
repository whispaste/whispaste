/// WhisPaste design tokens — Single Source of Truth for all visual styling.
///
/// Premium design: clean depth via layered surfaces, crisp shadows, and
/// subtle gradients. No glow effects — restraint IS premium.
library;

import 'package:flutter/material.dart';

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
// Motion / Animation durations
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
  static const Curve spring = Curves.elasticOut;
  static const Curve smooth_ = Curves.easeInOut;
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
