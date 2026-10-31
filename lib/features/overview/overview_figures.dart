import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/analytics_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_segmented_selector.dart';
import '../../widgets/wp_stat_tile.dart';
import '../../widgets/wp_text_link.dart';
import '../analytics/analytics_page.dart' show formatAnalyticsDuration;
import 'overview_navigation.dart';
import 'overview_providers.dart';

/// W4 and W5: the key figures of the chosen period (words, words per minute,
/// time saved, dictation days) in one card: title, the period choice across
/// the card (it applies to every value) and the figures, with the link to the
/// Statistik page in the title line. [stacked] lists the figures one under the
/// other with dividers, for the side column of a wide window; otherwise they
/// share one row, two per row when the space is narrow.
class OverviewFigures extends ConsumerWidget {
  const OverviewFigures({super.key, this.stacked = false});

  final bool stacked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final period = ref.watch(overviewPeriodProvider);
    final figures =
        ref.watch(overviewFiguresProvider(period)).value ?? AnalyticsData.empty;
    final lang = Localizations.localeOf(context).languageCode;
    final numbers = NumberFormat.decimalPattern(lang);
    final wpm = overviewWordsPerMinute(figures);
    String count(int v) => numbers.format(v);

    final tiles = [
      WpStatTile.row(
        key: const ValueKey('overview-figure-words'),
        isLead: true,
        icon: LucideIcons.type,
        rawValue: figures.totalWords,
        formatter: count,
        label: l10n.overviewFiguresWords,
      ),
      WpStatTile.row(
        key: const ValueKey('overview-figure-wpm'),
        icon: LucideIcons.gauge,
        rawValue: wpm?.round() ?? 0,
        formatter: count,
        placeholder: wpm == null ? l10n.overviewFiguresTooFewData : null,
        label: l10n.overviewFiguresWordsPerMinute,
      ),
      WpStatTile.row(
        key: const ValueKey('overview-figure-time-saved'),
        icon: LucideIcons.zap,
        rawValue: figures.timeSavedMinutes,
        formatter: (v) => formatAnalyticsDuration(l10n, lang, v),
        label: l10n.overviewFiguresTimeSaved,
        note: l10n.analyticsTimeSavedNote(kAnalyticsTypingWordsPerMinute),
      ),
      WpStatTile.row(
        key: const ValueKey('overview-figure-days'),
        icon: LucideIcons.calendarCheck,
        rawValue: figures.activeDays,
        formatter: count,
        label: period == OverviewPeriod.week
            ? l10n.overviewStreakLabel
            : l10n.overviewStreakLabelAll,
      ),
    ];

    return WpCard(
      key: const ValueKey('overview-figures'),
      title: l10n.overviewFiguresTitle,
      titleTestId: 'overview-figures-title',
      trailing: WpTextLink(
        testID: 'overview-figures-statistics',
        label: l10n.navAnalytics,
        icon: LucideIcons.arrowRight,
        iconAfter: true,
        onPressed: () => overviewOpenTarget(ref, 'analytics'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WpSegmentedChoice<OverviewPeriod>(
            key: const ValueKey('overview-figures-period'),
            height: 40,
            options: [
              WpSegmentOption(
                value: OverviewPeriod.week,
                label: l10n.overviewPeriodWeek,
              ),
              WpSegmentOption(
                value: OverviewPeriod.all,
                label: l10n.overviewPeriodAll,
              ),
            ],
            selected: period,
            onChanged: (p) => ref.read(overviewPeriodProvider.notifier).set(p),
          ),
          const SizedBox(height: WpSpacing.xs),
          if (stacked)
            for (final (i, tile) in tiles.indexed) ...[
              if (i > 0) const WpRowDivider(),
              tile,
            ]
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final perRow = constraints.maxWidth < 520 ? 2 : tiles.length;
                final width =
                    (constraints.maxWidth - WpSpacing.xl * (perRow - 1)) /
                    perRow;
                return Wrap(
                  spacing: WpSpacing.xl,
                  children: [
                    for (final tile in tiles)
                      SizedBox(width: width, child: tile),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
