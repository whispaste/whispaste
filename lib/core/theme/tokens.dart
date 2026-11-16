/// WhisPaste design tokens — Single Source of Truth for all visual styling.
///
/// Premium design: clean depth via layered surfaces, tinted material, tonal
/// gradients. Restraint means no light effects (UIA-VIS-12) and exactly two accents with two jobs —
/// violet-magenta for "you can act on this", cyan/teal for "a recording is in
/// flight" — not bare/flat; soft, tinted depth is equally premium. The two
/// accents are the *brand voice*: the pin marker and the category slots
/// (`WpCategorySlot`) carry hues of their own, but they state what something
/// *is*, never that it is important. See *The Categorical vs. Sequential Rule*
/// in `lib/DESIGN.md` for that last distinction.
///
/// The two-accent split and the one-depth-source-per-theme split are both new
/// with this token set and are stated here rather than cited: `lib/DESIGN.md`
/// still documents the superseded single-accent doctrine and is rewritten in a
/// follow-up ticket. Two accents, two exclusive jobs: violet-magenta means "you
/// can act on this", cyan/teal means "a recording is in flight" — no element
/// may reach for the other family to look important. One depth source: the
/// brightness delta between the card fills, and no card shadow at all.
///
/// > **Retracted 2026-08-11 (dark-only build).** This paragraph used to close
/// > with "one depth source per *theme*: light uses a soft, wide, tinted
/// > shadow ([WpShadows.cardTintedLight]), dark uses the brightness delta
/// > between its fills and gets no shadow at all." The per-theme half went
/// > with the light theme; the surviving clause is the dark one, which was
/// > always the app's real depth source. Recorded rather than reworded so the
/// > tinted-shadow token's disappearance has a reason attached to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'generated/wp_tokens.g.dart' show WpShellTokens;

export 'generated/wp_tokens.g.dart' show WpTypography;

// ---------------------------------------------------------------------------
// Spacing scale (px → logical pixels)
// ---------------------------------------------------------------------------
abstract final class WpSpacing {
  /// Hairline gap between a stacked title and its subtitle, between an icon
  /// and a tight caption, and between tightly packed marks (wave dots, chip
  /// icon and label). The only step below [xxs]; never for layout.
  static const double xxxs = 2;
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// The one gap between two buttons side by side (#1687): text buttons,
  /// outlined icon buttons, the dialog footer pair. Lay groups out with
  /// `WpButtonGroup` or a `Wrap` with this spacing, never flush. Exempt:
  /// ghost icon buttons and row actions, which show no box at rest, and the
  /// compact slot strip of an editor head (`WpHeadActions.gap`).
  static const double buttonGap = sm;
}

// ---------------------------------------------------------------------------
// Border radius
// ---------------------------------------------------------------------------
// The app's radius scale. Steps that the token source also names carry the
// same value (sm = `radius.control`, xl = `radius.surface`; guard test in
// tokens_test.dart). Micro steps below sm come from [WpRadiusTokens.xs] and
// [WpRadiusTokens.chip]. Decision and exceptions: design-tokens/README.md.
abstract final class WpRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  // Was 22 (off the 4 px grid, next to the 20 px surface token); #1369.
  static const double xl = 20;
  static const double full = 9999;

  static final BorderRadius borderSm = BorderRadius.circular(sm);
  static final BorderRadius borderMd = BorderRadius.circular(md);
  static final BorderRadius borderLg = BorderRadius.circular(lg);
  static final BorderRadius borderXl = BorderRadius.circular(xl);
  static final BorderRadius borderFull = BorderRadius.circular(full);
}

