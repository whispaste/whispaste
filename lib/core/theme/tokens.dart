/// WhisPaste design tokens — Single Source of Truth for all visual styling.
///
/// Premium design: clean depth via layered surfaces, crisp shadows, tonal
/// gradients, and warm materiality. Restraint means no glow and a single
/// brand accent (cyan/teal) — not bare/flat; warm, soft-shadowed depth is
/// equally premium. "Single accent" is about the *brand voice*: the pin marker
/// and the category slots (`WpCategorySlot`) carry hues of their own, but they
/// state what something *is*, never that it is important. See *The Single
/// Accent Rule* and *The Categorical vs. Sequential Rule* in `lib/DESIGN.md`.
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

  /// Height of a *dense* control — the trailing slot of a settings-style row.
  ///
  /// Three things share that slot and each had picked its own height: the
  /// dense [WpButton] (32), the key caps of `HotkeyDisplay` (30, from padding
  /// plus border) and the microphone-permission chip (30, likewise). Standing
  /// next to each other in one visual line, a 2-px difference does not read as
  /// two sizes — it reads as one size, misaligned. Naming the value is what
  /// keeps the three from drifting apart again the next time one of them
  /// changes its padding.
  ///
  /// Below [minTouchTarget] by design: these sit *inside* a row that already
  /// meets the touch target, and a 48-px control in a trailing slot out-shouts
  /// the row it answers to (see `WpButtonSize.dense`).
  static const double denseControlHeight = 32;

  /// Chrome stacked above and below the nav rail in the app shell: the title
  /// bar and the status bar, both fixed-height in every state.
  static const double frameChromeHeight = appBarHeight + statusBarHeight;

  /// What `minimumSize` costs before any of it reaches Flutter.
  ///
  /// `window_manager` hands the value to the platform's *window* minimum, not
  /// to the client area: `NSWindow.minSize` on macOS, `ptMinTrackSize` in
  /// `WM_GETMINMAXINFO` on Windows, GDK geometry hints on Linux. With
  /// `TitleBarStyle.hidden` the difference is small but not zero — the Windows
  /// plugin's own `WM_NCCALCSIZE` handler shrinks the client rect by 8 px at
  /// the bottom (plus 1 px at the top on Windows 10), so a bare 609 would
  /// arrive in the engine as ~600 dp and put the rail 8 dp into its scroll
  /// fallback at the very size the app enforces. 12 covers that worst case
  /// (the 9 px are physical, so they shrink at every scale above 100 %) and
  /// leaves a few dp for fractional-scale rounding on the other two
  /// platforms.
  static const double windowFrameAllowance = 12;

  /// Smallest window the app lets itself be resized to (`window_manager`
  /// `minimumSize`, applied in `main.dart`).
  ///
  /// The height is not a taste value: it is the point at which the nav rail
  /// stops needing its scroll fallback, plus what the window frame eats —
  /// [WpNavRail.productionContentHeight] (497) + [frameChromeHeight] (112) +
  /// [windowFrameAllowance] (12) = 621. Deriving it means adding a nav item
  /// raises the minimum with it instead of silently re-introducing the
  /// overflow this constant exists to prevent;
  /// `sidebar_height_budget_test.dart` measures the real rail against it.
  ///
  /// Kept as small as that derivation allows rather than rounded to a
  /// comfortable number: on a 1366×768 panel every dp here is one the user
  /// does not get back, and at that panel's 125 % scaling the work area is
  /// already ~576 dp — below what the rail needs at all, so that combination
  /// is the scroll fallback's territory by construction. Which is precisely
  /// why both halves of the fix exist together.
  static const double minWindowWidth = 800;
  static const double minWindowHeight =
      WpNavRail.productionContentHeight +
      frameChromeHeight +
      windowFrameAllowance;

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

  /// Vertical padding each rail row carries above and below itself.
  static const double rowPadding = WpSpacing.xs;

  /// Full vertical space one rail row occupies, padding included.
  static const double rowHeight = itemHeight + 2 * rowPadding;

  /// Full vertical space one group-break hairline occupies, padding included.
  static const double dividerRowHeight = dividerThickness + 2 * rowPadding;

  /// Gap the rail keeps between its last (bottom-pinned) row and the status
  /// bar underneath it.
  static const double bottomInset = WpSpacing.md;

  /// Height the production rail needs before it has to scroll: the seven nav
  /// rows from `wpNavItems`, the one group break from `wpNavDividerAfterIds`,
  /// the pinned settings row from `wpSettingsNavItem`, plus [bottomInset].
  ///
  /// 8 × 58 + 17 + 16 = 497. The rail itself never reads this number — it
  /// lays out from the rows above — but [WpLayout.minWindowHeight] does, and
  /// `sidebar_height_budget_test.dart` measures the real rail against it so
  /// the two cannot drift apart unnoticed.
  static const double productionContentHeight =
      8 * rowHeight + dividerRowHeight + bottomInset;

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
