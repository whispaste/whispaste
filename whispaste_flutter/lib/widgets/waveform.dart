import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';

/// Real-time waveform visualization — premium bar-style audio level display.
///
/// Renders a series of vertical bars that react to the current [audioLevel].
/// Bars animate smoothly between levels with staggered heights for visual
/// interest. Suitable for recording overlays, FAB decorations, or inline use.
class WpWaveform extends StatefulWidget {
  const WpWaveform({
    super.key,
    required this.audioLevel,
    this.isActive = true,
    this.barCount = 24,
    this.barWidth = 3.0,
    this.barSpacing = 2.0,
    this.height = 48.0,
    this.color,
    this.inactiveColor,
  });

  /// Current audio level, 0.0 (silence) to 1.0 (peak).
  final double audioLevel;

  /// Whether the waveform is actively animating. When false, bars drop to
  /// a flat idle line.
  final bool isActive;

  /// Number of vertical bars to render.
  final int barCount;

  /// Width of each bar in logical pixels.
  final double barWidth;

  /// Gap between bars.
  final double barSpacing;

  /// Total widget height.
  final double height;

  /// Active bar color. Defaults to theme accent.
  final Color? color;

  /// Idle bar color. Defaults to a muted variant.
  final Color? inactiveColor;

  @override
  State<WpWaveform> createState() => _WpWaveformState();
}

class _WpWaveformState extends State<WpWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Each bar gets a persistent random offset for organic feel.
  late final List<double> _offsets;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(42); // deterministic seed for consistency
    _offsets = List.generate(widget.barCount, (_) => rng.nextDouble());

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(WpWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor =
        widget.color ?? (isDark ? WpColorsDark.accent : WpColorsLight.accent);
    final idleColor = widget.inactiveColor ??
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(
            widget.barCount * (widget.barWidth + widget.barSpacing) -
                widget.barSpacing,
            widget.height,
          ),
          painter: _WaveformPainter(
            audioLevel: widget.isActive ? widget.audioLevel : 0.0,
            barCount: widget.barCount,
            barWidth: widget.barWidth,
            barSpacing: widget.barSpacing,
            activeColor: activeColor,
            idleColor: idleColor,
            offsets: _offsets,
            tick: _controller.value,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.audioLevel,
    required this.barCount,
    required this.barWidth,
    required this.barSpacing,
    required this.activeColor,
    required this.idleColor,
    required this.offsets,
    required this.tick,
  });

  final double audioLevel;
  final int barCount;
  final double barWidth;
  final double barSpacing;
  final Color activeColor;
  final Color idleColor;
  final List<double> offsets;
  final double tick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = barCount / 2.0;
    const minBarHeight = 3.0;

    for (int i = 0; i < barCount; i++) {
      // Distance from center (0..1) — bars taper toward edges
      final distFromCenter = (i - center).abs() / center;
      final taper = 1.0 - (distFromCenter * 0.6);

      // Per-bar organic variation using offset + tick
      final wave =
          math.sin((offsets[i] + tick) * math.pi * 2) * 0.15 + 0.85;

      // Compute bar height — clamp between min and full height
      final level = (audioLevel * taper * wave).clamp(0.0, 1.0);
      final barHeight =
          minBarHeight + (size.height - minBarHeight) * level;

      // Interpolate color based on level
      paint.color = Color.lerp(idleColor, activeColor, level) ?? activeColor;

      // Draw bar centered vertically
      final x = i * (barWidth + barSpacing);
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      audioLevel != oldDelegate.audioLevel || tick != oldDelegate.tick;
}

/// Compact waveform badge — small inline visualization for status indicators.
///
/// Renders a tiny waveform suitable for embedding in chips, status bars, or
/// list items. Uses fewer bars and smaller dimensions.
class WpWaveformBadge extends StatelessWidget {
  const WpWaveformBadge({
    super.key,
    required this.audioLevel,
    this.isActive = true,
    this.color,
  });

  final double audioLevel;
  final bool isActive;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return WpWaveform(
      audioLevel: audioLevel,
      isActive: isActive,
      barCount: 12,
      barWidth: 2.0,
      barSpacing: 1.5,
      height: 20.0,
      color: color,
    );
  }
}
