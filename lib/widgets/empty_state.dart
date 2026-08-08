import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';

/// Empty state — centered visual with icon, title, hint, and optional CTA.
///
/// Premium: accent-tinted icon circle (a single quiet signal point, glow-
/// free), glass border hint, refined spacing, confident title size.
///
/// When to pass an action — one rule, the same on every page: **an empty
/// state offers the area's main action whenever the area has one; that the
/// action is also reachable elsewhere (a toolbar button, say) is no reason
/// to leave it out, because an empty area is where the user looks for it
/// most urgently.** Use the same wording in both places. Areas without a
/// main action of their own get none: the history fills from a recording
/// run (its hint says so instead), and a trash only holds what was already
/// discarded. Error states offer "try again". A search-found-nothing state
/// offers "clear search" where the page owns its search field (history,
/// notes); the shared [WpSearchableListPage] does not yet, which is a gap,
/// not a second rule.
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
                WpButton(
                  label: actionLabel!,
                  variant: WpButtonVariant.primary,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
