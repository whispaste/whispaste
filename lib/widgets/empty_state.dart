import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Empty state — centered visual with icon, title, hint, and optional CTA.
///
/// Premium: accent-tinted icon circle (a single quiet signal point, glow-
/// free), glass border hint, refined spacing, confident title size.
class WpEmptyState extends StatelessWidget {
  const WpEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Scrollable so a tight viewport (minimum window height plus a tall
    // header above, e.g. the snippet-trigger card with its warning hint)
    // degrades to scrolling instead of a RenderFlex overflow.
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(WpSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon circle — one quiet accent signal point, no glow
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isDark
                      ? WpColorsDark.accentChipFill
                      : WpColorsLight.accentChipFill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? WpColorsDark.accentBorder20
                        : WpColorsLight.accentBorder20,
                  ),
                ),
                child: Icon(
                  icon,
                  size: WpIconSize.xl,
                  color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                ),
              ),
              const SizedBox(height: WpSpacing.xl),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (hint != null) ...[
                const SizedBox(height: WpSpacing.xs),
                SizedBox(
                  width: 300,
                  child: Text(
                    hint!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: WpSpacing.lg),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
