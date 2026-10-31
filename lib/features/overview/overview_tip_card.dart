import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../core/first_steps/first_steps.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';
import 'overview_navigation.dart';
import 'overview_providers.dart';

/// Whether the discovery tip may show now: the first steps are done or closed.
bool overviewTipEligible(OnboardingSettings onboarding) => overviewTipsEligible(
  firstStepsArmed: onboarding.firstStepsArmed,
  firstStepsDismissed: onboarding.firstStepsDismissed,
  firstStepsAllDone: firstStepsAllDone(
    parseFirstStepsDone(onboarding.firstStepsDone),
  ),
);

extension OverviewTipText on OverviewTip {
  /// Title and body of the tip, kept in one switch so a new tip cannot get
  /// one without the other.
  ({String title, String body}) text(L10n l10n) => switch (this) {
    OverviewTip.smartMode => (
      title: l10n.navSmartMode,
      body: l10n.overviewTipSmartBody,
    ),
    OverviewTip.vocabulary => (
      title: l10n.navReplacements,
      body: l10n.overviewTipVocabularyBody,
    ),
    OverviewTip.snippets => (
      title: l10n.navSnippets,
      body: l10n.overviewTipSnippetsBody,
    ),
    OverviewTip.notes => (
      title: l10n.navNotes,
      body: l10n.overviewTipNotesBody,
    ),
    OverviewTip.overlayLook => (
      title: l10n.overviewTipOverlayTitle,
      body: l10n.overviewTipOverlayBody,
    ),
    OverviewTip.recordingMode => (
      title: l10n.overviewTipRecordingModeTitle,
      body: l10n.overviewTipRecordingModeBody,
    ),
  };
}

/// W15: one discovery tip for the visit, with its action, a per-tip close and
/// "no more tips". Shown after the first steps are done or closed.
class OverviewTipCard extends ConsumerWidget {
  const OverviewTipCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tip = ref.watch(overviewPrefsProvider.select((p) => p.visibleTip));
    final onboarding = ref.watch(
      settingsProvider.select(
        (s) => s.value?.onboarding ?? OnboardingSettings.defaults,
      ),
    );
    if (tip == null || !overviewTipEligible(onboarding)) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context);
    final notifier = ref.read(overviewPrefsProvider.notifier);
    return WpCard(
      key: ValueKey('overview-tip-${tip.id}'),
      title: l10n.overviewTipHeading,
      trailing: WpIconButton.ghost(
        testId: 'overview-tip-hide',
        icon: LucideIcons.x,
        tooltip: l10n.overviewTipHide,
        onPressed: () => notifier.dismissTip(tip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip.text(l10n).title, style: WpTextStyles.rowTitle),
          const SizedBox(height: WpSpacing.xxs),
          Text(tip.text(l10n).body, style: WpTextStyles.rowNote),
          const SizedBox(height: WpSpacing.xs),
          Wrap(
            spacing: WpSpacing.xl,
            runSpacing: WpSpacing.xs,
            children: [
              WpTextLink(
                testID: 'overview-tip-try',
                label: l10n.overviewTipTry,
                icon: LucideIcons.arrowRight,
                iconAfter: true,
                onPressed: () => overviewOpenTarget(ref, tip.target),
              ),
              WpTextLink(
                testID: 'overview-tip-off',
                label: l10n.overviewTipsOff,
                onPressed: () => notifier.turnTipsOff(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
