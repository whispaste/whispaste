/// „Einführung erneut ansehen" — reopens the five-step onboarding flow from
/// Settings.
///
/// The introduction is the only place in the app that explains the whole
/// setup in order, and until now it was reachable exactly once, on the very
/// first launch. Anyone who clicked through it while distracted, or who wants
/// to check their own settings against what the flow now covers, had no way
/// back in. This is that way back in.
///
/// Deliberately not a settings *value*: tapping it opens a surface and
/// nothing is persisted, neither by opening it nor by paging through it. The
/// flow it opens runs in review mode — see [OnboardingOverlay.manualReview] —
/// which is prefilled from live settings, always starts at step 1, carries a
/// visible exit, and cannot write `onboardingCompleted`.
///
/// Shown only to users who have finished the first-run setup; the section is
/// filtered out of [SettingsPage] entirely otherwise (an unfinished first run
/// has the flow on screen already).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/feature_spotlight/feature_spotlight.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/onboarding/onboarding_revision.dart'
    show currentOnboardingPlatform;
import '../../../core/onboarding/onboarding_surface.dart';
import '../../../widgets/feature_spotlight_notice.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

class OnboardingReviewSection extends ConsumerWidget {
  const OnboardingReviewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // Every registered feature spotlight for this platform, seen or not —
    // unlike the automatic once-per-update showing, this manual re-view (see
    // [showFeatureSpotlightPreview]) exists precisely so someone who already
    // dismissed it can pull it back up, so filtering by seen state would
    // defeat the point.
    final platform = currentOnboardingPlatform();
    final spotlightEntries = ref
        .watch(featureSpotlightRegistryProvider)
        .where((entry) => entry.appliesTo(platform))
        .toList();
    return WpSection(
      title: l10n.onboardingReviewEntry,
      subtitle: l10n.onboardingReviewSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.compass,
            label: l10n.onboardingReviewLabel,
            trailing: WpButton(
              label: l10n.onboardingReviewAction,
              variant: WpButtonVariant.secondary,
              onPressed: () =>
                  ref.read(onboardingManuallyOpenProvider.notifier).open(),
            ),
          ),
          if (spotlightEntries.isNotEmpty)
            SettingRow(
              icon: LucideIcons.sparkles,
              label: l10n.featureSpotlightReviewLabel,
              trailing: WpButton(
                label: l10n.featureSpotlightReviewAction,
                variant: WpButtonVariant.secondary,
                onPressed: () =>
                    showFeatureSpotlightPreview(context, spotlightEntries),
              ),
            ),
        ],
      ),
    );
  }
}
