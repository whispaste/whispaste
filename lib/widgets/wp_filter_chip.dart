import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// The app's single selectable filter chip — one pill per filter in a list
/// area's filter row (History, Notes).
///
/// Anatomy: a compact 12×6 pill on a `borderFull` radius, centred inside a
/// [WpLayout.minTouchTarget]-tall tap surface, with the focus ring hugging the
/// pill via [WpFocusRing]'s external-node mode. Three states, all from theme
/// tokens: resting (`surfaceVariant` / `textSecondary`), hover (`hover` /
/// `textPrimary`) and selected (`accentSubtle` fill, `accentBorder30` outline,
/// `accent` label at w600). Call sites pass state, never colors.
///
/// [count] renders the optional hit-count badge behind the label — History
/// feeds it from `searchCountsProvider`, Notes leaves it null.
///
/// Not to be confused with the neighbouring chip families: `WpTriggerChip`
/// shows a value and the status-bar chips show a state; neither is selectable.
/// This one is the only chip the user picks.
class WpFilterChip extends StatefulWidget {
  const WpFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.isDark,
    this.icon,
    this.count,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? icon;

  /// Number of search hits for this filter. Shown as a badge when non-null.
  final int? count;

  @override
  State<WpFilterChip> createState() => _WpFilterChipState();
}

class _WpFilterChipState extends State<WpFilterChip> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpFilterChip');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    // The chip's three accent steps are the 6/12/30 % ladder the count badge
    // below already refers to, and they now actually are those rungs
    // (ticket 03, point 6). Two of them used to sit off it:
    //
    //   * Active fill was `accentSubtle` — the one accent token that never
    //     joined the ladder, and the only one that is *asymmetric* between
    //     themes (16.5 % dark vs 11 % light). A selected filter therefore
    //     read half again as strong on dark as on light, for no reason
    //     anybody had recorded. `accentActiveFill` is 12 % in both.
    //   * Hover was the neutral `hover` grey, so hovering an inactive chip
    //     hinted at nothing in particular. `accentRowHover` (6 %) makes the
    //     resting → hover → active progression one hue getting stronger,
    //     which is what a chip's hover is *for*: previewing the state the
    //     click leads to.
    if (widget.isActive) {
      bg = widget.isDark
          ? WpColorsDark.accentActiveFill
          : WpColorsLight.accentActiveFill;
      fg = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_isHovered) {
      bg = widget.isDark
          ? WpColorsDark.accentRowHover
          : WpColorsLight.accentRowHover;
      fg = widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    // Compact visual pill — the actual tap/focus surface around it is
    // stretched to WpLayout.minTouchTarget height by the InkWell below.
    final pill = AnimatedContainer(
      duration: WpMotion.durationFor(
        context,
        _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
      ),
      curve: WpMotion.defaultCurve,
      // Off-scale on purpose: 12x6 pill proportion shared with the detail
      // panel's edit pill; xs would visibly inflate the chip.
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: WpRadius.borderFull,
        border: widget.isActive
            ? Border.all(
                color: widget.isDark
                    ? WpColorsDark.accentBorder30
                    : WpColorsLight.accentBorder30,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: WpIconSize.sm, color: fg),
            const SizedBox(width: WpSpacing.xxs),
          ],
          // Flexible + ellipsis so a chip can be *narrower* than its label
          // wants. In a `Row` call site the chip is handed unbounded width and
          // this never engages; in a `Wrap` (the history filter bar since
          // ticket 03, the feedback form before it) a run is finite, and a
          // long label at a large text scale then overflowed this inner Row by
          // up to 30 px. Truncating a filter's name is the lesser evil against
          // painting outside the chip — and only happens when the label alone
          // is wider than the whole panel.
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: WpTypography.body,
                height: 1.15,
                fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (widget.count != null) ...[
            const SizedBox(width: 4),
            Text(
              '${widget.count}',
              style: TextStyle(
                // Foreground de-emphasis of the chip's own label color, not a
                // surface tint — the 6/12/30% ladder does not apply here.
                color: (!widget.isActive && widget.count! > 0)
                    ? (widget.isDark
                          ? WpColorsDark.accent
                          : WpColorsLight.accent)
                    : fg.withValues(alpha: 0.6),
                fontSize: WpTypography.caption,
                height: 1.15,
                fontWeight: (!widget.isActive && widget.count! > 0)
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );

    // House idiom (`section.dart`): MergeSemantics + a *label-less*
    // Semantics. A `label:` is prepended to the subtree's own text rather
    // than replacing it, so every filter chip announced as "Alle, Alle, 42".
    // One tap target in the subtree, so merging is the right shape here and
    // costs nothing: the tap action and the button role survive it.
    //
    // The trailing count keeps folding into the name ("Alle, 42"), as it
    // already did before this change. It is left as a bare number on
    // purpose: what the number counts is the caller's business, and this
    // widget is generic — inventing a label parameter for the one caller
    // that passes a count would be an abstraction ahead of a second need.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.isActive,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: InkWell(
            onTap: widget.onTap,
            focusNode: _focusNode,
            // WpFocusRing owns all focus visuals — suppress InkWell's own.
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: WpLayout.minTouchTarget,
              ),
              child: Center(
                // `widthFactor: 1.0`, or the chip claims the whole line it is
                // offered. A bare Center shrink-wraps only when the incoming
                // width is *unbounded*; given a finite maxWidth it expands to
                // it (RenderPositionedBox). Every call site was a Row — which
                // hands non-flexible children unbounded width — until the
                // feedback page put these chips in a Wrap, and a Wrap measures
                // its children against a finite width. Each chip then reported
                // the full form width around a compact pill, so no two of them
                // could ever share a run.
                //
                // Height deliberately keeps the expanding behaviour: that is
                // what stretches the tap surface to the ConstrainedBox's
                // minTouchTarget above.
                widthFactor: 1.0,
                // External-node mode: the ring hugs the compact pill while the
                // shared FocusNode lives on the taller InkWell surface.
                child: WpFocusRing(
                  focusNode: _focusNode,
                  radius: WpRadius.lg,
                  child: pill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
