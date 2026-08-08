import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

// ---------------------------------------------------------------------------
// WpRowAction — the one row-level icon action for every list in the app
// (history list/card/compact view, notes, replacements, snippets).
//
// Grew out of history's `HistoryRowAction`, which was the most mature of the
// four hand-rolled variants that used to exist (focusable, hover tint, own
// destructive-red state). Lives in `lib/widgets/` so notes/replacements/
// snippets can use it without importing from `lib/features/history/`
// (CONTEXT.md §5.9: no feature-to-feature dependency).
//
// ## Visibility: reveal on hover or focus — and why
//
// The two candidate patterns were "always visible, dimmed at rest" (the old
// notes tile) and "reveal on hover" (the old history rows). Reveal wins, and
// the deciding argument is width, not taste:
//
//   The history list panel is user-resizable down to 240 px
//   (`HistorySplitView._minListWidth`). After tile margin, padding and the
//   42 px avatar, a row has ~146 px left for title + timestamp + actions.
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
// Exception, deliberate: a *leading* glyph that is the row's only carrier of
// a persistent state — the notes favourite star — stays visible in both
// states. It is a state indicator that happens to be tappable, not a hidden
// action. History carries the same state on the avatar badge instead.
//
// ## Sizes and the 48 px touch target
//
// `lib/DESIGN.md` asks for a 48 px minimum touch target. A revealed action
// must not be taller than the row it appears in, or every mouse move would
// reflow the list — so the row's resting height, not the rule, sets the
// action height: 44 px (standard) where the row is roomy, 28 px (dense) in
// the tight ones. The compact history view is the honest shortfall: its rows
// are ~27 px by design ("dense power-user list"), and three 48 px targets
// would also overflow its non-flexible trailing metadata at 240 px. Density
// is the whole point of that view, so it keeps the dense variant.
// ---------------------------------------------------------------------------

class WpRowAction extends StatefulWidget {
  const WpRowAction({
    super.key,
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
    this.activeColor,
    this.dense = false,
  }) : assert(icon != null || faIcon != null, 'Provide icon or faIcon');

  final IconData? icon;
  final FaIconData? faIcon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDestructive;

  /// When set, overrides the icon color regardless of hover/active state.
  final Color? activeColor;

  /// Compact variant for inline list rows where vertical space is tight.
  /// Drops outer padding and shrinks the inner hit-area to ~28 px tall.
  final bool dense;

  /// Full extent a single action occupies, outer padding included. Callers
  /// reserve this so a revealed action never changes the row's height.
  static double extentFor({required bool dense}) => dense ? 28 : 44;

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

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    if (widget.activeColor != null) {
      iconColor = widget.activeColor!;
    } else if (widget.isDestructive && _isHovered) {
      iconColor = widget.isDark ? WpColorsDark.error : WpColorsLight.error;
    } else if (_isHovered) {
      iconColor = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      iconColor = widget.isDark
          ? WpColorsDark.textMuted
          : WpColorsLight.textMuted;
    }

    return Semantics(
      label: widget.tooltip,
      button: true,
      child: Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
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
                    color: _isHovered
                        ? (widget.isDark
                              ? WpColorsDark.active
                              : WpColorsLight.active)
                        : (widget.isDark
                              ? WpColorsDark.hoverTransparent
                              : WpColorsLight.hoverTransparent),
                    borderRadius: WpRadius.borderSm,
                  ),
                  child: widget.faIcon != null
                      ? FaIcon(widget.faIcon!, size: 16, color: iconColor)
                      : Icon(widget.icon!, size: 16, color: iconColor),
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

  @override
  Widget build(BuildContext context) {
    final show = widget.visible || _hasFocusWithin;
    return SizedBox(
      height: WpRowAction.extentFor(dense: widget.dense),
      child: Focus(
        // Not a tab stop of its own — it only listens for focus landing on
        // one of the actions below it.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (_hasFocusWithin == hasFocus) return;
          setState(() => _hasFocusWithin = hasFocus);
        },
        child: show
            ? Row(mainAxisSize: MainAxisSize.min, children: widget.children)
            : const SizedBox.shrink(),
      ),
    );
  }
}
