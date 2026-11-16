/// The waveform styles other than bars (bars: `WpLevelHistoryBars`).
///
/// Every style reads the same level history (oldest first, newest last) and
/// moves only when a new level arrives, so it draws in the overlay's existing
/// level tick and needs no extra animation ticker. That also keeps them calm
/// under reduced motion: nothing moves except in answer to the voice, exactly
/// like the bars.
///
/// All styles follow the bars' construction: filled shapes mirrored on the
/// centre line, no outlines, lit by the same gradient (bright core at the
/// centre line, shaded tips). A stroke around a filled shape reads as a heavy
/// frame, most of all in a black wave colour, so nothing here strokes.
///
/// History styles (line, dots, ribbons) fade from the oldest sample to the
/// newest, so the eye reads the right edge as "now" and the voice as flowing
/// in from there. The pulse shows the same history as soft stages that carry
/// each level outward from the centre.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_customization.dart';
import '../../core/theme/overlay_design_spec.dart';

/// Paints the line, dot, ribbon and pulse waveforms into a wave zone.
abstract final class WpOverlayWaveStyles {
  /// Paints [style] for [levels] (each 0–1) inside [zone] in [accent].
  /// [OverlayWaveStyle.bars] paints nothing here.
  static void paint(
    Canvas canvas,
    Rect zone,
    List<double> levels,
    OverlayWaveStyle style, {
    required Color accent,
  }) {
    if (levels.isEmpty || zone.width <= 0 || zone.height <= 0) return;
    switch (style) {
      case OverlayWaveStyle.bars:
        return;
      case OverlayWaveStyle.line:
        _line(canvas, zone, levels, accent);
      case OverlayWaveStyle.dots:
        _dots(canvas, zone, levels, accent);
      case OverlayWaveStyle.ribbon:
        _ribbon(canvas, zone, levels, accent);
      case OverlayWaveStyle.pulse:
        _pulse(canvas, zone, levels, accent);
    }
  }

  /// Opacity of the oldest sample of a history style; the newest is opaque.
  static const double _historyFadeFloor = 0.55;

  /// Share of the zone at the old (left) end over which history styles taper
  /// into the centre line, so the wave starts softly instead of cut off.
  static const double _taperShare = 0.18;

  /// Half-thickness of the line at silence, in logical pixels.
  static const double _lineRestHalf = 0.75;

  /// Opacity of the line at the top and bottom of the zone. The body dissolves
  /// towards its peaks instead of ending in a hard dark edge.
  static const double _lineTipAlpha = 0.42;

  /// The bars' light: tips shaded, a bright core on the centre line. [tipAlpha]
  /// lets a large closed shape dissolve towards the zone's edges, where a row
  /// of separate bars needs no such help.
  static Shader _energyShader(
    Rect zone,
    Color accent, {
    double coreLight = OverlayDesignSpec.waveformCoreMutedLightFraction,
    double tipAlpha = 1,
  }) {
    final tip = Color.lerp(
      accent,
      const Color(0xFF000000),
      OverlayDesignSpec.waveformTipShadeFraction,
    )!;
    final faded = tip.withValues(alpha: tip.a * tipAlpha);
    return ui.Gradient.linear(
      zone.topCenter,
      zone.bottomCenter,
      [faded, Color.lerp(accent, const Color(0xFFFFFFFF), coreLight)!, faded],
      const [0.0, 0.5, 1.0],
    );
  }

  /// Runs [draw] in one layer that fades from the old end (left) to full at
  /// "now" (right). A closed shape cannot carry this light and that fade in
  /// one shader, so it costs one zone-sized layer per paint, never one per
  /// shape.
  static void _fadingHistory(Canvas canvas, Rect zone, VoidCallback draw) {
    final bounds = zone.inflate(1);
    canvas.saveLayer(bounds, Paint());
    draw();
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(zone.centerLeft, zone.centerRight, [
          const Color(0xFFFFFFFF).withValues(alpha: _historyFadeFloor),
          const Color(0xFFFFFFFF),
        ])
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
  }

