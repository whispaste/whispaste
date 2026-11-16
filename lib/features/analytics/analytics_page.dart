import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/accessibility/announce.dart';
import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/recording/recording_helpers.dart' show displayNameForModel;
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_stat_tile.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/section.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../core/data/analytics_provider.dart';
import '../../services/recording_orchestrator.dart'
    show recordingOrchestratorProvider;

// ---------------------------------------------------------------------------
// Helper data classes (kept local — only used by widgets below)
// ---------------------------------------------------------------------------

class _ModelUsage {
  const _ModelUsage(this.id, this.name, this.count, this.fraction);

  /// The raw model id, kept alongside the display name because it — not the
  /// translated label — is what [categorySlotForModel] keys on. A localized
  /// name would hand the same model a different hue per language.
  final String id;
  final String name;
  final int count;
  final double fraction;
}

class _DurationBucket {
  const _DurationBucket(this.label, this.count, this.fraction);
  final String label;
  final int count;
  final double fraction;
}

/// Maps a raw model ID (e.g. "whisper-small") to a user-facing label
/// using the tier name as the primary label and the Whisper model name
/// in parentheses for recognition.
/// Delegates to the shared [displayNameForModel] helper.
String _displayNameForModel(String modelId, L10n l10n) =>
    displayNameForModel(modelId, l10n);

// ---------------------------------------------------------------------------
// Analytics Dashboard Page
// ---------------------------------------------------------------------------

/// Premium analytics dashboard with hero stats, charts, and cost overview.
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(analyticsProvider);
    final l10n = L10n.of(context);

    Widget body(AnalyticsData data) {
      if (data.isEmpty) {
        // An empty period keeps the selector, so the user can widen it. Only
        // the all-time view gets the page-level "no recordings yet" (UIA-ANA-01).
        if (ref.watch(analyticsPeriodProvider) != AnalyticsPeriod.allTime) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: _PeriodSelector(),
              ),
              const SizedBox(height: WpSpacing.md),
              WpEmptyState(
                icon: LucideIcons.chartNoAxesColumn,
                title: l10n.analyticsNoRecordingsInPeriod,
                actionLabel: l10n.dockDictate,
                actionTestId: 'analytics-period-dictate',
                onAction: () => ref
                    .read(recordingOrchestratorProvider.notifier)
                    .toggleRecording(),
              ),
            ],
          );
        }
        return WpEmptyState(
          icon: LucideIcons.chartNoAxesColumn,
          title: l10n.analyticsEmptyTitle,
          hint: l10n.analyticsEmptySubtitle,
          // Statistics fill from recordings: the first action is "Dictate".
          actionLabel: l10n.dockDictate,
          actionTestId: 'analytics-empty-dictate',
          onAction: () => ref
              .read(recordingOrchestratorProvider.notifier)
              .toggleRecording(),
        );
      }
      return _AnalyticsDashboard(data: data);
    }

    // A refresh (retry, reset) keeps the figures on screen. A reload (the
    // period changed) must not show the previous period's numbers under the
    // new label, so it falls through to that period's snapshot instead.
    if (asyncData.hasValue && !asyncData.isReloading && !asyncData.hasError) {
      return body(asyncData.requireValue);
    }
    if (asyncData.hasError && !asyncData.isLoading) {
      // Only a failure outside every panel lands here (e.g. no database);
      // a single failed query shows inside its own panel (#887).
      return WpEmptyState(
        icon: LucideIcons.triangleAlert,
        title: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        actionTestId: 'analytics-retry',
        onAction: () => ref.invalidate(analyticsProvider),
      );
    }
    // Opening the page shows the last complete result at once; the full
    // aggregation runs behind it and replaces it when done (#887).
    final snapshot = ref.watch(analyticsSnapshotProvider).value;
    if (snapshot != null) return body(snapshot);
    return _AnalyticsSkeleton(label: l10n.analyticsLoading);
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — page-shaped placeholder (4 stat cards + chart area)
// ---------------------------------------------------------------------------

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final boxColor = WpColors.borderSubtle;

    return Semantics(
      label: label,
      child: WpPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Key-figure placeholder, then one row of supporting tiles,
            // matching the loaded layout (#1075).
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: WpRadius.borderMd,
              ),
            ),
            const SizedBox(height: WpSpacing.sm),
            Row(
              children: List.generate(3, (i) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? WpSpacing.sm : 0),
                    child: Container(
                      height: 88,
                      decoration: BoxDecoration(
                        color: boxColor,
                        borderRadius: WpRadius.borderMd,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: WpSpacing.xxl),
            // Chart area placeholder
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: WpRadius.borderMd,
              ),
            ),
            const SizedBox(height: WpSpacing.xxl),
            // Two side-by-side panel placeholders
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: WpRadius.borderMd,
                    ),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: WpRadius.borderMd,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard body
