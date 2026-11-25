import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'focus_first_in.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

// ---------------------------------------------------------------------------
// WpRowAction — the one row-level icon action for every list in the app
// (history list/card/compact view, notes, replacements, snippets).
//
// Grew out of history's `HistoryRowAction`, which was the most mature of the
// four hand-rolled variants that used to exist (focusable, hover tint, own
// destructive-red state). Lives in `lib/widgets/` so notes/replacements/
// snippets can use it without importing from `lib/features/history/`
// (internal-notes §5.9: no feature-to-feature dependency).
//
// ## Visibility: reveal on hover or focus — and why
//
// The two candidate patterns were "always visible, dimmed at rest" (the old
// notes tile) and "reveal on hover" (the old history rows). Reveal wins, and
// the deciding argument is width, not taste:
//
//   The history list panel is user-resizable down to 240 px
//   (`WpCollectionSplit._minListWidth`). After tile margin, padding and the
//   type glyph, a row has well under 200 px left for title + actions.
//   Three permanently visible actions cost 84 px (dense) to 144 px
//   (48 px targets) of that — the title would be squeezed to a few pixels or
//   nothing at all. Permanent actions simply do not fit the narrow end of
//   the layout, so they cannot be the app-wide pattern.
//
// DESIGN.md's "Quiet Signal" doctrine points the same way: a resting list
// stays quiet. The two costs usually held against reveal are handled here
// rather than accepted:
//
//   * **Nothing gets displaced.** Callers keep persistent content (the
//     history timestamp) in its own slot and let the *flexible* element (the
//     title) absorb the reveal. Actions never take over another element's
//     place, so no information disappears on hover.
//   * **Nothing jumps.** `WpRowActions` reserves its height whether or not
//     the actions are showing, so revealing them never reflows the row.
//
// Keyboard: an unmounted widget cannot be focused, so reveal must not depend
// on the pointer alone. Every caller reveals on `hover || row-has-focus`, and
// keeps the group mounted while one of its own buttons holds focus. Focus is
// drawn exclusively by `WpFocusRing` ("One Highlight Per State").
//
// Item rows (recordings, notes, snippets) share one action set in one order:
// Copy, Star, Delete (#1498, `WpListItemActions`). At rest a favourite shows
// a non-interactive star mark after the title (`WpListItemStarMark`), so the
// state stays visible without a second always-on control. Anything else
// (Duplicate, setting the quick-note mark) lives in the row's context menu
// and as a screen-reader custom action, so a row never reveals more than
// three actions.
//
// Exception, deliberate: the notes quick-note mark stays visible and
// tappable in both states, after the title. It is the row's only carrier of
// that state and has no resting mark of its own; it is a state indicator
// that happens to be tappable, not a hidden action.
//
// ## Sizes and the touch target
//
// Standard (48 px): the tap area is `WpLayout.minTouchTarget` square
// (`WpTouchTarget`); the painted action stays 44 px. Used wherever a row has
// room for it (replacements).
//
// Dense (28 px): the documented exception to the 48 px rule — DESIGN.md,
// "The Confirmed Dense-Row Exception", decision E6 = (a), confirmed by the
// maintainer on 2026-08-10. A dense action is its 28 px box and nothing more:
// no enlarged tap surround, so the row is as tall as its icon needs.
//
// Why dense is a width budget, not a taste call: item rows put up to three
// actions on the title line (`WpListItemContent`, the same layout on
// recordings, notes and snippets), inside a panel the user can drag down to 240 px
// (`WpCollectionSplit._minListWidth`). Measured at a 340 px panel that line is 237 px
// wide. Three dense actions cost 84 px of it; three 48 px actions would cost
// 144 px, more than half the line before the title has any room. At the 240 px
// minimum the title would be left with nothing. Notes sits in the same narrow
// panel. The compact history view is the honest shortfall: its rows are ~27 px
// by design, so even 28 px only just fits, and it keeps the dense variant.
//
// A revealed action must never be taller than its line, or every mouse move
// would reflow the list. So the split moves only if the action count or the
// panel's minimum width moves, and any new call site picks its variant by the
// same budget.

