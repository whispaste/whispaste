// ---------------------------------------------------------------------------
// WpIconButton — the 44 px icon-only control (WP-14 spec §4).
//
// Sits beside a 44 px search field, so it shares that height instead of the
// 48 px text button. Outlined like the field: `cardFillElevated` fill,
// `borderDefault` edge, 8 px corners (`WpRadiusTokens.sm`). Hover washes the
// fill; disabled swaps to muted content with no edge.
//
// Every icon button needs a [tooltip]: it doubles as the accessible name, so
// an icon alone never reaches a screen reader unlabelled.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

class WpIconButton extends StatefulWidget {
  const WpIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    this.loading = false,
    this.color,
  });

  final IconData icon;

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

  /// Visible square. The tap area is [WpLayout.minTouchTarget] square, see
  /// [WpTouchTarget].
  static const double extent = WpShellTokens.fieldHeight;

  @override
  State<WpIconButton> createState() => _WpIconButtonState();
}

class _WpIconButtonState extends State<WpIconButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpIconButton');
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final radius = BorderRadius.circular(WpRadiusTokens.sm);

    final content = !enabled
        ? WpColors.textMuted
        : widget.color ??
              (widget.danger ? WpColors.error : WpColors.textPrimary);
    final fill = !enabled
        ? WpColors.surfaceVariant
        : _hovered
        ? WpColors.hover
        : WpColors.cardFillElevated;
    final edge = enabled ? WpColors.borderDefault : WpColors.borderSubtle;

    final button = SizedBox.square(
      dimension: WpIconButton.extent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          border: Border.all(color: edge),
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
                  : Icon(widget.icon, size: WpIconSize.md, color: content),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: WpTouchTarget(
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
