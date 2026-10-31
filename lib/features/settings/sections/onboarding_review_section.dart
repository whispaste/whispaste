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
/// Shown only to users who have finished the first-run setup; otherwise the
/// widget renders nothing (an unfinished first run has the flow on screen
/// already).
///
/// Lives on the Help page (Hilfe), not in Settings: the introduction is help,
/// and the settings search opens Help for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/config/settings_provider.dart';
import '../../onboarding/onboarding_overlay.dart' show openOnboardingReview;
import '../../../widgets/wp_button.dart';
import '../widgets/wp_settings_group.dart';

class OnboardingReviewSection extends ConsumerWidget {
  const OnboardingReviewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final onboardingCompleted = ref.watch(
      settingsProvider.select(
        (s) => s.value?.onboarding.onboardingCompleted ?? false,
      ),
    );
    if (!onboardingCompleted) return const SizedBox.shrink();
    return WpSettingsGroup(
      heading: l10n.onboardingReviewEntry,
      children: [
        WpSettingsRow(
          rowId: 'advanced-onboarding-again',
          title: l10n.onboardingReviewLabel,
          trailing: WpButton(
            label: l10n.onboardingReviewAction,
            variant: WpButtonVariant.secondary,
            onPressed: () => openOnboardingReview(ref),
          ),
        ),
      ],
    );
  }
}
