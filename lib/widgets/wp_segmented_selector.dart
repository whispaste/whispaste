/// Segmented pill selector with an animated active indicator.
///
/// Pure presentational component: items carry their own active state and tap
/// handlers. [WpSegmentedChoice] is the single-choice wrapper that the
/// settings-style pages use (UIA-CMP-06, instead of a raw `SegmentedButton`).
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';

/// One selectable segment of a [WpSegmentedSelector].
class WpSegmentItem {
  const WpSegmentItem({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  /// Optional decorative icon rendered left of the label.  Null = text-only.
  final Widget? icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  /// A disabled segment is shown dimmed and cannot be tapped.
  final bool enabled;
}

/// One value of a [WpSegmentedChoice].
class WpSegmentOption<T> {
  const WpSegmentOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// Single choice among [options], drawn as a [WpSegmentedSelector] with the
/// app's surface, border and secondary text roles.
class WpSegmentedChoice<T> extends StatelessWidget {
  const WpSegmentedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 48,
  });

  final List<WpSegmentOption<T>> options;

  /// Height of the frame; 32 is the compact size for a quiet period filter.
  final double height;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return WpSegmentedSelector(
      borderColor: WpColors.borderDefault,
      surfaceColor: WpColors.surfaceVariant,
      textSecondary: WpColors.textSecondary,
      height: height,
      items: [
        for (final option in options)
          WpSegmentItem(
            label: option.label,
            isActive: option.value == selected,
            enabled: option.enabled,
            onTap: () => onChanged(option.value),
          ),
      ],
    );
  }
}

/// Horizontal segmented control (WP-14 §4): one frame with an 8 px radius, an
/// active segment on a cyan-soft fill with petrol semibold text, and equal
/// tap targets. The indicator slides behind the active segment.
class WpSegmentedSelector extends StatelessWidget {
  const WpSegmentedSelector({
    super.key,
    required this.items,
    required this.borderColor,
    required this.surfaceColor,
    required this.textSecondary,
    this.height = 48,
  });

  final List<WpSegmentItem> items;
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
            borderRadius: BorderRadius.circular(WpRadiusTokens.sm),
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
                    color: WpColors.accentSubtle,
                    borderRadius: BorderRadius.circular(WpRadiusTokens.xs),
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
        enabled: widget.item.enabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.item.enabled ? widget.item.onTap : null,
            borderRadius: BorderRadius.circular(WpRadiusTokens.xs),
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
                                  ? WpColors.accent
                                  : widget.textSecondary,
                              size: WpIconSize.smMd,
                            ),
                            child: DefaultTextStyle(
                              style: TextStyle(
                                color: isActive
                                    ? WpColors.accent
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
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isActive
                                ? WpColors.accent
                                : widget.item.enabled
                                ? widget.textSecondary
                                : widget.textSecondary.withValues(alpha: 0.5),
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