// ---------------------------------------------------------------------------
// Shadows — clean layered depth, NO colored shadows (UIA-VIS-12)
// ---------------------------------------------------------------------------
abstract final class WpShadows {
  // Resting surfaces (cards, rows, fields) carry no shadow: their depth comes
  // from fill and edge. Only floating surfaces use `elevated`; `card` is the
  // floating frame of the snippet picker window (UIA-FND-13 V2).
  //
  // Apple-grade ambient depth: soft, diffuse, low-opacity — larger blur,
  // gentler alpha than crisp/tight shadows.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  // Art on the onboarding paintings (maintainer 2026-10-30): the painting gets a
  // faint vignette that darkens only the outer edge. The mark on it casts no
  // shadow (§7: shadows only for floating surfaces).
  static const Color artVignette = Color(0x2E000000);

  // -- Light-theme interaction shadows: removed 2026-08-11 (dark-only) -------
  //
  // `subtleLight` (6 % black) and `cardLight` (10 % / 4 %) halved the alpha of
  // [card] because black-alpha shadows read much heavier over the
  // pearl light surfaces than over the dark navy ones. With no light stack to
  // composite against, both tokens lost their only ground and are deleted
  // rather than left as unreachable constants.
  //
  // Their resolvers `subtleFor(isDark)` and `cardFor(isDark)` are gone too.
  // Both were kept for one commit as named entry points, on the theory that a
  // shadow which used to vary by theme should keep somewhere to vary again.
  // Once the argument came off there was nothing left to keep: each was a
  // second name for a constant declared a few lines above it, and a second
  // name is not a seam. Call sites read [card] and [elevated] directly.

  // A short offset with a wide, faint blur. The former 10 px offset at 25 %
  // alpha, plus a 2 px contact shadow, left a hard grey strip under every
  // light card: the offset reached past the soft part of the blur, so the
  // shadow read as a second, detached shape (the "Loch" effect, UX-020/UX-032;
  // render check in the ticket worktree). The lift stays; the strip is gone.
  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 2)),
  ];

  // A free-standing control that floats over the stage, such as the round
  // contact launcher: on navy the faint [elevated] lift disappears, so this
  // mirrors the website token `--wp-shadow-overlay` (0 12 32, black 30 %).
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  // -- cardTintedLight: removed 2026-08-11 (dark-only) ----------------------
  //
  // The light theme's one card shadow — soft, wide, violet-tinted, offset
  // (`0x14281446`, blur 35, offset (0, 10)) — mirroring the deleted
  // `WpColorsLight.cardShadowLight`. It was **light-theme only by refusal**:
  // on dark, depth comes from the brightness delta between the card fills and
  // a shadow on near-black adds mud, not depth. With the light stack gone the
  // refusal is the only case left, so the token has no theme to serve.
  //
  // A colored shadow at offset zero is forbidden (UIA-VIS-12). A plain shadow
  // is offset + wide blur + low alpha, and it may be tinted.
}

// ---------------------------------------------------------------------------
// Material elevation — only where a Material popup surface needs it
// ---------------------------------------------------------------------------
abstract final class WpElevation {
  /// Floating menu panels anchored to a control (the dock's dropdown menus).
  /// Matches Material's own menu elevation so the panel reads as one layer
  /// above the dock, like the system popups next to it. Resting surfaces stay
  /// at zero (theme: no Material elevation) and use fill and edge instead.
  static const double menu = 8;
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
//   waitCycle       → 1200 ms (one loop of a "working" indicator)
//   spring curve    → easeOutCubic (cubic-bezier 0.215, 0.61, 0.355, 1.0)
//   spring mass     → 1 | stiffness → 170 | damping → 26
// ---------------------------------------------------------------------------
abstract final class WpMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration smooth = Duration(milliseconds: 300);
  static const Duration dramatic = Duration(milliseconds: 500);

  /// Hover delay before every tooltip in the app (UIA-FND-12).
  static const Duration tooltipWait = Duration(milliseconds: 400);

  /// Instant hover transitions — no animation prevents flicker when moving
  /// between adjacent items (Discord / Notion style).
  static const Duration hoverIn = Duration.zero;
  static const Duration hoverOut = Duration(milliseconds: 80);