// ---------------------------------------------------------------------------

class _AnalyticsDashboard extends StatelessWidget {
  const _AnalyticsDashboard({required this.data});

  final AnalyticsData data;

  /// Wraps one panel: its own content, or — when that panel's query failed —
  /// an error card with its own retry, so the rest of the page stays usable.
  Widget _panel(
    AnalyticsPanel panel, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return WpCard(
      child: data.failedPanels.contains(panel)
          ? _PanelError(panel: panel, icon: icon, title: title)
          : child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A failed reset says so here, under the page head where one looks
          // (the button sits at the foot of a long page).
          const WpPageNoticeSlot(page: WpNoticePage.analytics),
          // ── Row 1: Hero stat cards ──────────────────────────────
          //
          // The period selector rides in the section header, not at the page
          // foot where it used to sit: it is the caption for every number
          // below it, and a caption you only meet after reading the whole
          // dashboard has already failed. On the header line it is the first
          // thing in reading order after the section title.
          WpSection(
            title: l10n.analyticsOverview,
            subtitle: l10n.analyticsOverviewSubtitle,
            padding: EdgeInsets.zero,
            trailing: const _PeriodSelector(),
            child: data.failedPanels.contains(AnalyticsPanel.overview)
                ? WpCard(
                    child: _PanelError(
                      panel: AnalyticsPanel.overview,
                      icon: LucideIcons.gauge,
                      title: l10n.analyticsOverview,
                    ),
                  )
                : _HeroStatsRow(data: data),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 2: Activity chart + Model usage ────────────────
          WpSection(
            title: l10n.analyticsActivity,
            padding: EdgeInsets.zero,
            child: WpTwoPanel(
              left: _panel(
                AnalyticsPanel.activity,
                icon: LucideIcons.calendarDays,
                title: l10n.analyticsRecordingActivity,
                child: _ActivityHeatmapPanel(
                  daily: data.dailyActivity,
                  streakDays: data.streakDays,
                ),
              ),
              right: _panel(
                AnalyticsPanel.models,
                icon: LucideIcons.brain,
                title: l10n.analyticsModelUsage,
                child: _ModelUsagePanel(
                  models: data.modelUsage
                      .map(
                        (m) => _ModelUsage(
                          m.model,
                          _displayNameForModel(m.model, l10n),
                          m.count,
                          m.fraction,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 3: Duration distribution + Cost overview ───────
          WpSection(
            title: l10n.analyticsInsights,
            padding: EdgeInsets.zero,
            child: WpTwoPanel(
              left: _panel(
                AnalyticsPanel.durations,
                icon: LucideIcons.timer,
                title: l10n.analyticsDurationDistribution,
                child: _DurationDistPanel(
                  buckets: _buildBuckets(l10n, data.durationBuckets),
                ),
              ),
              right: _panel(
                AnalyticsPanel.costs,
                icon: LucideIcons.piggyBank,
                title: l10n.analyticsCostSavings,
                child: _CostPanel(
                  localSavingsUsd: data.localSavingsUsd,
                  cloudCostUsd: data.cloudCostUsd,
                ),
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 3b: Wording + frequent corrections ─────────────
          WpSection(
            title: l10n.analyticsWordingTitle,
            padding: EdgeInsets.zero,
            child: WpTwoPanel(
              left: _panel(
                AnalyticsPanel.wording,
                icon: LucideIcons.textCursorInput,
                title: l10n.analyticsWordingPanelTitle,
                child: _WordingPanel(wording: data.wording),
              ),
              right: _panel(
                AnalyticsPanel.corrections,
                icon: LucideIcons.spellCheck,
                title: l10n.analyticsCorrectionsTitle,
                child: _CorrectionsPanel(corrections: data.topCorrections),
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 4: what is counted, then Reset ─────────────────
          Text(
            l10n.analyticsPrivacyNote,
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: WpColors.textMuted,
            ),
          ),
          const SizedBox(height: WpSpacing.md),
          const _ResetRow(),

          const SizedBox(height: WpSpacing.xl),
        ],
      ),
    );
  }

  List<_DurationBucket> _buildBuckets(L10n l10n, List<int> raw) {
    // A snapshot or fallback may carry fewer than five buckets; pad with 0.
    final counts = [for (var i = 0; i < 5; i++) i < raw.length ? raw[i] : 0];
    final total = counts.fold<int>(0, (s, c) => s + c);
    double frac(int c) => total > 0 ? c / total : 0.0;
    return [
      _DurationBucket(l10n.analyticsDurationLt15s, counts[0], frac(counts[0])),
      _DurationBucket(
        l10n.analyticsDuration15To30s,
        counts[1],
        frac(counts[1]),
      ),
      _DurationBucket(
        l10n.analyticsDuration30To60s,
        counts[2],
        frac(counts[2]),
      ),
      _DurationBucket(l10n.analyticsDuration1To3m, counts[3], frac(counts[3])),
      _DurationBucket(l10n.analyticsDurationGt3m, counts[4], frac(counts[4])),
    ];
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _commaFormat(String localeName, int value) {
  return NumberFormat.decimalPattern(localeName).format(value);
}

/// A count in the app locale, with the same thousands separator everywhere.
String _countText(BuildContext context, int value) =>
    _commaFormat(Localizations.localeOf(context).toString(), value);

/// Formats a whole-minute total for the hero stats in the app locale: decimal
/// hours from one hour up ("7,1 Std." in de), whole minutes below ("45 Min.").
/// A single compact unit keeps the 22 px hero number on its full rung; the
/// former "7 Std. 3 Min." had to be scaled down by the FittedBox.
String formatAnalyticsDuration(L10n l10n, String localeName, int totalMinutes) {
  if (totalMinutes < 60) {
    return l10n.analyticsDurationMinutes('$totalMinutes');
  }
  final hours = NumberFormat('#,##0.0', localeName).format(totalMinutes / 60);
  return l10n.analyticsDurationHours(hours);
}

/// Formats a cost total in USD for the app locale: the source prices are
/// per-transcription USD API prices, so the currency stays USD and only the
/// rendering follows the locale ("127,05 $" in de, "$127.05" in en).
String formatAnalyticsUsd(String localeName, double usd) =>
    NumberFormat.currency(
      locale: localeName,
      symbol: r'$',
      decimalDigits: 2,
    ).format(usd);

/// Formats a hotkey→text latency in whole milliseconds as a plain-language
/// seconds value (e.g. "1.8s") — never raw milliseconds.
String _latencySecondsFormat(String localeName, int latencyMs) {
  final seconds = latencyMs / 1000;
  return '${NumberFormat('0.0', localeName).format(seconds)}s';
}

List<String> _activityDayLabels(L10n l10n) => [
  l10n.analyticsDayMon,
  l10n.analyticsDayTue,
  l10n.analyticsDayWed,
  l10n.analyticsDayThu,
  l10n.analyticsDayFri,
  l10n.analyticsDaySat,
  l10n.analyticsDaySun,
];

// ---------------------------------------------------------------------------
// Panel header (renders inside a panel card)
// ---------------------------------------------------------------------------

/// Header inside a panel card — icon + title.
///
/// It used to hang a 1.5 × 40 px accent gradient under the title, kept as a
/// deliberate exception on the argument that the underline was "the only thing
/// separating two header ranks" here, whereas on About the `_AboutCard` border
/// already framed the group and the same underline would have been decoration
/// on top of decoration. Ticket 14 gives these panels that border, so the
/// exception's own condition no longer holds: [_AnalyticsPanelCard] now says
/// where a panel begins and ends, and the underline went back to being the
/// second mark for one boundary. The header keeps its accent *icon*, which is
/// what actually distinguishes a panel head from the [WpSection] title above
/// it, at no cost in paint.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    return Row(
      children: [
        Icon(icon, size: WpIconSize.sm, color: accent),
        const SizedBox(width: WpSpacing.xs),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: WpTypography.body,
              fontWeight: FontWeight.w600,
              color: WpColors.textPrimary,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: WpSpacing.xs),
          trailing!,
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Row 1 — Hero Stats
// ---------------------------------------------------------------------------

class _HeroStatsRow extends StatelessWidget {
  const _HeroStatsRow({required this.data});

  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final localeName = Localizations.localeOf(context).toString();
    String formatCount(int value) => _commaFormat(localeName, value);
    String formatDuration(int totalMinutes) =>
        formatAnalyticsDuration(l10n, localeName, totalMinutes);

    final wpm = data.wordsPerMinute;
    final timeSavedNote = l10n.analyticsTimeSavedNote(
      kAnalyticsTypingWordsPerMinute,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // One key moment, then the supporting detail (#1075, premium-apps:
        // one focus per view). The words dictated are what the whole app
        // exists to produce, so that figure takes a row of its own in the
        // hero stage; seven equally weighted tiles left the reader to find
        // the point themselves. The pace and what it saved follow, then the
        // supporting counts, in a grid of 2 or 3 columns.
        final lead = WpStatTile(
          hero: true,
          icon: LucideIcons.type,
          rawValue: data.totalWords,
          formatter: formatCount,
          label: l10n.analyticsWordsDictated,
        );
        // Every supporting tile reserves the time-saved note's line, so the
        // one tile that carries a note no longer stands taller than its
        // neighbours; each grid row also stretches to its tallest tile in
        // case a label wraps.
        final tiles = [
          if (wpm != null)
            WpStatTile(
              icon: LucideIcons.gauge,
              rawValue: wpm.round(),
              formatter: formatCount,
              label: l10n.analyticsWordsPerMinute,
              reserveNote: timeSavedNote,
            ),
          WpStatTile(
            icon: LucideIcons.zap,
            rawValue: data.timeSavedMinutes,
            formatter: formatDuration,
            label: l10n.analyticsTimeSaved,
            note: timeSavedNote,
          ),
          WpStatTile(
            icon: LucideIcons.clock,
            rawValue: data.totalDurationMinutes,
            formatter: formatDuration,
            label: l10n.analyticsTotalDuration,
            reserveNote: timeSavedNote,
          ),
          WpStatTile(
            icon: LucideIcons.mic,
            rawValue: data.totalRecordings,
            formatter: formatCount,
            label: l10n.analyticsTotalRecordings,
            reserveNote: timeSavedNote,
          ),
          if (data.activeDays > 0)
            WpStatTile(
              icon: LucideIcons.calendarCheck,
              rawValue: data.activeDays,
              formatter: formatCount,
              label: l10n.analyticsActiveDays,
              reserveNote: timeSavedNote,
            ),
          if (data.averageStopToTextMs != null)
            WpStatTile(
              icon: LucideIcons.timer,
              rawValue: data.averageStopToTextMs!.round(),
              formatter: (ms) => _latencySecondsFormat(localeName, ms),
              label: l10n.analyticsAvgLatency,
              reserveNote: timeSavedNote,
            ),
        ];

        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        final rows = <Widget>[];
        for (var start = 0; start < tiles.length; start += columns) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start; i < start + columns; i++) ...[
                    if (i > start) const SizedBox(width: WpSpacing.sm),
                    // An empty cell keeps a short last row on the grid
                    // instead of stretching its tiles wider than the rest.
                    Expanded(
                      child: i < tiles.length
                          ? tiles[i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            lead,
            for (final row in rows) ...[
              const SizedBox(height: WpSpacing.sm),
              row,
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Per-panel error state
// ---------------------------------------------------------------------------

/// What a panel shows when its own query failed (#887): its header, so one
/// still knows which figure is missing, a plain sentence and a retry. The
/// other panels keep their numbers; a whole-page error would hide them all.
class _PanelError extends ConsumerWidget {
  const _PanelError({
    required this.panel,
    required this.icon,
    required this.title,
  });

  final AnalyticsPanel panel;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Column(
      key: ValueKey('analytics-${panel.name}-error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(icon: icon, title: title),
        const SizedBox(height: WpSpacing.md),
        Row(
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: WpIconSize.sm,
              color: WpColors.textMuted,
            ),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                l10n.analyticsPanelError,
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.sm),
        WpButton(
          label: l10n.actionRetry,
          testId: 'analytics-${panel.name}-retry',
          variant: WpButtonVariant.secondary,
          size: WpButtonSize.dense,
          icon: LucideIcons.refreshCw,
          onPressed: () => ref.invalidate(analyticsProvider),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Row 2 — Activity heatmap (custom painter)
// ---------------------------------------------------------------------------

/// Weeks the heatmap shows: a season of use at a glance, still legible as
/// single cells in a half-width panel.
const _heatmapWeeks = 16;

/// Lays the trailing [_heatmapWeeks] weeks of [daily] (oldest first, today
/// last) out as week columns of seven rows, Monday on top. Cells after
/// [today] in the current week are `null` (not painted); days before the
/// data starts count as 0.
@visibleForTesting
List<int?> heatmapCells(List<int> daily, DateTime today) {
  final cells = List<int?>.filled(_heatmapWeeks * 7, null);
  final todayRow = today.weekday - 1;
  for (var col = 0; col < _heatmapWeeks; col++) {
    for (var row = 0; row < 7; row++) {
      final daysAgo = (_heatmapWeeks - 1 - col) * 7 + (todayRow - row);
      if (daysAgo < 0) continue;
      final i = daily.length - 1 - daysAgo;
      cells[col * 7 + row] = i >= 0 ? daily[i] : 0;
    }
  }
  return cells;
}

class _ActivityHeatmapPanel extends StatelessWidget {
  const _ActivityHeatmapPanel({required this.daily, required this.streakDays});

  final List<int> daily;
  final int streakDays;

  static const double _gap = 3;
  static const double _labelWidth = 28;
  static const double _maxCell = 14;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final cells = heatmapCells(daily, DateTime.now());
    final visible = cells.whereType<int>();
    final activeDays = visible.where((v) => v > 0).length;
    final recordings = visible.fold<int>(0, (s, v) => s + v);
    final summary = [
      l10n.analyticsHeatmapSummary(activeDays, recordings),
      if (streakDays > 0) l10n.analyticsStreakDays(streakDays),
    ].join('. ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.calendarDays,
          title: l10n.analyticsRecordingActivity,
          trailing: Text(
            l10n.analyticsLast16Weeks,
            style: TextStyle(fontSize: WpTypography.caption, color: textMuted),
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        // A quiet stretch keeps its grid, but says why it is empty (UIA-ANA-06).
        if (activeDays == 0) ...[
          Text(
            l10n.analyticsHeatmapEmpty,
            style: TextStyle(fontSize: WpTypography.caption, color: textMuted),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final cell = math.min(
              _maxCell,
              (constraints.maxWidth -
                      _labelWidth -
                      _gap * (_heatmapWeeks - 1)) /
                  _heatmapWeeks,
            );
            final size = math.max(cell, 4.0);
            return Semantics(
              key: const ValueKey('analytics-activity-heatmap'),
              label: summary,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: size * 7 + _gap * 6,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _HeatmapPainter(
                      cells: cells,
                      cellSize: size,
                      gap: _gap,
                      labelWidth: _labelWidth,
                      dayLabels: _activityDayLabels(l10n),
                      fillColor: WpColors.accent,
                      emptyColor: WpColors.borderSubtle,
                      labelColor: textMuted,
                      // CustomPainter TextPainter bypasses widget font
                      // inheritance; pass the family explicitly.
                      labelFontFamily: Theme.of(
                        context,
                      ).textTheme.labelSmall?.fontFamily,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // The streak only appears while there is one: no "streak lost"
        // message, a pause is not a failure (calm UI, Nordstern §10).
        if (streakDays > 0) ...[
          const SizedBox(height: WpSpacing.sm),
          ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: l10n.analyticsStreakDays(streakDays),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: WpColors.textPrimary,
                    ),
                  ),
                  TextSpan(text: ' · ${l10n.analyticsStreakGrace}'),
                ],
              ),
              style: TextStyle(
                fontSize: WpTypography.caption,
                color: textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.cells,
    required this.cellSize,
    required this.gap,
    required this.labelWidth,
    required this.dayLabels,
    required this.fillColor,
    required this.emptyColor,
    required this.labelColor,
    this.labelFontFamily,
  });

  final List<int?> cells;
  final double cellSize;
  final double gap;
  final double labelWidth;
  final List<String> dayLabels;
  final Color fillColor;
  final Color emptyColor;
  final Color labelColor;
  final String? labelFontFamily;

  /// Four steps of the one accent hue; a fifth, empty step is the grid tone.
  static const _alphas = [0.3, 0.5, 0.75, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = cells.whereType<int>().fold<int>(0, math.max);

    // Monday, Wednesday, Friday: every other row, as calendars label them.
    for (final row in const [0, 2, 4]) {
      final tp = TextPainter(
        text: TextSpan(
          text: dayLabels[row],
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: labelColor,
            fontFamily: labelFontFamily,
          ),
        ),
        // Intentionally LTR, like every axis label here, also in Hebrew.
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelWidth);
      final y = row * (cellSize + gap) + (cellSize - tp.height) / 2;
      tp.paint(canvas, Offset(0, y));
    }

    final radius = Radius.circular(cellSize / 4);
    final paint = Paint();
    for (var i = 0; i < cells.length; i++) {
      final v = cells[i];
      if (v == null) continue;
      final col = i ~/ 7;
      final row = i % 7;
      if (v == 0 || maxVal == 0) {
        paint.color = emptyColor;
      } else {
        final step = ((v / maxVal) * _alphas.length).ceil().clamp(
          1,
          _alphas.length,
        );
        paint.color = fillColor.withValues(alpha: _alphas[step - 1]);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelWidth + col * (cellSize + gap),
            row * (cellSize + gap),
            cellSize,
            cellSize,
          ),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      !listEquals(old.cells, cells) ||
      old.cellSize != cellSize ||
      old.fillColor != fillColor ||
      old.emptyColor != emptyColor ||
      old.labelColor != labelColor ||
      old.labelFontFamily != labelFontFamily;
}

// ---------------------------------------------------------------------------
// Row 2 — Model usage
// ---------------------------------------------------------------------------

class _ModelUsagePanel extends StatelessWidget {
  const _ModelUsagePanel({required this.models});

  final List<_ModelUsage> models;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(icon: LucideIcons.brain, title: l10n.analyticsModelUsage),
        const SizedBox(height: WpSpacing.md),
        if (models.isEmpty)
          Text(
            l10n.analyticsNoModelData,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textMuted,
            ),
          )
        else
          ...models.map((m) => _ModelUsageBar(model: m)),
      ],
    );
  }
}

/// One model's share of the recordings — name, percentage, count, bar.
///
/// The bar is a **flat category color**, not the accent gradient it used to be.
/// Models are a *nominal* scale: three of them wearing one cyan ramp said only
/// "this is a bar", while three category slots say *which* model each bar is —
/// the distinction a nominal scale owes. The gradient stays out on
/// purpose; it is the brand's own moment and spending it on a list of three
/// bars is what made every panel on this page look equally important.
///
/// Which hue a model gets is decided in `colors.dart` and keyed on the raw id,
/// never picked here — see [categorySlotForModel]. The percentage stays on the
/// accent: it is the value being read, and letting the category hue mark it
/// would turn a slot into an importance marker (*The Two Accent, Two Jobs Rule*).
class _ModelUsageBar extends StatelessWidget {
  const _ModelUsageBar({required this.model});

  final _ModelUsage model;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    final trackColor = WpColors.surfaceVariant;
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.name,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(model.fraction * 100).round()}%',
                style: TextStyle(
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                '(${_countText(context, model.count)})',
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xxs),
          ClipRRect(
            borderRadius: WpRadius.borderFull,
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  ColoredBox(color: trackColor),
                  FractionallySizedBox(
                    widthFactor: model.fraction,
                    child: ColoredBox(
                      color: categorySlotForModel(model.id).color(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row 3 — Duration distribution
// ---------------------------------------------------------------------------

class _DurationDistPanel extends StatelessWidget {
  const _DurationDistPanel({required this.buckets});

  final List<_DurationBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Every bar is the accent (#1075): the page's charts speak in the design
    // system's accent family, and the violet `iris` ramp this used to draw was
    // a second accent the rest of the app never uses. One series needs one
    // colour — the bucket order is already carried by the row labels, and an
    // accent ramp could not climb far on dark grounds before its rungs turned
    // near-white and stopped reading as the accent at all.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.timer,
          title: l10n.analyticsDurationDistribution,
        ),
        const SizedBox(height: WpSpacing.md),
        for (final b in buckets) _DurationBar(bucket: b),
      ],
    );
  }
}

/// One duration bucket — label, bar, count. The bar is the accent.
class _DurationBar extends StatelessWidget {
  const _DurationBar({required this.bucket});

  final _DurationBucket bucket;

  @override
  Widget build(BuildContext context) {
    // The track is `surfaceVariant`, the same ground the model bars run on. It
    // used to be `textMuted` at a hand-rolled alpha, which *The Tint Ladder
    // Rule* forbids — and an alpha over an unknown ground is also a track no
    // bar colour can be measured against.
    final trackColor = WpColors.surfaceVariant;
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;

    // The two text columns are fixed-width on purpose — that is what keeps
    // the bars starting and ending on one line down the whole panel. But a
    // width in raw pixels stops being enough the moment the system font grows:
    // at an accessibility text size "1-3 Min" wrapped inside its 52 px box
    // while the bar next to it stayed put. Scaling the box with the text keeps
    // the column *and* the legibility.
    final textScaler = MediaQuery.textScalerOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: textScaler.scale(52),
            child: Text(
              bucket.label,
              style: TextStyle(
                fontSize: WpTypography.caption,
                color: textPrimary,
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: ClipRRect(
              borderRadius: WpRadius.borderFull,
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    ColoredBox(color: trackColor),
                    FractionallySizedBox(
                      widthFactor: bucket.fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: WpColors.accent,
                          borderRadius: WpRadius.borderFull,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.xs),
          SizedBox(
            width: textScaler.scale(32),
            child: Text(
              _countText(context, bucket.count),
              style: TextStyle(
                fontSize: WpTypography.caption,
                color: textMuted,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row 3 — Cost & Savings
// ---------------------------------------------------------------------------

class _CostPanel extends StatelessWidget {
  const _CostPanel({required this.localSavingsUsd, required this.cloudCostUsd});

  final double localSavingsUsd;
  final double cloudCostUsd;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final localeName = Localizations.localeOf(context).toString();

    final savingsStr = formatAnalyticsUsd(localeName, localSavingsUsd);
    final costStr = formatAnalyticsUsd(localeName, cloudCostUsd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.piggyBank,
          title: l10n.analyticsCostSavings,
        ),
        const SizedBox(height: WpSpacing.lg),

        // Local savings
        _StatRow(
          icon: LucideIcons.shieldCheck,
          title: l10n.analyticsLocalSavings,
          value: l10n.analyticsSavedAmount(savingsStr),
        ),
        const SizedBox(height: WpSpacing.sm),

        // Cloud cost
        _StatRow(
          icon: LucideIcons.cloud,
          title: l10n.analyticsCloudCost,
          value: l10n.analyticsSpentAmount(costStr),
        ),
        // Both figures are computed from list prices, not billed (UIA-ANA-04).
        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.analyticsEstimateNote,
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: WpColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// One line of the cost panel: an icon, what the number counts, the number.
///
/// Both rows used to be colour-coded — savings in `success` green, cloud spend
/// in `warning` amber — and neither is a status. These are running totals over
/// the whole selected period: money that was never spent because dictation ran
/// locally, and money that was. Green here says "that just worked" about a
/// figure that has been true for weeks (the Earned-Green Rule, `lib/DESIGN.md`),
/// and amber says "look out" about a bill the user chose to run up. Ticket 32,
/// finding B5. The row therefore takes no colour parameters at all any more:
/// there is no per-row decision left to make, which is the point — the label
/// says which number this is, and both numbers read in the same voice.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textPrimary = WpColors.textPrimary;

    return Row(
      children: [
        Icon(icon, size: WpIconSize.sm, color: WpColors.textMuted),
        const SizedBox(width: WpSpacing.xs),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: WpTypography.small, color: textPrimary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: WpTypography.body,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overview header — period selector
// ---------------------------------------------------------------------------

/// The chip row that decides which period every number on this page describes.
///
/// Lives in the Overview section's `trailing` slot. It used to sit at the very
/// bottom of the page, beside the Reset button, which meant the reader met the
/// scope of the statistics only *after* reading all of them — and met it next
/// to a destructive control, as if picking a period were the same kind of act
/// as wiping the history.
///
/// A [Row] with `mainAxisSize.min`, deliberately not a [Wrap]: `RenderFlex`
/// measures its non-flexible children — this widget — against an *unbounded*
/// main axis and only then hands the remainder to the header's `Expanded`
/// title column. A `Wrap` here could therefore never wrap; it would silently
/// stay on one line and push the squeeze onto the title instead. If the chips
/// ever stop fitting, the fix belongs one level up, in `_AnalyticsDashboard`,
/// where the width is bounded and a full-width row above the stat cards is
/// still available.
///
/// It does fit, measured rather than assumed. At 800 px — the app's minimum
/// window width — the header line is 740 px wide, and German, the tightest of
/// the three locales, spends 336 of them on chips and 255 on the subtitle at
/// normal text size; at 1.15× it is 364 + 291. Only at a 1.5× accessibility
/// size does the pair stop fitting, and then the subtitle reflows onto a
/// second line under the title while the chips stay put — no clipping, no
/// overflow. `analytics_page_test.dart` pins all of that for de/en/he, with
/// the real Inter faces loaded, because the default test font is roughly
/// twice as wide per glyph and would have condemned a layout that ships fine.
class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final periods = [
      l10n.analyticsPeriod7d,
      l10n.analyticsPeriod30d,
      l10n.analyticsPeriod90d,
      l10n.analyticsPeriodAll,
    ];

    final currentPeriod = ref.watch(analyticsPeriodProvider);
    final selectedIndex = AnalyticsPeriod.values.indexOf(currentPeriod);

    // Period chips — WpFilterChip, the app's one selectable chip.
    //
    // These were a fourth independent reimplementation of it, and the
    // worst-off: bare GestureDetectors with no Semantics at all, so the
    // control that decides what the whole page shows was invisible to a
    // screen reader, unreachable by keyboard, and never announced which
    // period was selected. WpFilterChip brings the focus ring, `selected:`
    // and a 44 dp tap target with it, and History/Notes already read this
    // way, so the same widget now answers the same question everywhere.
    return Padding(
      // Keeps the chips off the section title/subtitle, which the header's
      // Expanded lets run right up to this widget's leading edge.
      padding: const EdgeInsetsDirectional.only(start: WpSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(periods.length, (i) {
          return Padding(
            padding: EdgeInsetsDirectional.only(
              start: i == 0 ? 0 : WpSpacing.xs,
            ),
            child: WpFilterChip(
              label: periods[i],
              testId: 'analytics-period-${AnalyticsPeriod.values[i].name}',
              isActive: i == selectedIndex,
              onTap: () => ref
                  .read(analyticsPeriodProvider.notifier)
                  .setPeriod(AnalyticsPeriod.values[i]),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row 4 — Reset
// ---------------------------------------------------------------------------

/// The page's destructive action, alone at the foot of the dashboard.
///
/// Stays last on purpose — wiping the statistics is the one thing on this page
/// that cannot be undone, so it belongs where nobody reaches it on the way to
/// something else. Only the period selector moved up; see [_PeriodSelector].
class _ResetRow extends ConsumerStatefulWidget {
  const _ResetRow();

  @override
  ConsumerState<_ResetRow> createState() => _ResetRowState();
}

class _ResetRowState extends ConsumerState<_ResetRow> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            // Reset button
            WpButton(
              label: l10n.analyticsReset,
              testId: 'analytics-reset',
              variant: WpButtonVariant.secondary,
              tone: WpButtonTone.danger,
              size: WpButtonSize.dense,
              icon: LucideIcons.trash2,
              onPressed: () => _confirmReset(context),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmReset(BuildContext context) {
    final l10n = L10n.of(context);
    showWpConfirmDialog(
      context: context,
      title: l10n.analyticsResetTitle,
      message: l10n.analyticsResetMessage,
      confirmLabel: l10n.analyticsReset,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    ).then((confirmed) async {
      if (confirmed) {
        final db = ref.read(historyDatabaseProvider);
        try {
          await db.resetDailyStats();
        } catch (_) {
          if (context.mounted) {
            showWpPageNotice(
              context,
              page: WpNoticePage.analytics,
              notice: WpPageNotice(
                id: 'analytics-reset-failed',
                message: L10n.of(context).errorGeneric,
              ),
            );
          }
          return;
        }
        ref.invalidate(analyticsProvider);
        // The emptied dashboard is the confirmation; a screen reader hears it.
        if (context.mounted) {
          announce(
            View.of(context),
            L10n.of(context).analyticsResetDone,
            Directionality.of(context),
          );
        }
      }
    });
  }
}

/// Raw versus revised word counts and how many recordings a transform changed.
class _WordingPanel extends StatelessWidget {
  const _WordingPanel({required this.wording});

  final AnalyticsWording wording;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.textCursorInput,
          title: l10n.analyticsWordingPanelTitle,
        ),
        const SizedBox(height: WpSpacing.lg),
        _StatRow(
          icon: LucideIcons.fileText,
          title: l10n.analyticsRawWords,
          value: _countText(context, wording.rawWords),
        ),
        const SizedBox(height: WpSpacing.sm),
        _StatRow(
          icon: LucideIcons.penLine,
          title: l10n.analyticsRevisedWords,
          value: '${wording.revisedWords}',
        ),
        const SizedBox(height: WpSpacing.sm),
        _StatRow(
          icon: LucideIcons.sparkles,
          title: l10n.analyticsTransformActions,
          value: '${wording.actionCount}',
        ),
      ],
    );
  }
}

/// The most frequent corrections as "heard → corrected" lines with a count.
class _CorrectionsPanel extends StatelessWidget {
  const _CorrectionsPanel({required this.corrections});

  final List<AnalyticsCorrection> corrections;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.spellCheck,
          title: l10n.analyticsCorrectionsTitle,
        ),
        const SizedBox(height: WpSpacing.lg),
        if (corrections.isEmpty)
          Text(l10n.analyticsNoCorrections)
        else
          for (final c in corrections) ...[
            _StatRow(
              icon: LucideIcons.arrowRight,
              title: '${c.sourceText} → ${c.targetText}',
              value: '${_countText(context, c.count)}×',
            ),
            const SizedBox(height: WpSpacing.sm),
          ],
      ],
    );
  }
}
