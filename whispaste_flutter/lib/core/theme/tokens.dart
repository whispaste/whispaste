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
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 18;
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
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x26000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 1),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 2),
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

  static const Curve defaultCurve = Curves.easeOut;
  static const Curve spring = Curves.elasticOut;
  static const Curve smooth_ = Curves.easeInOut;
}

// ---------------------------------------------------------------------------
// Layout dimensions
// ---------------------------------------------------------------------------
abstract final class WpLayout {
  static const double sidebarWidth = 72;
  static const double sidebarWidthExpanded = 220;
  static const double statusBarHeight = 34;
  static const double fabSize = 56;
  static const double appBarHeight = 64;
  static const double pageMaxWidth = 720;
}

// ---------------------------------------------------------------------------
// Icon sizes
// ---------------------------------------------------------------------------
abstract final class WpIconSize {
  static const double xs = 14;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}