// ---------------------------------------------------------------------------

class WpRowAction extends StatefulWidget {
  const WpRowAction({
    super.key,
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.onTap,
    this.isDestructive = false,
    this.activeColor,
    this.dense = false,
    this.testId,
    this.toggled,
    this.semanticsLabel,
  }) : assert(icon != null || faIcon != null, 'Provide icon or faIcon');

  final IconData? icon;
  final FaIconData? faIcon;
  final String tooltip;

  /// Null disables the action: dimmed, no hover, reported as disabled. The
  /// tooltip stays, so it can say why.
  final VoidCallback? onTap;
  final bool isDestructive;

  /// When set, overrides the icon color regardless of hover/active state.
  final Color? activeColor;

  /// Compact variant for inline list rows where vertical space is tight.
  /// Drops the outer padding and the 48 px tap surround: the 28 px box is the
  /// whole target. The documented exception to the 48 px rule, see the
  /// library docs above.
  final bool dense;

  /// Stable id, exposed as the accessibility identifier (`<screen>-<element>`).
  final String? testId;

  /// Set for a state toggle (e.g. a favorite star): reported to screen
  /// readers as on or off. Null for a plain action.
  final bool? toggled;

  /// Screen-reader name when it should differ from [tooltip], e.g. a toggle
  /// named after its state instead of the action the tooltip describes.
  final String? semanticsLabel;

  /// Full extent a single action occupies, tap area included. Callers reserve
  /// this so a revealed action never changes the row's height: 48 for the
  /// standard variant, 28 for the dense exception.
  static double extentFor({required bool dense}) =>
      dense ? _denseExtent : WpLayout.minTouchTarget;

  /// The dense box: a 16 px icon with 6 px padding on each side.
  static const double _denseExtent = 28;

  @override
  State<WpRowAction> createState() => _WpRowActionState();
}

