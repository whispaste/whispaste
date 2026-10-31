import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart' show appVersion;
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../core/overview/overview_logic.dart' show OverviewBlock;
import '../../core/theme/tokens.dart';
import '../../services/review_prompt_service.dart';
import '../../widgets/page_shell.dart';
import 'overview_community.dart';
import 'overview_figures.dart';
import 'overview_header.dart';
import 'overview_hint_place.dart';
import 'overview_last_dictation.dart';
import 'overview_storage.dart';
import 'overview_providers.dart';
import 'overview_tip_card.dart' show overviewTipEligible;
import 'overview_recent.dart';

/// The "Übersicht" start page, top to bottom: a compact head, a status line
/// only when something is missing, the hint place ([OverviewHintPlace]: the
/// first steps alone, or "new in this version" before one discovery tip), the
/// key figures and the newest recordings, and last the "Mitmachen" links
/// ([OverviewCommunity]), in the shared page shell (full width, one scroll
/// area). Below
/// [WpLayout.breakpointOverviewTwoColumn] it is one column with the figures as
/// a strip above the recordings; from there on the figures move into a side
/// column so the rows of the main column keep their actions near their text.
class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: the visit changes stored state, which must not
    // happen while the tree is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordVisit();
    });
  }

  void _recordVisit() {
    final notifier = ref.read(overviewPrefsProvider.notifier);
    unawaited(notifier.markOpened(appVersion));
    // Whether a rating ask is due survives a restart only in its stored
    // times; asking the service again lets the hint place show it.
    unawaited(ref.read(reviewPromptProvider.notifier).checkAndMaybePrompt());
    final onboarding =
        ref.read(settingsProvider).value?.onboarding ??
        OnboardingSettings.defaults;
    if (!overviewTipEligible(onboarding)) return;
    unawaited(
      notifier.chooseTipForVisit(
        now: clock.now(),
        used: ref.read(overviewTipUsageProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(
      overviewPrefsProvider.select((p) => p.hiddenBlocks),
    );
    final showFigures = !hidden.contains(OverviewBlock.figures);
    final showRecent = !hidden.contains(OverviewBlock.recent);
    final showDictation = !hidden.contains(OverviewBlock.dictation);
    final showStorage = !hidden.contains(OverviewBlock.storage);
    final showCommunity = !hidden.contains(OverviewBlock.community);
    return WpPageShell(
      child: LayoutBuilder(
        key: const ValueKey('overview-page'),
        builder: (context, constraints) {
          const head = [
            OverviewGreeting(),
            SizedBox(height: WpSpacing.md),
            OverviewStatusLine(),
          ];
          // A block switched off in "Übersicht anpassen" takes its gap
          // with it; without the figures the main column takes the width.
          if (constraints.maxWidth >= WpLayout.breakpointOverviewTwoColumn) {
            // "Mitmachen" sits under the main column, never in the side column.
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OverviewHintPlace(),
                if (showRecent) const OverviewRecent(),
                if (showCommunity && showRecent)
                  const SizedBox(height: WpSpacing.xl),
                if (showCommunity) const OverviewCommunity(),
              ],
            );
            // The side column holds the figures and the two status blocks,
            // each one switched off in "Übersicht anpassen" leaves no gap.
            final side = [
              if (showFigures) const OverviewFigures(stacked: true),
              if (showDictation) const OverviewLastDictation(),
              if (showStorage) const OverviewStorage(),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...head,
                const SizedBox(height: WpSpacing.xl),
                if (side.isEmpty)
                  main
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: WpLayout.overviewColumnGap),
                      SizedBox(
                        width: WpLayout.overviewSideColumn,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, block) in side.indexed) ...[
                              if (i > 0) const SizedBox(height: WpSpacing.xl),
                              block,
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...head,
              const SizedBox(height: WpSpacing.xl),
              const OverviewHintPlace(),
              if (showFigures) const OverviewFigures(),
              if (showFigures && showRecent)
                const SizedBox(height: WpSpacing.xxl),
              if (showRecent) const OverviewRecent(),
              if ((showFigures || showRecent) && showDictation)
                const SizedBox(height: WpSpacing.xl),
              if (showDictation) const OverviewLastDictation(),
              if ((showFigures || showRecent || showDictation) && showStorage)
                const SizedBox(height: WpSpacing.xl),
              if (showStorage) const OverviewStorage(),
              if (showCommunity &&
                  (showFigures || showRecent || showDictation || showStorage))
                const SizedBox(height: WpSpacing.xl),
              if (showCommunity) const OverviewCommunity(),
            ],
          );
        },
      ),
    );
  }
}
