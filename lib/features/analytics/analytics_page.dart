import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/recording/recording_helpers.dart' show displayNameForModel;
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/section.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_filter_chip.dart';
import '../../core/data/analytics_provider.dart';

// ---------------------------------------------------------------------------
// Helper data classes (kept local — only used by widgets below)
// ---------------------------------------------------------------------------

class _ModelUsage {
  const _ModelUsage(this.name, this.count, this.fraction);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    return asyncData.when(
      loading: () => _AnalyticsSkeleton(isDark: isDark),
      error: (e, _) => WpEmptyState(
        icon: LucideIcons.triangleAlert,
        title: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        onAction: () => ref.invalidate(analyticsProvider),
      ),
      data: (data) {
        if (data.isEmpty) {
          return WpEmptyState(
            icon: LucideIcons.chartNoAxesColumn,
            title: l10n.analyticsEmptyTitle,
            hint: l10n.analyticsEmptySubtitle,
          );
        }
        return _AnalyticsDashboard(data: data, isDark: isDark);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — page-shaped placeholder (4 stat cards + chart area)
// ---------------------------------------------------------------------------

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final boxColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4 hero stat card placeholders
          Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? WpSpacing.sm : 0),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard body
// ---------------------------------------------------------------------------

class _AnalyticsDashboard extends StatelessWidget {
  const _AnalyticsDashboard({required this.data, required this.isDark});

  final AnalyticsData data;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            trailing: _PeriodSelector(isDark: isDark),
            child: _HeroStatsRow(data: data, isDark: isDark),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 2: Activity chart + Model usage ────────────────
          WpSection(
            title: l10n.analyticsActivity,
            padding: EdgeInsets.zero,
            child: WpTwoPanel(
              left: _ActivityChartPanel(
                values: data.weeklyActivity,
                isDark: isDark,
              ),
              right: _ModelUsagePanel(
                models: data.modelUsage
                    .map(
                      (m) => _ModelUsage(
                        _displayNameForModel(m.model, l10n),
                        m.count,
                        m.fraction,
                      ),
                    )
                    .toList(),
                isDark: isDark,
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 3: Duration distribution + Cost overview ───────
          WpSection(
            title: l10n.analyticsInsights,
            padding: EdgeInsets.zero,
            child: WpTwoPanel(
              left: _DurationDistPanel(
                buckets: _buildBuckets(l10n, data.durationBuckets),
                isDark: isDark,
              ),
              right: _CostPanel(
                localSavingsUsd: data.localSavingsUsd,
                cloudCostUsd: data.cloudCostUsd,
                isDark: isDark,
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // ── Row 4: Reset ───────────────────────────────────────
          _ResetRow(isDark: isDark),

          const SizedBox(height: WpSpacing.xl),
        ],
      ),
    );
  }

  List<_DurationBucket> _buildBuckets(L10n l10n, List<int> counts) {
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

String _durationFormat(L10n l10n, int totalMinutes) {
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return l10n.analyticsDurationHoursMinutes(h, m);
}

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
// Panel header with accent underline (renders directly on surface)
// ---------------------------------------------------------------------------

/// Section header inside a flat panel — icon + title with thin accent underline.
///
/// A third header vocabulary alongside [WpSection] and `SettingRow`, and the
/// accent underline is the very decoration ticket 07 removed from the About
/// page. Kept anyway, as a deliberate exception: this is a genuine *second*
/// level, a panel head nested inside a [WpSection] that already spent its
/// accent bar on the level above. About had no such need — its `_AboutCard`
/// border already framed the group, so there the underline was decoration on
/// top of decoration. Here it is the only thing separating two header ranks.
///
/// Making it a `WpSection` instead would mean two accent bars stacked eight
/// pixels apart, which is worse than the small inconsistency it would fix.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.isDark,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final bool isDark;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                  color: isDark
                      ? WpColorsDark.textPrimary
                      : WpColorsLight.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: WpSpacing.xs),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Container(
          height: 1.5,
          width: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [accent, accent.withAlpha(0)]),
            borderRadius: WpRadius.borderFull,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Row 1 — Hero Stats
// ---------------------------------------------------------------------------

class _HeroStatsRow extends StatelessWidget {
  const _HeroStatsRow({required this.data, required this.isDark});

  final AnalyticsData data;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final localeName = Localizations.localeOf(context).toString();
    String formatCount(int value) => _commaFormat(localeName, value);
    String formatDuration(int totalMinutes) =>
        _durationFormat(l10n, totalMinutes);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final pills = [
          _HeroPill(
            isDark: isDark,
            icon: LucideIcons.mic,
            rawValue: data.totalRecordings,
            formatter: formatCount,
            label: l10n.analyticsTotalRecordings,
          ),
          _HeroPill(
            isDark: isDark,
            icon: LucideIcons.clock,
            rawValue: data.totalDurationMinutes,
            formatter: formatDuration,
            label: l10n.analyticsTotalDuration,
          ),
          _HeroPill(
            isDark: isDark,
            icon: LucideIcons.type,
            rawValue: data.totalWords,
            formatter: formatCount,
            label: l10n.analyticsWordsDictated,
          ),
          _HeroPill(
            isDark: isDark,
            icon: LucideIcons.zap,
            rawValue: data.timeSavedMinutes,
            formatter: formatDuration,
            label: l10n.analyticsTimeSaved,
          ),
          if (data.averageHotkeyLatencyMs != null)
            _HeroPill(
              isDark: isDark,
              icon: LucideIcons.gauge,
              rawValue: data.averageHotkeyLatencyMs!.round(),
              formatter: (ms) => _latencySecondsFormat(localeName, ms),
              label: l10n.analyticsAvgLatency,
            ),
        ];

        if (narrow) {
          return Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            children: pills
                .map(
                  (c) => SizedBox(
                    width: (constraints.maxWidth - WpSpacing.sm) / 2,
                    child: c,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: pills
              .map(
                (c) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: c == pills.last ? 0 : WpSpacing.sm,
                    ),
                    child: c,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

/// Pill-shaped stat block: flat, subtle border, gradient accent strip at top
/// and a number that counts up once on entry. Deliberately not interactive —
/// the doc used to promise a "hover interaction" that the widget no longer
/// has, and a stat card that lights up under the pointer would imply a click
/// target this app does not offer here.
class _HeroPill extends StatefulWidget {
  const _HeroPill({
    required this.isDark,
    required this.icon,
    required this.rawValue,
    required this.formatter,
    required this.label,
  });

  final bool isDark;
  final IconData icon;
  final int rawValue;
  final String Function(int) formatter;
  final String label;

  @override
  State<_HeroPill> createState() => _HeroPillState();
}

class _HeroPillState extends State<_HeroPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _counter;
  late final CurvedAnimation _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // `dramatic` (500 ms) is the app's ceiling for a one-shot transition, and
    // this count-up used to run 1200 ms — more than twice it. Every other
    // duration above the ceiling in this codebase is either a timer or a
    // *periodic* pulse (waveform, recording bar, overlay dot), where a long
    // period is the point; among one-shot entrance animations these two on
    // this screen were the only ones out of band. It matters more here than
    // it looks: while the count-up runs, the card does not show the number
    // smaller, it shows a *different* number — a total of 347 reads 12, then
    // 98, then 210. That is decoration instead of the information rather than
    // on top of it, so the time spent unreadable is the thing worth cutting.
    _counter = AnimationController(vsync: this, duration: WpMotion.dramatic);
    _curve = CurvedAnimation(parent: _counter, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `forward()` bakes in `duration` at call time, so the reduced-motion
    // duration must be set before the first (only) forward() call, not after.
    _counter.duration = WpMotion.durationFor(context, WpMotion.dramatic);
    if (!_started) {
      _started = true;
      _counter.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    // One stat, one node. The number and its caption were two unrelated
    // fragments in the semantics tree, so the value arrived without ever
    // saying what it counted ("1.234" … "Wörter").
    //
    // The hover highlight is gone: everywhere else in this app a surface that
    // lights up under the pointer is a surface you can click, and this pill
    // has never been tappable. It promised an interaction that does not exist.
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient accent strip at top
            Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: WpSpacing.sm),
              decoration: BoxDecoration(
                gradient: isDark
                    ? WpColorsDark.accentWarmGradient
                    : WpColorsLight.accentWarmGradient,
                borderRadius: WpRadius.borderFull,
              ),
            ),
            // Icon
            Row(
              children: [
                Icon(widget.icon, size: WpIconSize.sm, color: accent),
                const Spacer(),
              ],
            ),
            const SizedBox(height: WpSpacing.sm),
            // Animated number — counts up, but only for the eye. The node
            // states the final value from the first frame; announcing every
            // intermediate step would have a screen reader read the same
            // statistic dozens of times on its way to the real one.
            Semantics(
              label: widget.formatter(widget.rawValue),
              excludeSemantics: true,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, _) {
                  final current = (widget.rawValue * _curve.value).round();
                  return Text(
                    widget.formatter(current),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 2),
            // Label
            Text(
              widget.label,
              style: TextStyle(
                fontSize: WpTypography.caption,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row 2 — Activity chart (custom painter)
// ---------------------------------------------------------------------------

class _ActivityChartPanel extends StatefulWidget {
  const _ActivityChartPanel({required this.values, required this.isDark});

  final List<double> values;
  final bool isDark;

  @override
  State<_ActivityChartPanel> createState() => _ActivityChartPanelState();
}

class _ActivityChartPanelState extends State<_ActivityChartPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final CurvedAnimation _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Same ceiling as the hero pills above (see `_HeroPillState`). The bars
    // are less harmful than the count-up while they grow — a rising bar is a
    // readable convention and its shape *is* the information — but the two
    // animations start together on one screen, so they should also end
    // together instead of the chart finishing 400 ms before the numbers.
    _anim = AnimationController(vsync: this, duration: WpMotion.dramatic);
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `forward()` bakes in `duration` at call time, so the reduced-motion
    // duration must be set before the first (only) forward() call, not after.
    _anim.duration = WpMotion.durationFor(context, WpMotion.dramatic);
    if (!_started) {
      _started = true;
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.chartNoAxesColumn,
          title: l10n.analyticsRecordingActivity,
          isDark: isDark,
          trailing: Text(
            l10n.analyticsLast7Days,
            style: TextStyle(fontSize: WpTypography.caption, color: textMuted),
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        SizedBox(
          height: 140,
          child: AnimatedBuilder(
            animation: _curve,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _BarChartPainter(
                values: widget.values,
                labels: _activityDayLabels(l10n),
                barColor: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                // Same accent token, faded — was a hand-picked hex pair that
                // had drifted from the real accent (#3CCBE6 / #06678A).
                barColorEnd:
                    (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                        .withValues(alpha: 0.65),
                gridColor: isDark
                    ? WpColorsDark.borderSubtle
                    : WpColorsLight.borderSubtle,
                labelColor: isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
                // CustomPainter TextPainter bypasses widget font inheritance.
                // Pass fontFamily explicitly so labels render with the correct
                // typeface in tests and on all platforms.
                labelFontFamily: Theme.of(
                  context,
                ).textTheme.labelSmall?.fontFamily,
                animationValue: _curve.value,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.labels,
    required this.barColor,
    required this.barColorEnd,
    required this.gridColor,
    required this.labelColor,
    this.labelFontFamily,
    this.animationValue = 1.0,
  });

  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final Color barColorEnd;
  final Color gridColor;
  final Color labelColor;
  final String? labelFontFamily;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.reduce(math.max);
    if (maxVal == 0) return;

    const labelHeight = 20.0;
    const topPad = 4.0;
    final chartH = size.height - labelHeight - topPad;
    final barCount = values.length;
    final barWidth = (size.width / barCount) * 0.50;
    final gap = (size.width - barWidth * barCount) / (barCount + 1);

    // Grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Bars
    for (var i = 0; i < barCount; i++) {
      final fraction = (values[i] / maxVal) * animationValue;
      final barH = chartH * fraction;
      final x = gap + i * (barWidth + gap);
      final y = topPad + chartH - barH;
      final radius = barWidth / 2;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, y, barWidth, barH),
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      );

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [barColor, barColorEnd],
        ).createShader(Rect.fromLTWH(x, y, barWidth, barH));

      canvas.drawRRect(rect, paint);

      // Day label
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: WpTypography.micro,
            color: labelColor,
            fontFamily: labelFontFamily,
          ),
        ),
        // Intentionally LTR: numeric axis labels (dates, counts) are always
        // left-to-right regardless of app locale, including RTL languages
        // like Hebrew.  Do NOT change this to TextDirection.rtl.
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x + (barWidth - tp.width) / 2, topPad + chartH + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values ||
      old.barColor != barColor ||
      old.barColorEnd != barColorEnd ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor ||
      old.labelFontFamily != labelFontFamily ||
      old.animationValue != animationValue;
}

// ---------------------------------------------------------------------------
// Row 2 — Model usage
// ---------------------------------------------------------------------------

class _ModelUsagePanel extends StatelessWidget {
  const _ModelUsagePanel({required this.models, required this.isDark});

  final List<_ModelUsage> models;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.brain,
          title: l10n.analyticsModelUsage,
          isDark: isDark,
        ),
        const SizedBox(height: WpSpacing.md),
        if (models.isEmpty)
          Text(
            '—',
            style: TextStyle(
              fontSize: WpTypography.small,
              color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
            ),
          )
        else
          ...models.map((m) => _ModelUsageBar(model: m, isDark: isDark)),
      ],
    );
  }
}

class _ModelUsageBar extends StatelessWidget {
  const _ModelUsageBar({required this.model, required this.isDark});

  final _ModelUsage model;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final trackColor = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

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
                '(${model.count})',
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: WpRadius.borderFull,
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: trackColor),
                  FractionallySizedBox(
                    widthFactor: model.fraction,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: isDark
                            ? WpColorsDark.accentWarmGradient
                            : WpColorsLight.accentWarmGradient,
                      ),
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
  const _DurationDistPanel({required this.buckets, required this.isDark});

  final List<_DurationBucket> buckets;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.timer,
          title: l10n.analyticsDurationDistribution,
          isDark: isDark,
        ),
        const SizedBox(height: WpSpacing.md),
        ...buckets.map((b) => _DurationBar(bucket: b, isDark: isDark)),
      ],
    );
  }
}

class _DurationBar extends StatelessWidget {
  const _DurationBar({required this.bucket, required this.isDark});

  final _DurationBucket bucket;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final barColor = isDark
        ? WpColorsDark.textMuted.withAlpha(40)
        : WpColorsLight.textMuted.withAlpha(30);
    final barGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

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
                    Container(color: barColor),
                    FractionallySizedBox(
                      widthFactor: bucket.fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: barGradient,
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
              '${bucket.count}',
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
  const _CostPanel({
    required this.localSavingsUsd,
    required this.cloudCostUsd,
    required this.isDark,
  });

  final double localSavingsUsd;
  final double cloudCostUsd;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final success = isDark ? WpColorsDark.success : WpColorsLight.success;
    final warning = isDark ? WpColorsDark.warning : WpColorsLight.warning;
    final l10n = L10n.of(context);

    final savingsStr = '\$${localSavingsUsd.toStringAsFixed(2)}';
    final costStr = '\$${cloudCostUsd.toStringAsFixed(2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          icon: LucideIcons.piggyBank,
          title: l10n.analyticsCostSavings,
          isDark: isDark,
        ),
        const SizedBox(height: WpSpacing.lg),

        // Local savings
        _CostRow(
          isDark: isDark,
          icon: LucideIcons.shieldCheck,
          iconColor: success,
          title: l10n.analyticsLocalSavings,
          value: l10n.analyticsSavedAmount(savingsStr),
          valueColor: success,
        ),
        const SizedBox(height: WpSpacing.sm),

        // Cloud cost
        _CostRow(
          isDark: isDark,
          icon: LucideIcons.cloud,
          iconColor: warning,
          title: l10n.analyticsCloudCost,
          value: l10n.analyticsSpentAmount(costStr),
          valueColor: warning,
        ),
      ],
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.valueColor,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    return Row(
      children: [
        Icon(icon, size: WpIconSize.sm, color: iconColor),
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
            color: valueColor,
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
  const _PeriodSelector({required this.isDark});

  final bool isDark;

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
              isActive: i == selectedIndex,
              isDark: isDark,
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
  const _ResetRow({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_ResetRow> createState() => _ResetRowState();
}

class _ResetRowState extends ConsumerState<_ResetRow> {
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);

    return Row(
      children: [
        const Spacer(),
        // Reset button
        // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
        WpButton(
          label: l10n.analyticsReset,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.danger,
          size: WpButtonSize.dense,
          icon: LucideIcons.trash2,
          onPressed: () => _confirmReset(context, isDark),
        ),
      ],
    );
  }

  void _confirmReset(BuildContext context, bool isDark) {
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
        await db.resetDailyStats();
        ref.invalidate(analyticsProvider);
        if (context.mounted) {
          WpToast.show(
            context,
            message: L10n.of(context).analyticsResetTitle,
            type: WpToastType.success,
          );
        }
      }
    });
  }
}