class _WpRowActionState extends State<WpRowAction> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpRowAction');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// The 48 px surround for the standard variant; dense is its own target.
  Widget _maybeTouchTarget({required Widget child}) =>
      // loam-ignore: a11y-interactive-semantics – the wrapped child keeps its own role and label; WpTouchTarget only enlarges the tap area and is excluded from semantics (see wp_touch_target.dart).
      widget.dense ? child : WpTouchTarget(onTap: widget.onTap, child: child);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final hovered = enabled && _isHovered;
    final Color iconColor;
    if (!enabled) {
      // Dimmer than an idle action, so "not now" differs from "off".
      iconColor = WpColors.textMuted.withValues(alpha: 0.5);
    } else if (widget.activeColor != null) {
      iconColor = widget.activeColor!;
    } else if (widget.isDestructive && hovered) {
      iconColor = WpColors.error;
    } else if (hovered) {
      iconColor = WpColors.textPrimary;
    } else {
      iconColor = WpColors.textMuted;
    }

    return Semantics(
      label: widget.semanticsLabel ?? widget.tooltip,
      button: true,
      enabled: enabled,
      toggled: widget.toggled,
      identifier: widget.testId,
      // The Semantics above names the action; the tooltip is visual only,
      // otherwise screen readers announced the name twice (#1498).
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        preferBelow: false,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: _maybeTouchTarget(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.dense ? 0 : WpSpacing.xxs,
                vertical: widget.dense ? 0 : WpSpacing.xxs,
              ),
              child: WpFocusRing(
                focusNode: _focusNode,
                radius: WpRadius.sm,
                child: InkWell(
                  onTap: widget.onTap,
                  focusNode: _focusNode,
                  borderRadius: WpRadius.borderSm,
                  // WpFocusRing owns all focus visuals — suppress InkWell's own.
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: AnimatedContainer(
                    duration: WpMotion.durationFor(context, WpMotion.fast),
                    // Off-scale on purpose: icon-button padding tuned so the
                    // dense/regular variants land on their intended hit sizes;
                    // snapping to xxs/xs/sm would resize every row action.
                    padding: EdgeInsets.all(widget.dense ? 6 : 10),
                    decoration: BoxDecoration(
                      color: hovered
                          ? (WpColors.active)
                          : (WpColors.hoverTransparent),
                      borderRadius: WpRadius.borderSm,
                    ),
                    // A fixed square: icon-font glyphs take their own advance
                    // width (the solid star is 18 px at size 16), which made
                    // the same action 28 or 30 px wide depending on the glyph
                    // (#1498). The glyph stays centred and may overhang into
                    // the padding; the hit area no longer follows it.
                    child: SizedBox.square(
                      dimension: WpIconSize.sm,
                      child: OverflowBox(
                        maxWidth: double.infinity,
                        child: widget.faIcon != null
                            ? FaIcon(
                                widget.faIcon!,
                                size: WpIconSize.sm,
                                color: iconColor,
                              )
                            : Icon(
                                widget.icon!,
                                size: WpIconSize.sm,
                                color: iconColor,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trailing group of [WpRowAction]s with the app-wide reveal behaviour.
///
/// Holds its height whether or not [visible] is true, so revealing the
/// actions never reflows the row (see the library comment above); the width
/// collapses to zero while hidden, which is what buys the title its space
/// back on narrow panels.
///
/// In a `WpListTileSurface` actions slot this reserved height is the row's
/// minimum body: the surface pads the content around it, and the 48 px box
/// sets the floor for single-line rows (see that widget's `actions` notes).
///
/// Keeps itself revealed while one of its buttons holds keyboard focus, so
/// tabbing through a row's actions cannot pull the ground out from under the
/// focused button.
class WpRowActions extends StatefulWidget {
  const WpRowActions({
    super.key,
    required this.visible,
    required this.children,
    this.dense = false,
  });

  /// Pointer/keyboard state of the surrounding row — typically
  /// `isHovered || isFocused`.
  final bool visible;

  /// Must match the `dense` flag of the [WpRowAction]s in [children].
  final bool dense;

  final List<Widget> children;

  @override
  State<WpRowActions> createState() => _WpRowActionsState();
}

class _WpRowActionsState extends State<WpRowActions> {
  bool _hasFocusWithin = false;

  /// True while focus sits on [_entryNode] and is being handed on to the
  /// first action. The entry stays focusable exactly for that hand-off.
  bool _handingOff = false;

  /// The group's single keyboard stop while the actions are hidden. Tab lands
  /// here, the group reveals itself and focus moves on to the first action.
  /// Each row therefore costs one Tab stop, not one per action, and no
  /// [WpRowAction] is mounted while the group is hidden.
  final FocusNode _entryNode = FocusNode(debugLabel: 'WpRowActions.entry');

  /// Holds the revealed actions, so the hand-off can name the first one.
  final FocusNode _actionsNode = FocusNode(
    debugLabel: 'WpRowActions.actions',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _entryNode.dispose();
    _actionsNode.dispose();
    super.dispose();
  }

  void _onEntryFocusChange(bool hasFocus) {
    if (hasFocus) {
      setState(() => _handingOff = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The first action by name, not `nextFocus()`: from the zero-width
        // entry the geometric order picked the last action, so Tab skipped
        // Copy and Star (#1845).
        if (mounted && _handingOff && !focusFirstIn(_actionsNode)) {
          _entryNode.nextFocus();
        }
      });
    } else if (_handingOff) {
      setState(() => _handingOff = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.visible || _hasFocusWithin;
    return SizedBox(
      height: WpRowAction.extentFor(dense: widget.dense),
      child: Focus(
        // Not a tab stop of its own — it only listens for focus landing on
        // the entry or on one of the actions below it.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (_hasFocusWithin == hasFocus) return;
          setState(() => _hasFocusWithin = hasFocus);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zero-width while hidden: the group keeps its width budget.
            ExcludeSemantics(
              child: Focus(
                focusNode: _entryNode,
                canRequestFocus: !show || _handingOff,
                onFocusChange: _onEntryFocusChange,
                child: SizedBox(
                  width: 0,
                  height: WpRowAction.extentFor(dense: widget.dense),
                ),
              ),
            ),
            if (show)
              Focus(
                focusNode: _actionsNode,
                canRequestFocus: false,
                skipTraversal: true,
                child: FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
