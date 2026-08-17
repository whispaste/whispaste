import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// WpListTileSurface — the one tile envelope for every list row in the app
// (history list, notes, replacements, snippets).
//
// Sibling of `wp_row_action.dart`, and for the same reason: four areas had
// hand-rolled the same envelope and drifted apart. Before this widget the
// four decorations differed in ways nobody had decided on — snippets and
// replacements drew a 1.0 px border, notes and history 1.5 px; snippets and
// replacements had no shadow at all while notes/history faded one in on
// interaction; the radius was `md` on two areas and `lg` on the other two.
// Rows that sit two clicks apart in the same window should not disagree
// about what a row *is*, so the recipe now lives in exactly one place.
//
// ## Two variants, one recipe
//
// The split is not cosmetic — it follows the surface a list sits on:
//
//   * [WpListTileVariant.card] — full-width page lists (replacements,
//     snippets) inside `WpSearchableListPage`. The row is a card on the page
//     ground: it carries a visible resting border and a frost fill, because
//     with nothing else on the page an invisible row edge would leave the list
//     shapeless. No selection state — these rows open a dialog, they are never
//     "the current one".
//   * [WpListTileVariant.panel] — narrow split-view panels (history, notes).
//     The row is transparent at rest so a dense list stays quiet
//     (DESIGN.md "Quiet Signal"), and spends its ink on the states that
//     matter in a panel with a detail pane: selection and the keyboard
//     cursor, both drawn in accent.
//
// Everything the two share is fixed here and cannot drift again: radius
// (`WpRadius.borderLg`), resting border width (1.5) and the hover-in/hover-out
// motion. Guarded by `test/widgets/list_tile_surface_consistency_test.dart`,
// which compares the four real call sites *against each other* rather than
// against numbers.
//
// ## Why there is no shadow (Ticket 08)
//
// Until the visual refresh the card variant lifted itself on hover with
// `WpShadows.subtle` *on top of* a fill change — two depth cues on one
// element. On the app's single dark ground depth comes from the brightness
// delta alone; a drop shadow under a row that sits *in* the plane rather than
// above it only muddies the ambient gradient it is supposed to let through.
// The row's state now reads entirely off its fill and its edge. (Shadows are
// not banned app-wide: an element that genuinely floats over unknown content —
// dialog, toast, dropdown popup — still gets exactly one.)
//
// ## Why the border is never null
//
// It is always present and animates its *alpha*. `Border.lerp(a, null, t)`
// scales the width toward zero at fixed colour, which for one frame reads as a
// flash, not a fade. A zero-alpha `Border.all` exists for exactly this, and
// the whole app depends on it being used rather than re-derived.
//
// ## The actions slot
//
// [actions] is a trailing slot at the *envelope* level: the row's content
// gets the flexible remainder, the actions get their intrinsic width, and
// `WpRowActions` reserves its own height so revealing them never reflows the
// row. Replacements and snippets use it — their single action genuinely
// belongs to the row as a whole.
//
// History and notes deliberately pass their actions inside [child] instead,
// because theirs belong to one specific *line* of a multi-line tile:
// history's three actions share the metadata line with the timestamp, and
// notes' trash actions sit on the title line next to the relative date.
// Hoisting them to the envelope would move them visually. The slot is an
// offer, not an obligation.
// ---------------------------------------------------------------------------

/// Which surface a list row sits on — see the library comment for why this
/// is the only axis the tile envelope varies along.
enum WpListTileVariant {
  /// Opaque card on a full-width page (replacements, snippets).
  card,

  /// Transparent-at-rest row in a narrow split-view panel (history, notes).
  panel,
}

/// The shared envelope of every list row: fill, radius, border, shadow fade
/// and hover/focus/selected states, plus an optional trailing [actions] slot.
///
/// Callers own their content and their own hover tracking (they usually need
/// the hover flag for other things too, such as revealing row actions) and
/// hand the resulting state in.
class WpListTileSurface extends StatelessWidget {
  const WpListTileSurface({
    super.key,
    required this.variant,
    required this.child,
    this.isHovered = false,
    this.isFocused = false,
    this.isSelected = false,
    this.actions,
  }) : assert(
         variant != WpListTileVariant.card || !isSelected,
         'Card rows open a dialog and are never "the current one" — '
         'selection is a panel-variant state.',
       );

  final WpListTileVariant variant;

  /// Pointer is over the row.
  final bool isHovered;

  /// The row is the keyboard cursor's current target. In the panel variant
  /// this draws its own accent border; in the card variant it shares the
  /// hover appearance, because a card row's focus is already announced by
  /// [WpFocusRing] at the call site.
  final bool isFocused;

