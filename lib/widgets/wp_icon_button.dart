// ---------------------------------------------------------------------------
// WpIconButton — the 44 px icon-only control (ticket spec §4).
//
// Sits beside a 44 px search field, so it shares that height instead of the
// 48 px text button. Every icon control of a collection toolbar (filter,
// select, sort, overflow, import, new) is this variant, never the ghost. Outlined like the field: `cardFillElevated` fill,
// `borderDefault` edge, 8 px corners (`WpRadiusTokens.sm`). Hover washes the
// fill; disabled swaps to muted content with no edge.
//
// [WpIconButton.ghost] is the quiet one for a secondary action inside a
// card (closing a hint): no fill and no edge at rest, a 20 px glyph in
// `textMuted`, a 40 px square that washes only under hover; the tap area
// stays the full touch target. `compact: true` is its one density for a
// dense editor toolbar (markdown toolbar, note and snippet editor headers):
// 32 px visual and hit square, desktop and mouse-first, 18 px glyph.
//
// Every icon button needs a [tooltip]: it doubles as the accessible name, so
// an icon alone never reaches a screen reader unlabelled.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

class WpIconButton extends StatefulWidget {
  const WpIconButton({
    super.key,
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    this.loading = false,
    this.color,
    this.testId,
    this.semanticsLabel,
    this.focusNode,
    this.selected,
  }) : assert(
         (icon == null) != (faIcon == null),
         'Provide exactly one of icon or faIcon',
       ),
       ghost = false,
       compact = false;

  const WpIconButton.ghost({
    super.key,
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.testId,
    this.semanticsLabel,
    this.focusNode,
    this.selected,
    this.compact = false,
  }) : assert(
         (icon == null) != (faIcon == null),
         'Provide exactly one of icon or faIcon',
       ),
       ghost = true,
       danger = false,
       loading = false;

  /// No fill and no edge at rest, see the library comment.
  final bool ghost;

  /// Lucide glyph. Exactly one of [icon] and [faIcon] is set.
  final IconData? icon;

  /// Font Awesome glyph, for the few states only that set draws (the solid
  /// pinned star, the quick-note bolt). Painted at [WpIconSize.sm] so its
  /// optical size matches a Lucide glyph at [WpIconSize.md].
  final FaIconData? faIcon;

  /// Shown on hover and read as the accessible name.
  final String tooltip;

  /// `null` disables the control.
  final VoidCallback? onPressed;

  /// Paints the glyph in the error colour, for a control that ends something
  /// live (a running recording), not one that destroys data.
  final bool danger;

  /// Replaces the glyph with a spinner and blocks presses while work is in
  /// flight.
  final bool loading;

  /// Glyph colour of an enabled button, for a control whose state the colour
  /// carries (the pinned star, the accent quick-note key). Null keeps the
  /// default text colour, or the error colour when [danger] is set.
  final Color? color;

  /// Stable id, exposed as the accessibility identifier (`<screen>-<element>`).
  final String? testId;

  /// What a screen reader says instead of [tooltip], when the short tooltip
  /// needs its row to make sense ("Remove" → "Remove “teh → the” from log").
  final String? semanticsLabel;

  /// Focus of the control, for a caller that reacts to it (a row that reveals
  /// its hover-only delete while the button holds keyboard focus). Null keeps
  /// a node owned by the button.
  final FocusNode? focusNode;

  /// Sticky on/off state of a toggle (the find bar of the markdown toolbar, a
  /// collection toolbar's select or group-by-date button): `true` paints the
  /// glyph in the accent on a washed square and is announced as toggled. Null
  /// for a plain action.
  final bool? selected;

  /// Editor-toolbar density of the ghost (#1498 F-header-actions): a 32 px
  /// square that is also the whole hit target, no 48 px touch padding, so a
  /// row of eleven formatting actions fits beside the tags of a note. The
  /// editor surfaces are mouse-first desktop UI; every other ghost keeps the
  /// touch target.
  final bool compact;

  /// Visible and hit square of a [compact] ghost.
  static const double compactExtent = 32;

  /// Visible square. The tap area is [WpLayout.minTouchTarget] square, see
  /// [WpTouchTarget].
  static const double extent = WpLayout.controlHeight;

  /// Visible square of [WpIconButton.ghost].
  static const double ghostExtent = 40;

  @override
  State<WpIconButton> createState() => _WpIconButtonState();
}

class _WpIconButtonState extends State<WpIconButton> {
  FocusNode? _ownFocusNode;
  bool _hovered = false;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'WpIconButton'));

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final radius = BorderRadius.circular(WpRadiusTokens.sm);

    final ghost = widget.ghost;
    final selected = widget.selected ?? false;
    final content = !enabled
        // A ghost has no edge to drop, so a disabled one fades its glyph
        // instead: next to an enabled neighbour (undo beside bold) it must
        // read as off, not as the same muted grey.
        ? (ghost
              ? WpColors.textMuted.withValues(alpha: 0.4)
              : WpColors.textMuted)
        : selected
        ? WpColors.accent
        : widget.color ??
              (widget.danger
                  ? WpColors.error
                  : ghost
                  ? WpColors.textMuted
                  : WpColors.textPrimary);
    final fill = (_hovered || selected) && enabled
        ? WpColors.hover
        : ghost
        ? Colors.transparent
        : enabled
        ? WpColors.cardFillElevated
        : WpColors.surfaceVariant;
    final edge = ghost
        ? null
        : Border.all(
            color: enabled ? WpColors.borderDefault : WpColors.borderSubtle,
          );

    final button = SizedBox.square(
      dimension: widget.compact
          ? WpIconButton.compactExtent
          : ghost
          ? WpIconButton.ghostExtent
          : WpIconButton.extent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          border: edge,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            focusNode: _focusNode,
            borderRadius: radius,
            onTap: enabled ? widget.onPressed : null,
            onHover: (h) => setState(() => _hovered = h),
            child: Center(
              child: widget.loading
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: content,
                      ),
                    )
                  : widget.faIcon != null
                  ? FaIcon(widget.faIcon!, size: WpIconSize.sm, color: content)
                  : Icon(
                      widget.icon,
                      size: widget.compact ? WpIconSize.smMd : WpIconSize.md,
                      color: content,
                    ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      toggled: widget.selected,
      label: widget.semanticsLabel ?? widget.tooltip,
      identifier: widget.testId,
      // The label above already names the button; the tooltip stays out of
      // the semantics tree so it is not announced a second time.
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        child: widget.compact
            ? WpFocusRing(
                focusNode: _focusNode,
                radius: WpRadiusTokens.sm,
                child: button,
              )
            : WpTouchTarget(
                onTap: enabled ? widget.onPressed : null,
                child: WpFocusRing(
                  focusNode: _focusNode,
                  radius: WpRadiusTokens.sm,
                  child: button,
                ),
              ),
      ),
    );
  }
}
