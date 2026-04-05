/// WhisPaste design tokens — Single Source of Truth for all visual styling.
///
/// These values implement the premium design system documented in
/// copilot-instructions.md. Never hardcode colors, spacing, or typography
/// values — always reference these tokens.
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
  static const double full = 9999;

  static final BorderRadius borderSm = BorderRadius.circular(sm);
  static final BorderRadius borderMd = BorderRadius.circular(md);
  static final BorderRadius borderLg = BorderRadius.circular(lg);
  static final BorderRadius borderFull = BorderRadius.circular(full);
}

// ---------------------------------------------------------------------------
// Shadows (dark theme — layered, NOT colored)
// ---------------------------------------------------------------------------
abstract final class WpShadows {
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x33000000), blurRadius: 1),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

// ---------------------------------------------------------------------------
// Motion / Animation durations
// ---------------------------------------------------------------------------
abstract final class WpMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration smooth = Duration(milliseconds: 300);

  static const Curve defaultCurve = Curves.easeOut;
  static const Curve spring = Curves.elasticOut;
  static const Curve smooth_ = Curves.easeInOut;
}

// ---------------------------------------------------------------------------
// Sidebar dimensions
// ---------------------------------------------------------------------------
abstract final class WpLayout {
  static const double sidebarWidth = 70;
  static const double statusBarHeight = 36;
  static const double fabSize = 56;
  static const double appBarHeight = 48;
}
