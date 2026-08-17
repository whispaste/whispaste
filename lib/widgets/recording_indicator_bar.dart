/// Thin animated bar at the top of the content panel.
///
/// Pulses in the recording cyan while a recording or its transcription is in
/// flight, hidden otherwise. 3 px tall — visible but non-intrusive, signalling
/// an active recording at a glance without competing with content.
///
/// This is the main window's whole recording surface: the in-window FAB is
/// gone (`test/widgets/no_fab_regression_test.dart` keeps it gone) and the
/// floating overlay is a separate window with its own material. So the bar is
/// what Ticket 15 means by "the recording screen".
library;

import 'package:flutter/material.dart';

import '../core/recording/recording_state.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Recording indicator bar — sits above page content inside the content panel.
class WpRecordingIndicatorBar extends StatefulWidget {
  const WpRecordingIndicatorBar({super.key, required this.phase});

  final RecordingPhase phase;

  /// Returns the bar colour for [phase] — always the recording family.
  ///
  /// Both in-flight phases resolve to [WpColors.recordingAccent], whose one
  /// documented job is "a recording *or its transcription* is in flight".
  /// They used to be red and amber, which spent the two colours the Quiet
  /// Status Rule reserves for real failures and for not-yet-granted states on
  /// a bar that reports neither. The phase *detail* (recording vs.
  /// transcribing) is the status bar chip's job; this bar reports that
  /// something is running at all.
  ///
  /// Not folded into a constant: the method is the seam the colour mapping is
  /// pinned through, and a future phase that legitimately needs its own hue
  /// has somewhere to land.
  ///
  /// Deliberately *not* [WpColors.accent]: the generic accent means "you can
  /// act on this", and a state that the user cannot press would put a second
  /// job on it (*The Two-Accent-Two-Jobs Rule*).
  ///
  /// Exposed `@visibleForTesting` so the colour-token mapping can be pinned
  /// without depending on the full widget/render pipeline.
  @visibleForTesting
  static Color colorFor(RecordingPhase phase) {
    return WpColors.recordingAccent;
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
      // `AnimationController.repeat()` asserts its period is > 0; reduced
      // motion (`WpMotion.durationFor` in didChangeDependencies) sets
      // `_pulse.duration` to `Duration.zero`, which would violate that
      // assertion. A thrown exception here lands inside the ancestor
      // rebuild pass (didUpdateWidget, called from Element.updateChildren)
      // and aborts it partway through, desyncing the Element/RenderObject
      // child lists for everything built after this bar — so skip the
      // animation and land on the fully-lit static state instead, which is
      // what reduced motion should show anyway.
      if (_pulse.duration == Duration.zero) {
        _pulse.value = 1.0;
      } else {
        _pulse.repeat(reverse: true);
      }
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

    final color = WpRecordingIndicatorBar.colorFor(widget.phase);

    return AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      height: isActive ? 3.0 : 0.0,
      child: isActive
          ? AnimatedBuilder(
              animation: _opacity,
              builder: (context, _) {
                // Flat, not a gradient. The three-stop LinearGradient this
                // replaces faded the same hue out towards both ends, which is
                // a light falling on the bar — a second light source, three
                // pixels tall, over the one ambient the whole app stands on
                // (*The One-Atmosphere Rule*). The pulse alone carries the
                // "something is running" signal; the alpha is animated, the
                // hue is not, and nothing here paints a shape of its own.
                return ColoredBox(
                  color: color.withValues(alpha: _opacity.value),
                );
              },
            )
          : const SizedBox.shrink(),
    );
  }
}