  /// 0 at the old end, rising smoothly to 1 after [_taperShare] of the zone.
  static double _oldEndTaper(double t) {
    final u = (t / _taperShare).clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  /// [v] as a level; NaN counts as silence.
  static double _unit(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);

  /// [levels] with a light three-tap smoothing, so a closed shape follows the
  /// words instead of every jagged sample. Separate bars need no such help.
  static List<double> _smoothed(List<double> levels) {
    final last = levels.length - 1;
    return [
      for (var i = 0; i <= last; i++)
        _unit(levels[math.max(0, i - 1)]) * 0.25 +
            _unit(levels[i]) * 0.5 +
            _unit(levels[math.min(last, i + 1)]) * 0.25,
    ];
  }

  /// The smooth curve through [top] and back along its mirror on [axis], as
  /// one closed shape.
  static Path _mirroredBody(List<Offset> top, double axis) {
    final mirrored = [
      for (var i = top.length - 1; i >= 0; i--)
        Offset(top[i].dx, 2 * axis - top[i].dy),
    ];
    return appendSmoothCurve(
      appendSmoothCurve(Path(), top, start: true),
      mirrored,
    )..close();
  }

  /// One filled, mirrored silhouette of the voice. Silence leaves a thin
  /// thread on the centre line; the old end tapers to a point and "now" closes
  /// in a rounded tip, so there is no cut edge anywhere.
  static void _line(Canvas canvas, Rect zone, List<double> levels, Color c) {
    final cy = zone.center.dy;
    final half = zone.height / 2;
    final count = levels.length;
    final pitch = zone.width / count;
    final smooth = _smoothed(levels);
    final top = <Offset>[
      for (var i = 0; i < count; i++)
        Offset(
          zone.left + (i + 0.5) * pitch,
          cy -
              math.max(_lineRestHalf, smooth[i] * half) *
                  _oldEndTaper(count <= 1 ? 1 : i / (count - 1)),
        ),
      Offset(zone.right, cy),
    ];
    final body = _mirroredBody(top, cy);
    final fill = Paint()
      ..shader = _energyShader(zone, c, tipAlpha: _lineTipAlpha)
      ..isAntiAlias = true;
    _fadingHistory(canvas, zone, () => canvas.drawPath(body, fill));
  }

  /// A halftone of the bars: one dot column per bar slot on a fixed grid. The
  /// dots stay in place and only grow, so loud speech fills a column from the
  /// centre line outward without anything jumping; silence is a calm dotted
  /// line. Outer rows stay smaller, like the bars' shaded tips.
  static void _dots(Canvas canvas, Rect zone, List<double> levels, Color c) {
    final cy = zone.center.dy;
    final half = zone.height / 2;
    final count = levels.length;
    final slot = zone.width / count;
    final rows = half >= _dotTwoRowsMinHalf ? 2 : 1;
    final dot = math.min(
      slot * OverlayDesignSpec.waveformBarFillFactor / 2,
      half / (1 + rows * _dotRowPitch),
    );
    final pitch = (half - dot) / rows;
    final muted = Paint()
      ..shader = _energyShader(zone, c)
      ..isAntiAlias = true;
    final hot = Paint()
      ..shader = _energyShader(
        zone,
        c,
        coreLight: OverlayDesignSpec.waveformCoreActiveLightFraction,
      )
      ..isAntiAlias = true;
    for (var i = 0; i < count; i++) {
      final t = count <= 1 ? 1.0 : i / (count - 1);
      final reach = _unit(levels[i]) * half * _oldEndTaper(t);
      final paint = i == count - 1 ? hot : muted;
      paint.color = const Color(
        0xFFFFFFFF,
      ).withValues(alpha: _historyFadeFloor + (1 - _historyFadeFloor) * t);
      final x = zone.left + (i + 0.5) * slot;
      final swell = (reach / pitch).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x, cy),
        dot * (_dotRestShare + (1 - _dotRestShare) * swell),
        paint,
      );
      for (var row = 1; row <= rows; row++) {
        final grown = ((reach - (row - 0.5) * pitch) / pitch).clamp(0.0, 1.0);
        if (grown <= 0) break;
        final full = dot * (1 - _dotRowShrink * row);
        final r = full * (_dotRestShare + (1 - _dotRestShare) * grown);
        canvas.drawCircle(Offset(x, cy - row * pitch), r, paint);
        canvas.drawCircle(Offset(x, cy + row * pitch), r, paint);
      }
    }
  }

  /// Size of the smallest dot relative to a full one: a silent dot on the
  /// centre line, or the first moment of an outer dot. Anything smaller reads
  /// as specks.
  static const double _dotRestShare = 0.45;

  /// How much smaller each row away from the centre line is.
  static const double _dotRowShrink = 0.12;

  /// Distance between two rows, in full dot radii.
  static const double _dotRowPitch = 2.15;

  /// Half-height of the zone from which two rows per side fit legibly.
  static const double _dotTwoRowsMinHalf = 9;

  /// Three translucent bands, each a mirrored shape whose edge undulates at
  /// its own rhythm. Their edges cross, and where they overlap the colour
  /// deepens, so the ribbons are lit from the middle by their own layers and
  /// need no outline. A band only narrows to its waist, never to nothing, so a
  /// loud word is never pinched off. Each band's height follows the level
  /// history at its position: loud speech swells the ribbons at the right edge
  /// and the swell travels left as the voice flows in. The bands meet at both
  /// ends of the zone.
  static void _ribbon(Canvas canvas, Rect zone, List<double> levels, Color c) {
    final cy = zone.center.dy;
    final half = zone.height / 2;
    final steps = math.max(32, levels.length * _ribbonStepsPerSample);
    final smooth = _smoothed(levels);
    final heights = [
      for (var k = 0; k <= steps; k++)
        half *
            math.max(
              _ribbonRest,
              levelAt(smooth, k / steps * (levels.length - 1)),
            ) *
            math.pow(math.sin(math.pi * k / steps), 0.7),
    ];
    final fill = Paint()
      ..shader = _energyShader(zone, c, tipAlpha: _ribbonTipAlpha)
      ..isAntiAlias = true;
    _fadingHistory(canvas, zone, () {
      for (final band in _ribbonBands) {
        final top = <Offset>[
          for (var k = 0; k <= steps; k++)
            () {
              final phase = 2 * math.pi * band.cycles * k / steps + band.offset;
              final swing = 0.5 + 0.5 * math.sin(phase);
              return Offset(
                zone.left + k / steps * zone.width,
                cy -
                    heights[k] *
                        band.weight *
                        (_ribbonWaist + (1 - _ribbonWaist) * swing),
              );
            }(),
        ];
        fill.color = const Color(0xFFFFFFFF).withValues(alpha: band.alpha);
        canvas.drawPath(_mirroredBody(top, cy), fill);
      }
    });
  }

  /// Ribbon height at silence, as a share of the zone: a faint breath.
  static const double _ribbonRest = 0.08;

  /// Curve points per level sample.
  static const int _ribbonStepsPerSample = 4;

  /// Narrowest share of its height a band undulates down to.
  static const double _ribbonWaist = 0.45;

  /// Opacity of the ribbons at the top and bottom of the zone.
  static const double _ribbonTipAlpha = 0.6;

  static const List<_RibbonBand> _ribbonBands = [
    _RibbonBand(cycles: 1.5, offset: 0, weight: 1, alpha: 0.52),
    _RibbonBand(cycles: 2.25, offset: 1.3, weight: 0.86, alpha: 0.46),
    _RibbonBand(cycles: 3, offset: 2.6, weight: 0.72, alpha: 0.4),
  ];

  /// A centre orb that swells with the newest level, inside soft filled stages
  /// that carry earlier levels outward: each stage holds the loudest level of
  /// a longer stretch of the recent voice, so a spoken word leaves the centre
  /// first and the edge last, and an outer stage can never fall inside an
  /// inner one. The stages overlap, so the colour falls off in steps with the
  /// outermost one faintest, and no stage has a line of its own. They widen
  /// into capsules that use the wave zone, so the pulse reads in a wide pill;
  /// silence gathers them around the orb.
  static void _pulse(Canvas canvas, Rect zone, List<double> levels, Color c) {
    final centre = zone.center;
    final rMax = zone.height / 2;
    final coreMin = rMax * _pulseCoreMin;
    final core =
        coreMin + (rMax * _pulseCoreMax - coreMin) * _unit(recentLevel(levels));
    final fill = Paint()
      ..shader = _energyShader(zone, c)
      ..isAntiAlias = true;
    final stages = _pulseStageAlphas.length;
    final newest = levels.length - 1;
    for (var k = stages; k >= 1; k--) {
      var level = 0.0;
      final oldest = math.max(0, newest - k * _pulseStageStep);
      for (var i = oldest; i <= newest; i++) {
        level = math.max(level, _unit(levels[i]));
      }
      final reach =
          k / stages * (_pulseRestReach + (1 - _pulseRestReach) * level);
      final stage = Rect.fromCenter(
        center: centre,
        width: 2 * core + (zone.width - 2 * core) * reach,
        height: 2 * core + (zone.height - 2 * core) * reach,
      );
      fill.color = const Color(
        0xFFFFFFFF,
      ).withValues(alpha: _pulseStageAlphas[k - 1]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(stage, Radius.circular(stage.height / 2)),
        fill,
      );
    }
    fill.color = const Color(0xFFFFFFFF);
    canvas.drawCircle(centre, core, fill);
  }

  static const double _pulseCoreMin = 0.26;
  static const double _pulseCoreMax = 0.62;

  /// Opacity of each stage, innermost first. They add up where they overlap.
  static const List<double> _pulseStageAlphas = [0.26, 0.18, 0.12, 0.08, 0.05];

  /// Share of a stage's full reach that remains at silence.
  static const double _pulseRestReach = 0.2;

  /// How many more samples of the recent voice each next stage looks back on.
  static const int _pulseStageStep = 2;

  /// Mean of the newest three levels, so the orb does not flicker.
  @visibleForTesting
  static double recentLevel(List<double> levels) {
    if (levels.isEmpty) return 0;
    final n = math.min(3, levels.length);
    var sum = 0.0;
    for (var i = levels.length - n; i < levels.length; i++) {
      sum += levels[i].clamp(0.0, 1.0);
    }
    return sum / n;
  }

  /// Linear level at fractional sample index [x].
  @visibleForTesting
  static double levelAt(List<double> levels, double x) {
    if (levels.isEmpty) return 0;
    final i = x.floor().clamp(0, levels.length - 1);
    final j = math.min(i + 1, levels.length - 1);
    final f = (x - i).clamp(0.0, 1.0);
    return (levels[i] + (levels[j] - levels[i]) * f).clamp(0.0, 1.0);
  }

  /// Appends a Catmull-Rom curve through [points] to [path] (moving to the
  /// first point when [start], else drawing a line to it) and returns [path].
  static Path appendSmoothCurve(
    Path path,
    List<Offset> points, {
    bool start = false,
  }) {
    if (points.isEmpty) return path;
    final first = points.first;
    start ? path.moveTo(first.dx, first.dy) : path.lineTo(first.dx, first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[math.min(points.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }
}

class _RibbonBand {
  const _RibbonBand({
    required this.cycles,
    required this.offset,
    required this.weight,
    required this.alpha,
  });

  /// Sine periods across the zone.
  final double cycles;

  /// Phase offset in radians, so the bands cross instead of stacking.
  final double offset;

  /// Height relative to the strongest band.
  final double weight;

  /// Opacity relative to the wave colour.
  final double alpha;
}
