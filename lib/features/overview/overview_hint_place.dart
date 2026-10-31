import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/tokens.dart';
import '../first_steps/first_steps_card.dart';
import 'overview_ask_card.dart';
import 'overview_providers.dart';
import 'overview_tip_card.dart';
import 'overview_whats_new_card.dart';

/// Ü5: the hint place under the head. [overviewHintPlace] decides which
/// cards show and in which order; the cards sit 16 px apart and the place
/// takes no height when it is empty.
class OverviewHintPlace extends ConsumerWidget {
  const OverviewHintPlace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(overviewPrefsProvider);
    final onboarding = ref.watch(
      settingsProvider.select(
        (s) => s.value?.onboarding ?? OnboardingSettings.defaults,
      ),
    );
    final hints = overviewHintPlace(
      firstStepsVisible: ref.watch(firstStepsViewProvider).visible,
      whatsNewHasItems: ref.watch(overviewWhatsNewProvider).items.isNotEmpty,
      tipVisible: prefs.visibleTip != null && overviewTipEligible(onboarding),
      askVisible: ref.watch(overviewAskCardProvider) != null,
    );
    if (hints.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('overview-hint-place'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, hint) in hints.indexed) ...[
          if (i > 0) const SizedBox(height: WpSpacing.md),
          switch (hint) {
            OverviewHint.firstSteps => const FirstStepsCard(),
            OverviewHint.whatsNew => const OverviewWhatsNewCard(),
            OverviewHint.tip => const OverviewTipCard(),
            OverviewHint.ask => const OverviewAskCardView(),
          },
        ],
        // The gap to the next section belongs to the place, so an empty
        // place leaves none behind.
        const SizedBox(height: WpSpacing.xxl),
      ],
    );
  }
}
