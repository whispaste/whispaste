/// Thin animated bar at the top of the content panel.
///
/// Pulses red during recording, amber during transcribing, hidden otherwise.
/// 3 px tall — visible but non-intrusive, signalling active recording at a
/// glance without competing with content.
library;

import 'package:flutter/material.dart';

import '../core/recording/recording_state.dart';
import '../core/theme/tokens.dart';

/// Recording indicator bar — sits above page content inside the content panel.
class WpRecordingIndicatorBar extends StatefulWidget {
  const WpRecordingIndicatorBar({super.key, required this.phase});

  final RecordingPhase phase;

  @override
  State<WpRecordingIndicatorBar> createState() =>
      _WpRecordingIndicatorBarState();
}

class _WpRecordingIndicatorBarState extends State<WpRecordingIndicatorBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _syncPulse();
  }

  @override
  void didUpdateWidget(WpRecordingIndicatorBar old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase) _syncPulse();
  }

  void _syncPulse() {
    if (widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing ||
        widget.phase == RecordingPhase.processing) {
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
    final isActive = widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing ||
        widget.phase == RecordingPhase.processing;

    final color = widget.phase == RecordingPhase.recording
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return AnimatedContainer(
      duration: WpMotion.normal,
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
