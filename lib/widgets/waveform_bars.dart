import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Scrolling waveform bars — visualizes a rolling history of audio levels.
///
/// Renders [barCount] vertical bars from a circular buffer of audio samples.
/// New levels push in from the right; old ones shift left. Each bar animates
/// its height independently via [AnimatedContainer] for a smooth, premium feel.
///
/// Complements [WpWaveform] (real-time reactive visualizer). Use this widget
/// for recording overlays where a scrolling level history is desired.
class WpWaveformBars extends StatelessWidget {
  const WpWaveformBars({
    super.key,
    required this.levels,
    this.barCount = 20,
    this.height = 40,
    this.barWidth = 3,
    this.barSpacing = 2,
    this.isPaused = false,
    this.isActive = true,
  });

  /// Current audio levels buffer (0.0–1.0 each), length ≤ [barCount].
  /// The last element is the most recent sample (displayed rightmost).
  final List<double> levels;

  /// Number of bars to display.
  final int barCount;

  /// Total widget height in logical pixels.
  final double height;

  /// Width of each bar in logical pixels.
  final double barWidth;

  /// Gap between bars (each bar gets half on each side).
  final double barSpacing;

  /// When true, all bars fade to 40 % opacity (recording paused).
  final bool isPaused;

  /// When false, all bars render at minimum height with muted color (idle).
  final bool isActive;

  static const double _minBarHeight = 4;
  static const double _brightThreshold = 0.30;

  /// Apply sqrt-boost for visual impact, capped at 1.0.
  static double _boostedLevel(double raw) =>
      (math.sqrt(raw.clamp(0.0, 1.0)) * 1.5).clamp(0.0, 1.0);

  /// Resolve the level for bar [index] from the right-padded buffer.
  double _levelAt(int index, List<double> padded) =>
      isActive ? _boostedLevel(padded[index]) : 0.0;

  double _barHeight(int index, List<double> padded) {
    if (!isActive) return _minBarHeight;
    return math.max(_minBarHeight, _levelAt(index, padded) * height);
  }

  Color _barColor(
    int index,
    List<double> padded, {
    required Color accent,
    required Color muted,
  }) {
    if (!isActive) return muted;
    final level = _levelAt(index, padded);
    return level > _brightThreshold
        ? accent.withValues(alpha: 0.85)
        : muted.withValues(alpha: 0.5);
  }

  /// Right-align [levels] into a fixed-length buffer of [barCount] zeros.
  List<double> _paddedLevels() {
    final padded = List<double>.filled(barCount, 0.0);
    if (levels.isEmpty) return padded;
    final count = levels.length.clamp(0, barCount);
    final srcStart = levels.length - count;
    final dstStart = barCount - count;
    for (var i = 0; i < count; i++) {
      padded[dstStart + i] = levels[srcStart + i];
    }
    return padded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final muted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final padded = _paddedLevels();

    Widget bars = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < barCount; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: barSpacing / 2),
            child: AnimatedContainer(
              duration: WpMotion.fast,
              curve: WpMotion.defaultCurve,
              width: barWidth,
              height: _barHeight(i, padded),
              decoration: BoxDecoration(
                color: _barColor(i, padded, accent: accent, muted: muted),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
          ),
      ],
    );

    // Fade when paused.
    if (isPaused) {
      bars = AnimatedOpacity(
        opacity: 0.4,
        duration: WpMotion.smooth,
        curve: WpMotion.defaultCurve,
        child: bars,
      );
    }

    return SizedBox(height: height, child: bars);
  }
}
