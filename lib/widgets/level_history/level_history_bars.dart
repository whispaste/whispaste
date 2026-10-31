/// The one bar-history element of WhisPaste: the recording overlay's waveform
/// and the onboarding microphone test both paint through it.
///
/// Bars are mirrored capsules around the centre line, oldest on the left,
/// newest on the right. The newest bar is the "now" marker: it is drawn wider
/// with the hot core, so the eye finds the live edge without a second colour.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';

/// Pure bar-history helpers: a fixed-length list of levels in `[0, 1]`, newest
/// last.
abstract final class WpLevelHistory {
  /// A history of [count] silent bars.
  static List<double> zeros(int count) => List<double>.filled(count, 0.0);

  /// Appends [level] (clamped to `[0, 1]`, NaN counts as silence) and drops the
  /// oldest value, so the length never changes.
  static List<double> push(List<double> history, double level) {
    if (history.isEmpty) return const [];
    final clamped = level.isNaN ? 0.0 : level.clamp(0.0, 1.0);
    return [...history.sublist(1), clamped];
  }

  /// Index of the newest bar, the "now" marker, or -1 for an empty history.
  static int newestIndex(List<double> history) => history.length - 1;
}

/// Paints a level history into a zone. Stateless: the caller owns the history,
/// so the overlay and the onboarding view feed the same numbers.
abstract final class WpLevelHistoryBars {
  /// Paints one mirrored capsule per entry of [levels] into [zone].
  ///
  /// [highlightNewest] gives the newest bar the "now" treatment: the wider
  /// fill and the hot core, at [nowAlpha]. The other bars use [mutedAlpha].
  /// Colour comes only from [accent]; nothing here is an accent of its own,
  /// so the preset's ink and surface rules keep applying through the caller.
  static void paint(
    Canvas canvas,
    Rect zone,
    List<double> levels, {
    required Color accent,
    required double lineStrokeMin,
    double mutedAlpha = 1.0,
    double nowAlpha = 1.0,
    bool highlightNewest = true,
  }) {
    final count = levels.length;
    if (count == 0 || zone.width <= 0) return;
    final barW = zone.width / count;
    final tip = Color.lerp(
      accent,
      const Color(0xFF000000),
      OverlayDesignSpec.waveformTipShadeFraction,
    )!;
    Shader coreShader(double coreLight) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        tip,
        Color.lerp(accent, const Color(0xFFFFFFFF), coreLight)!,
        tip,
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(zone);
    final mutedPaint = Paint()
      ..shader = coreShader(OverlayDesignSpec.waveformCoreMutedLightFraction);
    final nowPaint = Paint()
      ..shader = coreShader(OverlayDesignSpec.waveformCoreActiveLightFraction);
    final newest = WpLevelHistory.newestIndex(levels);
    for (var i = 0; i < count; i++) {
      final now = highlightNewest && i == newest;
      final x = zone.left + i * barW + barW / 2;
      final wBar = _barWidth(barW, now, lineStrokeMin);
      final h = _barHeight(levels[i].clamp(0.0, 1.0), zone.height, wBar);
      final paint = now ? nowPaint : mutedPaint;
      paint.color = const Color(
        0xFFFFFFFF,
      ).withValues(alpha: now ? nowAlpha : mutedAlpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, zone.center.dy),
            width: wBar,
            height: h,
          ),
          Radius.circular(wBar / 2),
        ),
        paint,
      );
    }
  }

  static double _barWidth(double slot, bool now, double lineStrokeMin) {
    final fill = now
        ? OverlayDesignSpec.waveformActiveBarFillFactor
        : OverlayDesignSpec.waveformBarFillFactor;
    return lineStrokeMin > slot * fill ? lineStrokeMin : slot * fill;
  }

  /// Height floor: never below the bar's own width, so a resting bar stays a
  /// bead and a speaking bar a capsule.
  static double _barHeight(double level, double zoneHeight, double wBar) {
    final floor = OverlayDesignSpec.waveform.minBarHeightPx > wBar
        ? OverlayDesignSpec.waveform.minBarHeightPx
        : wBar;
    final scaled = level * zoneHeight;
    return floor > scaled ? floor : scaled;
  }
}

/// Widget host for [WpLevelHistoryBars]: a fixed-size box painted from [levels].
class WpLevelHistoryView extends StatelessWidget {
  const WpLevelHistoryView({
    super.key,
    required this.levels,
    required this.color,
    required this.width,
    required this.height,
    this.lineStrokeMin = 2.0,
  });

  /// One value per bar, oldest first, newest last.
  final List<double> levels;

  /// Accent of the bars (the preset's wave colour, or the onboarding amber).
  final Color color;
  final double width;
  final double height;
  final double lineStrokeMin;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: _LevelHistoryPainter(
      levels: levels,
      color: color,
      lineStrokeMin: lineStrokeMin,
    ),
  );
}

class _LevelHistoryPainter extends CustomPainter {
  const _LevelHistoryPainter({
    required this.levels,
    required this.color,
    required this.lineStrokeMin,
  });

  final List<double> levels;
  final Color color;
  final double lineStrokeMin;

  @override
  void paint(Canvas canvas, Size size) {
    WpLevelHistoryBars.paint(
      canvas,
      Offset.zero & size,
      levels,
      accent: color,
      lineStrokeMin: lineStrokeMin,
      mutedAlpha: OverlayDesignSpec.waveformMutedLineOpacity,
      nowAlpha: OverlayDesignSpec.waveformActiveOpacity,
    );
  }

  @override
  bool shouldRepaint(_LevelHistoryPainter old) =>
      old.color != color ||
      old.lineStrokeMin != lineStrokeMin ||
      !listEquals(old.levels, levels);
}
