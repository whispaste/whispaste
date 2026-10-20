import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_row_checkbox.dart';

/// A labelled, optional consent checkbox for a form. The whole row toggles the
/// value, so the label is part of the tap target. Defaults are the caller's
/// decision: a consent checkbox must start unchecked.
class WpConsentCheckbox extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The whole row is one tap target (label included), at least as tall as a
    // touch target. WpTouchTarget is not used because it only forwards taps
    // that the child does not take, so a tap on the label would do nothing.
    return Semantics(
      checked: value,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: WpLayout.minTouchTarget,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The box is WpRowCheckbox, so it matches every other
                // selection checkbox in the app. The row above owns the tap
                // and the semantics, so the box itself is excluded.
                ExcludeSemantics(
                  child: WpRowCheckbox(
                    value: value,
                    onChanged: () => onChanged(!value),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: WpSpacing.xs),
                      Text(
                        explanation,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: WpColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