  /// Settings deep-link highlight: the tint fades in quickly, then fades out
  /// slowly once the row has had its moment (1.5 s hold, see settings_page).
  static const Duration highlightIn = Duration(milliseconds: 150);
  static const Duration highlightOut = Duration(milliseconds: 1500);

  /// One loop of an indeterminate "working" indicator (the wave of the
  /// processing dots): slow enough to read as waiting, not as alarm.
  static const Duration waitCycle = Duration(milliseconds: 1200);

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

/// Drop-in [AnimatedSize] that a zero [duration] passes straight through
/// instead of animating.
///
/// [AnimatedSize] restarts its internal [AnimationController] from inside its
/// own `performLayout` whenever the child's size changes while it is
/// `stable`. With [duration] resolved to [Duration.zero] (as
/// [WpMotion.durationFor] does under reduced motion) that restart completes
/// synchronously and calls `markNeedsLayout` on itself while still being laid
/// out — a hard Flutter assertion ("A RenderObject must not re-dirty itself
/// while still being laid out"), reproduced in
/// `test/core/theme/motion_test.dart`. A zero-duration transition is not an
/// animation to begin with, so skipping [AnimatedSize] for that case is the
/// correct behavior, not merely a workaround for the assertion.
class WpAnimatedSize extends StatelessWidget {
  const WpAnimatedSize({
    super.key,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Layout dimensions
// ---------------------------------------------------------------------------
abstract final class WpLayout {
  /// Navigation sidebar width (chat-08/10). Below
  /// [WpShellTokens.breakpointCompact] it collapses to the icon-only rail.
  static const double sidebarWidth = WpShellTokens.sidebarWidth;
  static const double sidebarWidthCompact = WpShellTokens.sidebarWidthCompact;

  /// Window title bar (the frame row above sidebar and content).
  static const double appBarHeight = WpShellTokens.titleBarHeight;

  /// Recording dock footprint: the dock plus its inset to the window edge.
  /// It runs full width under the sidebar and the content panel.
  static const double dockAreaHeight =
      WpShellTokens.dockHeight + WpShellTokens.dockInset;

  /// Material 3 minimum touch target — all interactive elements must meet this.
  static const double minTouchTarget = 48;

  /// Visible height of every standard control that can share a line with
  /// another: `WpTextField` (`form`, `embedded`), `WpSearchField`, the
  /// `WpDropdown` trigger, the standard `WpButton` and `WpIconButton`
  /// (UX-131). One number,
  /// so a field and the button or dropdown beside it end on the same two
  /// edges; `WpControlRow` keeps them there when the text size grows.
  static const double controlHeight = WpShellTokens.controlHeight;

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

  /// Chrome stacked above the nav rail and the page in the app shell: the
  /// title bar and the recording dock, both fixed-height in every state.
  static const double frameChromeHeight = appBarHeight + dockAreaHeight;

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
  /// [WpNavRail.productionContentHeight] + [frameChromeHeight] (title bar above
  /// the rail, recording dock below it) + [windowFrameAllowance]. Deriving it means adding a nav item
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

  /// Responsive breakpoints.
  ///
  /// These are not one scale with the shell and dock thresholds
  /// (`WpShellTokens` 960/1440, `WpDockTokens` 1000/720 in the generated
  /// file). Each set follows its own layout, so a value here is changed only
  /// together with a screenshot check of the affected layout (UIA-FND-15).
  ///
  /// Content width from which the Übersicht splits into a flexible main
  /// column (hints, newest recordings) and a fixed side column of key figures
  /// ([overviewSideColumn] wide, [overviewColumnGap] apart). Below it the
  /// page is one column with the figures as a strip above the recordings.
  static const double breakpointOverviewTwoColumn = 960;

  /// Width of the Übersicht's figures column.
  static const double overviewSideColumn = 320;

  /// Gap between the Übersicht's two columns.
  static const double overviewColumnGap = WpSpacing.xl;

  /// Narrowest detail column that still reads as a document. Below it, a
  /// master/detail split (list + divider + this detail) is abandoned for the
  /// focused full-width detail — `WpCollectionSplit` derives its collapse width from
  /// the list minimum, the divider and this value.
  static const double minReadableDetailWidth = 440;

  /// Widest a note beside a row or button gets, so a sentence stays readable.
  static const double noteMaxWidth = 320;
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
  /// Width of the icon-only rail (below the compact breakpoint).
  static const double compactItemWidth =
      WpLayout.sidebarWidthCompact - 2 * inset;

  /// Largest factor the expanded rail grows by when the text scale is above
  /// 1.0 (UX-033). At the cap the label column is about 270 px, which holds
  /// the longest working-area word in de/en/he at 2.0x without breaking it;
  /// beyond the cap, labels wrap onto a second line instead of growing more.
  static const double maxTextScaleWidthFactor = 1.5;

  /// One entry is 44 high (chat-08).
  static const double itemHeight = WpShellTokens.navItemHeight;

  /// Vertical gap between entries: 52 px pitch measured on the mockup.
  static const double itemGap = WpSpacing.xs;

  static const double rowHeight = itemHeight + itemGap;

  /// Horizontal inset of the entry boxes from the sidebar edge.
  static const double inset = WpSpacing.sm;

  /// Leading padding inside an entry, before the icon.
  static const double contentStart = WpSpacing.md;

  /// Icon–label distance (16 on the mockup).
  static const double iconLabelGap = WpSpacing.md;

  /// Lucide outline icon size on the entries (22).
  static const double iconSize = 22;

  /// Group divider: a 1 px hairline centred in this much vertical space.
  static const double groupBreakHeight = WpSpacing.xl;

  /// Brand artwork (original word-and-image mark, logo mark when compact),
  /// 40 high so the lettering stays legible, and the gaps around it. The gap
  /// shrank by what the artwork grew, keeping the rail's height budget.
  static const double brandTop = WpSpacing.md;
  static const double brandHeight = 40;
  static const double brandGap = WpSpacing.md;

  static const double bottomInset = WpSpacing.md;

  /// Height the rail needs without any scrolling: brand block, the six
  /// working entries, one group break, the two pinned entries, bottom inset.
  static const double productionContentHeight =
      brandTop +
      brandHeight +
      brandGap +
      6 * rowHeight +
      // Two group breaks between the six working areas (after History and
      // after Replacements) plus the break above the pinned Help/Settings pair.
      3 * groupBreakHeight +
      2 * rowHeight +
      bottomInset;

  /// Radius of the active-entry fill (8) and the 3 px start bar.
  static const double activeRadius = WpRadius.sm;
  static const double indicatorWidth = 3;

  /// Attention dot on an entry (update available).
  static const double badgeSize = 8;
}

// ---------------------------------------------------------------------------
// Icon sizes
//
// Usage rules (touch target and hit area):
//   xxs (12), xs (14), sm (16) → Decorative/metadata icons ONLY (status dots, timestamps)
//   smMd (18)        → Icons in toasts, segmented selectors and the RAM notice
//   md (20)          → MINIMUM for interactive icons (buttons, chips, actions)
//   lg (24)          → Standard interactive (toolbar buttons, nav icons)
//   xl (32), xxl (48)→ Prominent / hero icons
// ---------------------------------------------------------------------------
abstract final class WpIconSize {
  /// Smallest step, for dense metadata glyphs such as filter bars (UIA-FND-10).
  static const double xxs = 12;
  static const double xs = 14;
  static const double sm = 16;

  /// Between [sm] and [md] (UIA-FND-10).
  static const double smMd = 18;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ---------------------------------------------------------------------------
// Typography: the one scale is generated from `design-tokens/app.tokens.json`
// (`WpTypography` in `generated/wp_tokens.g.dart`, re-exported above, #197).
// Prefer `Theme.of(context).textTheme.<role>`; reach for a `WpTypography`
// size only where a bespoke `TextStyle` genuinely needs a literal size.
// ---------------------------------------------------------------------------