  /// The row is the one shown in the detail pane (panel variant only).
  final bool isSelected;

  /// Optional trailing actions at the envelope level — typically a
  /// `WpRowActions`. See the library comment for when *not* to use it.
  final Widget? actions;

  final Widget child;

  /// Horizontal inset from the panel edge to the row edge, for the panel
  /// variant.
  ///
  /// Zero on purpose: the *list* owns the page inset (`WpSpacing.xl`) so that
  /// a row's edge lands on exactly the same vertical as the search bar above
  /// it and as the date headers between rows. Rows carrying their own
  /// horizontal margin is what made history sit 16 px inside every other
  /// area's edge.
  static const double panelHorizontalMargin = 0.0;

  /// Hairline gap between rows so adjacent selection borders never touch.
  /// Off-scale on purpose — `WpSpacing.xxs` would read as a list gap.
  static const double panelVerticalMargin = 1.0;

  /// Resting border width, shared by both variants. The dark-theme selection
  /// stroke is the single documented exception (2 px, see [_border]).
  static const double borderWidth = 1.5;

  bool get _isActive => isHovered || isFocused || isSelected;

  Color _fill() {
    switch (variant) {
      case WpListTileVariant.card:
        // Frost, not `surfaceElevated`/`hover`: a card row is a translucent
        // tinted plate over the one ambient gradient, so the ground keeps
        // running underneath the list instead of being cut into opaque bands.
        // The hover delta is deliberately quiet (~1.03:1) — it is carried
        // jointly by the fill and the tinted edge in [_border], and the row's
        // real hover affordance is the action slot it reveals.
        return _isActive ? WpColors.cardFillElevated : WpColors.cardFill;
      case WpListTileVariant.panel:
        if (isSelected) {
          return WpColors.accentSubtle;
        }
        if (isFocused || isHovered) {
          return WpColors.hover;
        }
        return WpColors.hoverTransparent;
    }
  }

  Border _border() {
    switch (variant) {
      case WpListTileVariant.card:
        // Active edge is the tinted `cardEdgeHighlight` rather than the
        // neutral `cardActiveBorder`: on a frost plate the rim is what carries
        // the shape, and a white rim over a chromatic fill is the exact
        // "reads grey" failure the frost material was introduced to fix.
        return Border.all(
          color: _isActive ? WpColors.cardEdgeHighlight : WpColors.borderSubtle,
          width: borderWidth,
        );
      case WpListTileVariant.panel:
        const accent = WpColors.accent;
        if (isSelected) {
          // Light-theme ink is deliberately reduced (history polish pass,
          // 2026-07-28): the light accent #06678A is itself dark
          // (rel. luminance ≈ 0.11), so a 2 px @ 0.7 stroke was the darkest
          // ink in the whole list (≈ 3.4:1 against the 0.92-lum surface) and
          // read as "much too dark". 1.5 px @ 0.6 keeps the stroke at
          // ≈ 2.9:1 — still clearly visible on top of the tinted fill and the
          // lifted shadow — with ~45 % less ink. Dark keeps the approved
          // full-strength values, and is the one place the shared
          // [borderWidth] is exceeded.
          return Border.all(color: accent.withValues(alpha: 0.7), width: 2);
        }
        if (isFocused) {
          return Border.all(
            color: accent.withValues(alpha: 0.5),
            width: borderWidth,
          );
        }
        return Border.all(
          color: accent.withValues(alpha: 0),
          width: borderWidth,
        );
    }
  }

  EdgeInsets _padding() {
    switch (variant) {
      case WpListTileVariant.card:
        return const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        );
      case WpListTileVariant.panel:
        return const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.md,
        );
    }
  }

  EdgeInsets _margin() {
    switch (variant) {
      case WpListTileVariant.card:
        // The list's `separatorBuilder` owns the gap between card rows.
        return EdgeInsets.zero;
      case WpListTileVariant.panel:
        return const EdgeInsets.symmetric(
          horizontal: panelHorizontalMargin,
          vertical: panelVerticalMargin,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = actions == null
        ? child
        : Row(
            children: [
              Expanded(child: child),
              actions!,
            ],
          );

    return AnimatedContainer(
      duration: WpMotion.durationFor(
        context,
        _isActive ? WpMotion.hoverIn : WpMotion.hoverOut,
      ),
      curve: WpMotion.defaultCurve,
      margin: _margin(),
      padding: _padding(),
      decoration: BoxDecoration(
        color: _fill(),
        borderRadius: WpRadius.borderLg,
        border: _border(),
        // No `boxShadow` at all — see the library comment. A row lives in the
        // plane; its depth is the brightness delta.
      ),
      child: content,
    );
  }
}
