/// Segmented pill selector with an animated active indicator.
///
/// Extracted from the onboarding Welcome step, where it used to drive the
/// theme choice. **Currently unused**: the theme choice it was extracted for
/// became a picture-tile selector on its own onboarding page (see
/// `features/onboarding/steps/appearance_step.dart`), and no other caller
/// picked this up in the meantime. Kept as-is pending a decision — delete it
/// if nothing claims it. Pure presentational component: items carry their own
/// active state and tap handlers.
library;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// One selectable segment of a [WpSegmentedSelector].
class WpSegmentItem {
  const WpSegmentItem({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.icon,
  });

  /// Optional decorative icon rendered left of the label.  Null = text-only.
  final Widget? icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
}

/// Horizontal pill selector: an animated gradient indicator slides behind the
/// active segment; every segment is an equally sized tap target.
class WpSegmentedSelector extends StatelessWidget {
  const WpSegmentedSelector({
    super.key,
    required this.items,
    required this.activeGradient,
    required this.borderColor,
    required this.surfaceColor,
    required this.textSecondary,
    this.height = 48,
  });

  final List<WpSegmentItem> items;
  final LinearGradient activeGradient;
  final Color borderColor;
  final Color surfaceColor;
  final Color textSecondary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final activeIndex = items.indexWhere((item) => item.isActive);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final itemWidth = totalWidth / items.length;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: WpRadius.borderFull,
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: WpMotion.durationFor(context, WpMotion.normal),
                curve: Curves.easeOutCubic,
                left: activeIndex >= 0 ? activeIndex * itemWidth + 4 : 4,
                top: 4,
                bottom: 4,
                width: itemWidth - 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: activeGradient,
                    borderRadius: WpRadius.borderFull,
                    boxShadow: WpShadows.subtle,
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _SegmentButton(
                        item: item,
                        textSecondary: textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({required this.item, required this.textSecondary});

  final WpSegmentItem item;
  final Color textSecondary;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.item.isActive;

    // House idiom (`section.dart`): MergeSemantics + a *label-less*
    // Semantics. A `label:` is prepended to the subtree's own text rather
    // than replacing it, so the rendered `Text(widget.item.label)` below made
    // every segment announce as "Verlauf, Verlauf". `selected:` stays on the
    // wrapper — it is the segment's whole state and the pill is its only
    // visual carrier.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isActive,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.item.onTap,
            borderRadius: WpRadius.borderFull,
            focusColor: widget.textSecondary.withValues(alpha: 0.15),
            onHover: (hovering) => setState(() => _hovered = hovering),
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              color: !isActive && _hovered
                  ? widget.textSecondary.withValues(alpha: 0.08)
                  : Colors.transparent,
              alignment: Alignment.center,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.item.icon != null) ...[
                          IconTheme(
                            data: IconThemeData(
                              color: isActive
                                  ? Colors.white
                                  : widget.textSecondary,
                              size: 18,
                            ),
                            child: DefaultTextStyle(
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : widget.textSecondary,
                              ),
                              child: widget.item.icon!,
                            ),
                          ),
                          const SizedBox(width: WpSpacing.xs),
                        ],
                        AnimatedDefaultTextStyle(
                          duration: WpMotion.durationFor(
                            context,
                            WpMotion.fast,
                          ),
                          style: TextStyle(
                            fontSize: WpTypography.subheading,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? Colors.white
                                : widget.textSecondary,
                          ),
                          child: Text(widget.item.label),
                        ),
                      ],
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
