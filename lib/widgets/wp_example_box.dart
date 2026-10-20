import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';

/// A worked example shown beside a setting or in onboarding: a sunken panel
/// with an overline ("Beispiel") and a Bernstein marker on its leading edge.
///
/// The marker is the amber `highlight` role, drawn as a thin bar. Amber marks
/// something the user should look at; it is never a fill behind the content.
class WpExampleBox extends StatelessWidget {
  const WpExampleBox({super.key, required this.overline, required this.child});

  /// Short label above the example, e.g. the localized word for "Example".
  final String overline;

  /// The example itself: usually a text or a small preview.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WpColors.surfaceMutedFill,
        borderRadius: BorderRadius.circular(WpRadiusTokens.control),
        border: Border.all(color: WpColors.borderSubtle),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: WpColors.highlight,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(WpRadiusTokens.control),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(WpSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      overline.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: WpColors.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: WpSpacing.xxs),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
