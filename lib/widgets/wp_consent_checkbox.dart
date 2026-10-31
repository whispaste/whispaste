import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_row_checkbox.dart';

/// A labelled, optional consent checkbox for a form. The whole row toggles the
/// value, so the label is part of the tap target. Defaults are the caller's
/// decision: a consent checkbox must start unchecked.
class WpConsentCheckbox extends StatefulWidget {
  const WpConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.explanation,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String explanation;

  @override
  State<WpConsentCheckbox> createState() => _WpConsentCheckboxState();
}

class _WpConsentCheckboxState extends State<WpConsentCheckbox> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final onChanged = widget.onChanged;
    final label = widget.label;
    final explanation = widget.explanation;
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: WpColors.textPrimary,
    );
    // The box sits centred in its touch-target slot; the label's first line
    // is centred on it, so box and label read as one line.
    final labelLine = MediaQuery.textScalerOf(
      context,
    ).scale((labelStyle?.fontSize ?? 14) * (labelStyle?.height ?? 1.4));
    final labelInset = math.max(0.0, (WpRowCheckbox.extent - labelLine) / 2);
    // The whole row is one tap target (label included), at least as tall as a
    // touch target. WpTouchTarget is not used because it only forwards taps
    // that the child does not take, so a tap on the label would do nothing.
    return Semantics(
      checked: value,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          // No hover, press or focus fill (maintainer 2026-10-30): a filled
          // block around a checkbox reads as a second card, and without it
          // the box lines up with the fields' edge. Keyboard focus draws a
          // ring just outside the row instead.
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_focused)
                Positioned.fill(
                  left: -WpSpacing.xxs,
                  right: -WpSpacing.xxs,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: WpRadius.borderSm,
                        border: Border.all(color: WpColors.accent, width: 2),
                      ),
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: WpLayout.minTouchTarget,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The box is WpRowCheckbox, so it matches every other
                    // selection checkbox in the app. The row above owns the tap
                    // and the semantics, so the box itself is excluded.
                    // The slot is laid out only as wide as the visible box and
                    // overflows to both sides (the row above owns the taps), so
                    // the box keeps the same inset as the text.
                    SizedBox(
                      width: WpRowCheckbox.boxSize,
                      height: WpRowCheckbox.extent,
                      child: OverflowBox(
                        minWidth: WpRowCheckbox.extent,
                        maxWidth: WpRowCheckbox.extent,
                        child: ExcludeSemantics(
                          child: WpRowCheckbox(
                            value: value,
                            onChanged: () => onChanged(!value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: labelInset,
                          bottom: WpSpacing.xs,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: labelStyle),
                            const SizedBox(height: WpSpacing.xxs),
                            Text(
                              explanation,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: WpColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
