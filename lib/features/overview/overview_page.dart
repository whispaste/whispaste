import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart' show appVersion;
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../core/overview/overview_logic.dart'
    show OverviewBlock, overviewBlockShown;
import '../../core/theme/tokens.dart';
import '../../services/review_prompt_service.dart';
import '../../services/support_prompt_service.dart';
import '../../widgets/page_shell.dart';
import 'overview_community.dart';
import 'overview_figures.dart';
import 'overview_header.dart';
import 'overview_hint_place.dart';
import 'overview_last_dictation.dart';
import 'overview_movable_card.dart'
    show OverviewColumnDrop, OverviewMovableCard, overviewDragActiveProvider;
import 'overview_news.dart';
import 'overview_notes.dart';
import 'overview_storage.dart';
import 'overview_providers.dart';
import 'overview_system_card.dart';
import 'overview_tip_card.dart' show overviewTipEligible;
import 'overview_weather.dart';
import 'overview_recent.dart';

/// The "Übersicht" start page, top to bottom: a compact head, a status line
/// only when something is missing, the hint place ([OverviewHintPlace]: the
/// first steps alone, or "new in this version" before one discovery tip), the
/// key figures, the newest recordings, the notes edited last and, when switched
/// on, the news ([OverviewNews]), and last the "Mitmachen" links
/// ([OverviewCommunity]), in the shared page shell (full width, one scroll
/// area). Below
/// [WpLayout.breakpointOverviewTwoColumn] it is one column with the figures as
/// a strip above the recordings; from there on the figures move into a side
/// column so the rows of the main column keep their actions near their text.
/// The cards follow the order the user gave them by dragging or with the
/// arrow keys ([OverviewMovableCard], #1970), also across the two columns.
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
    // Whether a rating or support ask is due survives a restart only in its stored
    // times; asking the service again lets the hint place show it.
    unawaited(ref.read(reviewPromptProvider.notifier).checkAndMaybePrompt());
    unawaited(ref.read(supportPromptProvider.notifier).checkAndMaybePrompt());
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
    final layout = ref.watch(
      overviewPrefsProvider.select(
        (p) => (p.hiddenBlocks, p.shownBlocks, p.blockOrder, p.sideBlocks),
      ),
    );
    final (hidden, shown, order, sideSet) = layout;
    final dragging = ref.watch(overviewDragActiveProvider);
    // The shown blocks in the user's order (#1970).
    final visible = [
      for (final block in order)
        if (overviewBlockShown(block, hidden: hidden, shown: shown)) block,
    ];
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
          // with it; without side blocks the main column takes the width,
          // except while a card is dragged: then the empty side column is a
          // drop place.
          if (constraints.maxWidth >= WpLayout.breakpointOverviewTwoColumn) {
            final mainBlocks = [
              for (final b in visible)
                if (!sideSet.contains(b)) b,
            ];
            final sideBlocks = [
              for (final b in visible)
                if (sideSet.contains(b)) b,
            ];
            List<Widget> column(List<OverviewBlock> blocks, bool side) => [
              ..._column(blocks, visible: visible, side: side),
              if (dragging) ...[
                if (blocks.isNotEmpty) const SizedBox(height: WpSpacing.xl),
                OverviewColumnDrop(
                  side: side,
                  blocks: blocks,
                  visible: visible,
                ),
              ],
            ];
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OverviewHintPlace(),
                ...column(mainBlocks, false),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...head,
                const SizedBox(height: WpSpacing.xl),
                if (sideBlocks.isEmpty && !dragging)
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
                          children: column(sideBlocks, true),
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
              ..._column(visible, visible: visible, side: null),
            ],
          );
        },
      ),
    );
  }

  /// One key per card across both columns: a card moved into the other
  /// column keeps its state and the keyboard focus on its grip.
  final Map<OverviewBlock, GlobalKey> _keys = {};

  /// The movable cards of one column with the gaps between them. The
  /// figures strip keeps its wider gap before the recordings below it.
  /// [side] is the column of the wide layout, null in the one-column one.
  List<Widget> _column(
    List<OverviewBlock> blocks, {
    required List<OverviewBlock> visible,
    required bool? side,
  }) => [
    for (final (i, block) in blocks.indexed) ...[
      if (i > 0)
        SizedBox(
          height:
              blocks[i - 1] == OverviewBlock.figures &&
                  block == OverviewBlock.recent
              ? WpSpacing.xxl
              : WpSpacing.xl,
        ),
      OverviewMovableCard(
        key: _keys.putIfAbsent(
          block,
          () => GlobalKey(debugLabel: 'overview-card-${block.id}'),
        ),
        block: block,
        visible: visible,
        side: side,
        reserveTop: block == OverviewBlock.community,
        child: _card(block, narrow: side ?? false),
      ),
    ],
  ];

  /// [narrow]: the card sits in the side column, so the figures stack.
  static Widget _card(OverviewBlock block, {required bool narrow}) =>
      switch (block) {
        OverviewBlock.figures => OverviewFigures(stacked: narrow),
        OverviewBlock.recent => const OverviewRecent(),
        OverviewBlock.notes => const OverviewNotes(),
        OverviewBlock.dictation => const OverviewLastDictation(),
        OverviewBlock.storage => const OverviewStorage(),
        OverviewBlock.system => const OverviewSystemCard(),
        OverviewBlock.weather => const OverviewWeatherCard(),
        OverviewBlock.news => const OverviewNews(),
        OverviewBlock.community => const OverviewCommunity(),
      };
}
