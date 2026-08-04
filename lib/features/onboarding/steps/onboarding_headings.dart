/// Shared heading vocabulary for onboarding pages 2–5.
///
/// The redesign's central structural fix: before it, page 5 stacked two
/// headline-sized bold titles while page 3 carried three same-sized block
/// titles and no page title at all — so no page had a visible hierarchy and
/// every page looked equally "full". There are now exactly two levels:
/// [OnboardingPageHeading] (one per page) and [OnboardingSectionLabel] (for
/// the blocks inside a page), separated by a clear size step (22 vs 14).
///
/// Both are start-aligned on [kSettingRowInset] — the horizontal padding
/// [SettingRow] applies to itself — so headings and the frameless settings
/// rows beneath them share one reading edge. `EdgeInsetsDirectional` keeps
/// that edge correct under RTL.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;

/// One per page: the title the page is about, plus an optional explanatory
/// line. Mirrors the Conductor reference's start-aligned "Set up Conductor"
/// lockup (`.scratch/onboarding-redesign/reference-conductor/
/// SCR-20260804-kayx.png`).
class OnboardingPageHeading extends StatelessWidget {
  const OnboardingPageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleMaxWidth = 560,
  });

  final String title;
  final String? subtitle;

  /// Bounded measure for the explanatory line so it keeps a readable line
  /// length instead of running the full (deliberately wide) page frame.
  final double subtitleMaxWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.headline,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: WpSpacing.xs),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: subtitleMaxWidth),
              child: Text(
                subtitle!,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: WpTypography.subheading,
                  color: textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A block inside a page. Deliberately a long way below
/// [OnboardingPageHeading] in weight so a page with several blocks still
/// reads as one page.
class OnboardingSectionLabel extends StatelessWidget {
  const OnboardingSectionLabel({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.subheading,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: textMuted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
