/// Thin animated bar at the top of the content panel.
///
/// Pulses red during recording, amber during transcribing, hidden otherwise.
/// 3 px tall — visible but non-intrusive, signalling active recording at a
/// glance without competing with content.
library;

import 'package:flutter/material.dart';

import '../core/recording/recording_state.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Recording indicator bar — sits above page content inside the content panel.
class WpRecordingIndicatorBar extends StatefulWidget {
  const WpRecordingIndicatorBar({super.key, required this.phase});

  final RecordingPhase phase;

  /// Returns the bar colour for [phase] and the current [isDark] setting.
  ///
  /// Recording → error token (red), transcribing → warning token (amber).
  /// Exposed `@visibleForTesting` so the colour-token mapping can be pinned
  /// without depending on the full widget/render pipeline.
  @visibleForTesting
  static Color colorFor(RecordingPhase phase, {required bool isDark}) {
    if (phase == RecordingPhase.recording) {
      return isDark ? WpColorsDark.error : WpColorsLight.error;
    }
    return isDark ? WpColorsDark.warning : WpColorsLight.warning;
  }

  @override
  State<WpRecordingIndicatorBar> createState() =>
      _WpRecordingIndicatorBarState();
}

class _WpRecordingIndicatorBarState extends State<WpRecordingIndicatorBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  static const _kPulseDuration = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: _kPulseDuration);
    _opacity = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _syncPulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route pulse duration through the reduced-motion guard.
    _pulse.duration = WpMotion.durationFor(context, _kPulseDuration);
  }

  @override
  void didUpdateWidget(WpRecordingIndicatorBar old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase) _syncPulse();
  }

  void _syncPulse() {
    if (widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive =
        widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = WpRecordingIndicatorBar.colorFor(
      widget.phase,
      isDark: isDark,
    );

    return AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      height: isActive ? 3.0 : 0.0,
      child: isActive
          ? AnimatedBuilder(
              animation: _opacity,
              builder: (context, _) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: _opacity.value * 0.8),
                        color.withValues(alpha: _opacity.value),
                        color.withValues(alpha: _opacity.value * 0.8),
                      ],
                    ),
                  ),
                );
              },
            )
          : const SizedBox.shrink(),
    );
  }
}
