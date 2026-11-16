import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// From this system text scale on, a [WpBanner] moves its action below the
/// message (same idea as the settings navigation's collapse scale).
const _kLargeTextScale = 1.4;

/// Below this content width (at text scale 1, grown with the system text
/// scale) a banner's action goes under the message; beside it the message
/// would be squeezed to a few letters per line or the action would overflow.
/// Same rule as [WpErrorNotice] (#321, #835).
const double kWpBannerActionBesideMinWidth = 480;

/// Severity of a [WpBanner]. There is no success tone: green is reserved for
/// the earned moment after a user action, which is a toast, not a banner
/// (`test/core/design/earned_green_test.dart`).
enum WpBannerTone { info, warning, error }

/// A full-width notice inside a page or card: one sentence, a tone icon and an
/// optional action (usually a [WpTextLink] or a secondary button).
///
/// Each tone is a tinted fill with its own rim, drawn from the status roles.
/// Banners state something that holds for the whole page, so they do not
/// animate in and do not dismiss themselves.
/// Icon, icon colour, fill and rim of one [WpBannerTone].
typedef WpBannerLook = ({
  IconData icon,
  Color iconColor,
  Color fill,
  Color rim,
});

WpBannerLook wpBannerLook(WpBannerTone tone) => switch (tone) {
  WpBannerTone.info => (
    icon: LucideIcons.info,
    iconColor: WpColors.accent,
    fill: WpColors.accentSubtle,
    rim: WpColors.accentBorder20,
  ),
  // Amber marks a notice: the soft amber fill with the amber text role keeps
  // the text at 4.5:1 (wcag_contrast_test). Error
  // stays red, so the two tones never read alike.
  WpBannerTone.warning => (
    icon: LucideIcons.triangleAlert,
    iconColor: WpColors.highlightText,
    fill: WpColors.highlightSoft,
    rim: WpColors.highlight.withValues(alpha: 0.5),
  ),
  WpBannerTone.error => (
    icon: LucideIcons.circleAlert,
    iconColor: WpColors.errorRed,
    fill: WpColors.errorActiveFill,
    rim: WpColors.errorBorder30,
  ),
};

/// The tinted, rimmed frame shared by [WpBanner] and [WpErrorNotice], so a
/// change to a tone's fill, rim or radius lands in one place.
class WpBannerSurface extends StatelessWidget {
  const WpBannerSurface({super.key, required this.tone, required this.child});

  final WpBannerTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = wpBannerLook(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: look.fill,
        borderRadius: BorderRadius.circular(WpRadiusTokens.control),
        border: Border.all(color: look.rim),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        child: child,
      ),
    );
  }
}

class WpBanner extends StatelessWidget {
  const WpBanner({
    super.key,
    required this.tone,
    required this.message,
    this.action,
  });

  final WpBannerTone tone;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final look = wpBannerLook(tone);
    final text = Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: WpColors.textPrimary,
        fontFamily: kWpUiFont,
        fontFamilyFallback: kWpFontFallback,
      ),
    );
    final icon = Icon(look.icon, size: WpIconSize.md, color: look.iconColor);
    // At a large system text size or in a narrow banner the action would
    // squeeze the message into a narrow column (or run out of the banner): it
    // moves below the message and stays fully usable (#599, #835).
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(1) >= _kLargeTextScale;
    final minBeside = scaler.scale(kWpBannerActionBesideMinWidth);
    final action = this.action;
    if (action == null) {
      return WpBannerSurface(
        tone: tone,
        child: Row(
          children: [
            icon,
            const SizedBox(width: WpSpacing.sm),
            Expanded(child: text),
          ],
        ),
      );
    }
    return WpBannerSurface(
      tone: tone,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (large || constraints.maxWidth < minBeside) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: WpSpacing.sm),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: WpSpacing.xs),
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: WpSpacing.sm),
              Expanded(child: text),
              const SizedBox(width: WpSpacing.sm),
              action,
            ],
          );
        },
      ),
    );
  }
}
