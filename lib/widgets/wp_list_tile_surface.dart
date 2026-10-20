import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
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
// ## Variants, one recipe
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
//   * [WpListTileVariant.overview] — a full-width list with no detail pane
//     open (history overview). The row is a quiet card: frost fill, 1 px
//     neutral edge, `md` radius, so a short list does not read as bare text.
//
// Everything the variants share is fixed here and cannot drift again: the
// hover-in/hover-out motion and the tile state rules. Radius and resting border
// width are per variant (`overview` is the one that differs). Guarded by
// `test/widgets/list_tile_surface_consistency_test.dart`, which compares the
// four real call sites *against each other* rather than
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
// row. Replacements, snippets and notes use it. Notes' favourite star and row
// actions form one trailing group centred on the body, so the 48 px touch
// boxes set the body's minimum height instead of stacking on its padding.
//
// History passes its actions inside [child] instead, because they belong to
// one specific *line* of a multi-line tile: the three actions share the
// metadata line with the timestamp, and hoisting them to the envelope would
// move them visually. The slot is an offer, not an obligation.
// ---------------------------------------------------------------------------

/// Which surface a list row sits on — see the library comment for why this
/// is the only axis the tile envelope varies along.
enum WpListTileVariant {
  /// Opaque card on a full-width page (replacements, snippets).
  card,

  /// Transparent-at-rest row in a narrow split-view panel (history, notes).
  panel,

  /// Quiet card row in a full-width list with no detail open (history
  /// overview). It reads as a row on the page ground: frost fill, a 1 px
  /// neutral edge and the smaller `md` radius, with the same tile state
  /// rules as [card] (hover/focus brighten, selection tints).
  overview,
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

  /// The row is the one shown in the detail pane (panel variant only). In the
  /// overview variant it means "checked" (multi-select) and tints the fill.
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

  /// Vertical padding of the panel row (spec §3: 16/14). Off the spacing scale
  /// on purpose; 14 is the row's own rhythm, not a list gap.
  static const double panelVerticalPadding = 14;

  /// Hairline gap between rows so adjacent selection borders never touch.
  /// Off-scale on purpose — `WpSpacing.xxs` would read as a list gap.
  static const double panelVerticalMargin = 1.0;

  /// Resting border width, shared by the card and panel variants. The
  /// dark-theme selection stroke is the single documented exception (2 px,
  /// see [_border]). The overview variant draws a 1 px edge instead, see
  /// [overviewBorderWidth].
  static const double borderWidth = 1.5;

  /// Edge width of the [WpListTileVariant.overview] row.
  static const double overviewBorderWidth = 1.0;

  bool get _isActive => isHovered || isFocused || isSelected;

  Color _fill() {
    switch (variant) {
      case WpListTileVariant.card:
      case WpListTileVariant.overview:
        // Frost, not `surfaceElevated`/`hover`: a card row is a translucent
        // tinted plate over the one ambient gradient, so the ground keeps
        // running underneath the list instead of being cut into opaque bands.
        // The hover delta is deliberately quiet (~1.03:1) — it is carried
        // jointly by the fill and the tinted edge in [_border], and the row's
        // real hover affordance is the action slot it reveals.
        return _isActive ? WpColors.cardFillElevated : WpColors.cardFill;
      case WpListTileVariant.panel:
        // Selected rows are white cards, never a cyan wash (WP-14 §3).
        if (isSelected) {
          return WpColors.surfaceElevated;
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
        if (isSelected) {
          return Border.all(
            color: WpColors.controlEdge,
            width: overviewBorderWidth,
          );
        }
        // Active edge is the tinted `cardEdgeHighlight` rather than the
        // neutral `cardActiveBorder`: on a frost plate the rim is what carries
        // the shape, and a white rim over a chromatic fill is the exact
        // "reads grey" failure the frost material was introduced to fix.
        return Border.all(
          color: _isActive ? WpColors.cardEdgeHighlight : WpColors.borderSubtle,
          width: borderWidth,
        );
      case WpListTileVariant.overview:
        if (isSelected) {
          return Border.all(
            color: WpColors.controlEdge,
            width: overviewBorderWidth,
          );
        }
        return Border.all(
          color: _isActive ? WpColors.cardEdgeHighlight : WpColors.borderSubtle,
          width: overviewBorderWidth,
        );
      case WpListTileVariant.panel:
        final accent = WpColors.accent;
        // One width in every state, the same resting width as the other list
        // areas (see list_tile_surface_consistency_test): a state change must
        // not move the label.
        if (isSelected) {
          return Border.all(color: WpColors.controlEdge, width: borderWidth);
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
          horizontal: WpSpacing.md,
          vertical: panelVerticalPadding,
        );
      case WpListTileVariant.overview:
        return const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        );
    }
  }

  BorderRadius _radius() {
    switch (variant) {
      // One radius for every row (WP-14 §3: selected row radius 10).
      case WpListTileVariant.overview:
      case WpListTileVariant.card:
      case WpListTileVariant.panel:
        return BorderRadius.circular(WpRadiusTokens.control);
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
      case WpListTileVariant.overview:
        // 8 px between rows: each row carries 4 px above and below.
        return const EdgeInsets.symmetric(vertical: WpSpacing.xxs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = _padding();
    // With an actions slot the vertical padding moves from the envelope onto
    // the content, next to the actions. The actions box (48 px, reserved by
    // WpRowActions) is then the row's minimum height: a single-line row is
    // 48 px at least, and a multi-line one keeps its full padding above and
    // below to the divider. Callers must keep 48 px touch targets out of the
    // content column, or the content's own floor would add to this padding.
    final hasActions = actions != null;
    final content = !hasActions
        ? child
        : Row(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: padding.top),
                  child: child,
                ),
              ),
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
      padding: hasActions
          ? EdgeInsets.symmetric(horizontal: padding.left)
          : padding,
      decoration: BoxDecoration(
        color: _fill(),
        borderRadius: _radius(),
        border: _border(),
      ),
      child: variant == WpListTileVariant.panel
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                // The rule sits at the text start (inside the horizontal
                // padding). It is transparent when selected so both states
                // keep the same height and label position.
                Container(
                  key: const ValueKey('wp-list-tile-divider'),
                  height: 1,
                  color: isSelected
                      ? Colors.transparent
                      : WpColors.borderSubtle,
                ),
              ],
            )
          : content,
    );
  }
}
