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
          WpSection(
            title: l10n.analyticsOverview,
            subtitle: l10n.analyticsOverviewSubtitle,
            padding: EdgeInsets.zero,
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

          // ── Row 4: Period selector + Reset ─────────────────────
          _PeriodAndResetRow(isDark: isDark),

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
                  fontSize: 13,
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

/// Pill-shaped stat block: flat, subtle border, gradient accent strip at top,
/// animated count-up number, and hover interaction.
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
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _counter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _curve = CurvedAnimation(parent: _counter, curve: Curves.easeOutCubic);
    _counter.forward();
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _hovered
              ? (isDark ? WpColorsDark.hover : WpColorsLight.hover)
              : Colors.transparent,
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
            // Animated number
            AnimatedBuilder(
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
            const SizedBox(height: 2),
            // Label
            Text(
              widget.label,
              style: TextStyle(fontSize: 11, color: textSecondary),
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

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
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
            style: TextStyle(fontSize: 11, color: textMuted),
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
                barColorEnd: isDark
                    ? const Color(0xFF0891B2)
                    : const Color(0xFF06B6D4),
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
            fontSize: 10,
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
              fontSize: 12,
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
                  style: TextStyle(fontSize: 12, color: textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(model.fraction * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                '(${model.count})',
                style: TextStyle(fontSize: 11, color: textMuted),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              bucket.label,
              style: TextStyle(fontSize: 11, color: textPrimary),
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
            width: 32,
            child: Text(
              '${bucket.count}',
              style: TextStyle(fontSize: 11, color: textMuted),
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
            style: TextStyle(fontSize: 12, color: textPrimary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Row 4 — Period selector + Reset
// ---------------------------------------------------------------------------

class _PeriodAndResetRow extends ConsumerStatefulWidget {
  const _PeriodAndResetRow({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_PeriodAndResetRow> createState() => _PeriodAndResetRowState();
}

class _PeriodAndResetRowState extends ConsumerState<_PeriodAndResetRow> {
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final borderDefault = isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;
    final periods = [
      l10n.analyticsPeriod7d,
      l10n.analyticsPeriod30d,
      l10n.analyticsPeriod90d,
      l10n.analyticsPeriodAll,
    ];

    final currentPeriod = ref.watch(analyticsPeriodProvider);
    final selectedIndex = AnalyticsPeriod.values.indexOf(currentPeriod);

    return Row(
      children: [
        // Period chips
        Expanded(
          child: Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: List.generate(periods.length, (i) {
              final selected = i == selectedIndex;
              return GestureDetector(
                onTap: () => ref
                    .read(analyticsPeriodProvider.notifier)
                    .setPeriod(AnalyticsPeriod.values[i]),
                child: AnimatedContainer(
                  duration: WpMotion.normal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.sm,
                    vertical: WpSpacing.xxs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? accent.withAlpha(25) : Colors.transparent,
                    borderRadius: WpRadius.borderFull,
                    border: Border.all(
                      color: selected ? accent : borderDefault,
                    ),
                  ),
                  child: Text(
                    periods[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: selected ? accent : textSecondary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // Reset button
        OutlinedButton.icon(
          onPressed: () => _confirmReset(context, isDark),
          icon: const Icon(LucideIcons.trash2, size: WpIconSize.xs),
          label: Text(l10n.analyticsReset),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? WpColorsDark.error : WpColorsLight.error,
            side: BorderSide(
              color: (isDark ? WpColorsDark.error : WpColorsLight.error)
                  .withAlpha(80),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            textStyle: const TextStyle(fontSize: 12),
            shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
          ),
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
