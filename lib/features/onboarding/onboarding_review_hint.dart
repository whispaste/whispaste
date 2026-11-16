/// The one-time notice for users who finished an earlier onboarding (Onboarding
/// v6, V08, decision E1 a): "New: check the microphone test and pasting". It
/// sits on the start page as a dismissible banner and opens a review on the
/// microphone page. No full run is forced.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';
import 'onboarding_flow_migration.dart'
    show kOnboardingFlowVersion, onboardingReviewHintDue;
import 'onboarding_overlay.dart' show OnboardingStepId, openOnboardingReview;

/// Start-page banner for [onboardingReviewHintDue] users.
///
/// It is shown the first time the start page is displayed and then counts as
/// shown: the stored flow version moves to the current one, so the notice can
/// never come back, not even after a restart. It stays on screen for this
/// visit only, until it is dismissed, acted on or the user leaves the start
/// page. New installs never see it, because they stamp the flow version as
/// soon as their first setup starts.
class OnboardingReviewHintBanner extends ConsumerStatefulWidget {
  const OnboardingReviewHintBanner({super.key});

  @override
  ConsumerState<OnboardingReviewHintBanner> createState() =>
      _OnboardingReviewHintBannerState();
}

class _OnboardingReviewHintBannerState
    extends ConsumerState<OnboardingReviewHintBanner> {
  /// Latched when the banner is first displayed on the start page this visit.
  bool _shownThisVisit = false;

  /// The user dismissed or acted on the banner. It stays hidden for the rest
  /// of this visit.
  bool _dismissed = false;

  /// Writes the shown mark once the banner has been painted.
  void _markShown() {
    if (!mounted) return;
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(
              onboardingFlowVersion: kOnboardingFlowVersion,
            ),
          ),
        );
  }

  void _dismiss() => setState(() => _dismissed = true);

  void _open() {
    setState(() => _dismissed = true);
    openOnboardingReview(ref, at: OnboardingStepId.mic);
  }

  @override
  Widget build(BuildContext context) {
    // Leaving the start page ends this visit, so coming back shows nothing.
    ref.listen<String>(activePageProvider, (previous, next) {
      if (next != kDefaultStartPage && _shownThisVisit) {
        setState(() {
          _shownThisVisit = false;
          _dismissed = false;
        });
      }
    });
    final onStartPage = ref.watch(activePageProvider) == kDefaultStartPage;
    final onboarding = ref.watch(
      settingsProvider.select((s) => s.value?.onboarding),
    );
    final due =
        onboarding != null &&
        onboardingReviewHintDue(
          onboardingCompleted: onboarding.onboardingCompleted,
          flowVersion: onboarding.onboardingFlowVersion,
        );
    if (onStartPage && due && !_shownThisVisit) {
      // First display: latch the visit now, mark the notice shown after the
      // frame, so the mark cannot be lost by a rebuild before it is painted.
      _shownThisVisit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _markShown());
    }
    if (!onStartPage || !_shownThisVisit || _dismissed) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.lg,
        0,
        WpSpacing.lg,
        WpSpacing.md,
      ),
      child: WpBanner(
        key: const ValueKey('onboarding-review-hint'),
        tone: WpBannerTone.info,
        message: l10n.onboardingReviewHintMessage,
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WpTextLink(
              key: const ValueKey('onboarding-review-hint-open'),
              label: l10n.onboardingReviewHintAction,
              testID: 'onboarding-review-hint-open',
              onPressed: _open,
            ),
            WpIconButton(
              key: const ValueKey('onboarding-review-hint-dismiss'),
              icon: LucideIcons.x,
              tooltip: l10n.actionDismiss,
              testId: 'onboarding-review-hint-dismiss',
              onPressed: _dismiss,
            ),
          ],
        ),
      ),
    );
  }
}
