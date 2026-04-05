import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Empty state — centered visual with icon, title, hint, and optional CTA.
///
/// Premium: subtle gradient background circle, refined spacing, clean typography.
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WpSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with subtle gradient
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: isDark
                    ? WpColorsDark.surfaceGradient
                    : WpColorsLight.surfaceGradient,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? WpColorsDark.borderSubtle
                      : WpColorsLight.borderSubtle,
                ),
              ),
              child: Icon(icon, size: WpIconSize.xl, color: cs.secondary),
            ),
            const SizedBox(height: WpSpacing.xl),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: WpSpacing.xs),
              SizedBox(
                width: 280,
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
    );
  }
}
