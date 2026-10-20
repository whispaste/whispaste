/// Shared error notice: what went wrong, then what the user can do next.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'wp_banner.dart';

/// Error notice with a cause line and an optional next-step line.
///
/// The cause and the next step are separate texts, so each one can be read,
/// tested and translated on its own. Colours come from [WpColors] at build
/// time, so a theme switch repaints the notice.
class WpErrorNotice extends StatelessWidget {
  const WpErrorNotice({
    super.key,
    required this.cause,
    this.nextStep,
    this.action,
  });

  /// What went wrong, in one sentence.
  final String cause;

  /// What the user can do now. Omitted when no sensible action exists.
  final String? nextStep;

  /// Optional trailing control, such as a settings shortcut.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: WpColors.textPrimary,
      fontFamily: kWpUiFont,
      fontFamilyFallback: kWpFontFallback,
    );
    return WpBannerSurface(
      tone: WpBannerTone.error,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            wpBannerLook(WpBannerTone.error).icon,
            size: WpIconSize.md,
            color: WpColors.errorRed,
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cause,
                  key: const Key('error-notice-cause'),
                  style: bodyStyle,
                ),
                if (nextStep != null) ...[
                  const SizedBox(height: WpSpacing.xs),
                  Text(
                    nextStep!,
                    key: const Key('error-notice-next-step'),
                    style: bodyStyle?.copyWith(color: WpColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: WpSpacing.sm), action!],
        ],
      ),
    );
  }
}
