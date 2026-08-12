/// Regression test for the release-out bug (2026-08-12 live report): "beim
/// Wechsel von recording zu transcribing stoppt die Wellenform abrupt statt
/// sanft auszuklingen" — most visible on the mini overlay, where the waveform
/// is the only moving content.
///
/// Two pieces of machinery are supposed to cooperate here and did not:
///
///  1. [FloatingOverlayService] keeps the waveform timer alive for
///     `releaseOutDurationMs` (= [OverlayDesignSpec.waveformReleaseOutMs],
///     300 ms) after `recording → transcribing` and feeds the pipeline
///     `pushSample(0.0, …)`, so the bars decay toward the rest floor instead
///     of freezing at the snapshot moment.
///  2. [WpFloatingOverlayView] crossfades the *content* between the two
///     states. The live bars only reach the canvas through the outgoing
///     (recording) crossfade layer — [WpFloatingOverlayView.painterFor] gates
///     `waveformBars` on the painted snapshot's own state, and the steady
///     transcribing painter draws the flat [OverlayDesignSpec.waveformRestLevel]
///     frame.
///
/// The crossfade ran for `stateTransitionDuration` (150 ms) — only half the
/// release-out window. At t = 150 ms the outgoing layer disappeared and the
/// flat rest frame took over while the service was still feeding decaying
/// samples: the decay was cut in half and ended on a visible step, which is
/// the "abrupt stop" the user reported.
///
/// Both ends of the window are asserted here: motion must survive the whole
/// release-out, and the frame that stays on screen afterwards must be the
/// resting one — never a frozen mid-decay waveform (the pipeline's scrolling
/// history still holds loud speech in its older bars when the timer stops,
/// so freezing it would leave a loud waveform standing for the entire
/// transcription).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

/// Waveform animation tick of the service loop (~30 fps).
const _tick = Duration(milliseconds: 33);

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  OverlaySizeVariant size = OverlaySizeVariant.mini,
}) => FloatingOverlaySnapshot(
  visible: true,
  state: state,
  size: size,
  label: state == OverlayVisualState.recording ? 'Recording' : 'Transcribing…',
  elapsed: state == OverlayVisualState.recording ? '0:07' : '',
);

/// Uniform bar snapshot at [level] — stands in for one pipeline snapshot.
List<double> _bars(double level) =>
    List<double>.filled(OverlayDesignSpec.waveform.barCount, level);

Widget _wrap(Widget child) => MediaQuery(
  // Animations ON: the crossfade under test only runs outside reduced motion.
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

/// `animate: false` keeps the perpetual dot-pulse/liquid tickers out of the
/// test while leaving the state-transition crossfade fully live.
Widget _view(OverlayVisualState state, List<double> bars) => _wrap(
  WpFloatingOverlayView(
    snapshot: _snap(state),
    waveformBars: bars,
    animate: false,
  ),
);

List<WpOverlayPainter> _painters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<WpOverlayPainter>()
    .toList();

/// The live waveform levels actually reaching the canvas this frame — empty
/// when every painted layer draws the static rest waveform instead.
List<double> _paintedWaveform(WidgetTester tester) {
  for (final painter in _painters(tester)) {
    if (painter.waveformBars.isNotEmpty) return painter.waveformBars;
  }
  return const [];
}

void main() {
  testWidgets(
    'the decaying waveform stays on screen for the whole release-out window, '
    'not just for the 150 ms content crossfade',
    (tester) async {
      await tester.pumpWidget(_view(OverlayVisualState.recording, _bars(0.9)));
      // Let the appear spring settle.
      await tester.pump(const Duration(milliseconds: 350));
      expect(_paintedWaveform(tester), _bars(0.9));

      // recording → transcribing: from here the service keeps ticking the
      // pipeline with silence for waveformReleaseOutMs, so every frame in
      // that window carries a slightly quieter bar set.
      var level = 0.9;
      var elapsedMs = 0;
      List<double> current = _bars(level);
      await tester.pumpWidget(_view(OverlayVisualState.transcribing, current));

      const windowMs = OverlayDesignSpec.waveformReleaseOutMs;
      // Sample the last frame before the release-out window closes.
      while (elapsedMs + _tick.inMilliseconds < windowMs) {
        level *= 0.9;
        current = _bars(level);
        await tester.pumpWidget(
          _view(OverlayVisualState.transcribing, current),
        );
        await tester.pump(_tick);
        elapsedMs += _tick.inMilliseconds;
      }

      expect(
        elapsedMs,
        greaterThan(
          OverlayDesignSpec.arc.stateTransitionDuration.inMilliseconds,
        ),
        reason: 'the sampled frame must sit past the generic crossfade',
      );
      // BUG (pre-fix): the crossfade ended at 150 ms, so from then on only the
      // steady transcribing painter remained — with `waveformBars: const []`,
      // i.e. a flat rest waveform. The remaining ~150 ms of decay the service
      // was still producing never reached the canvas.
      expect(
        _paintedWaveform(tester),
        current,
        reason:
            'the live (decaying) bars must still be painted at '
            '${elapsedMs}ms — the full release-out window is '
            '${windowMs}ms',
      );
    },
  );

  testWidgets(
    'once the release-out window has passed the overlay rests on the static '
    'transcribing frame — no frozen mid-decay waveform',
    (tester) async {
      await tester.pumpWidget(_view(OverlayVisualState.recording, _bars(0.9)));
      await tester.pump(const Duration(milliseconds: 350));

      // The service stops its timer at the end of the window, so the last
      // pushed bars simply stay — deliberately still loud here (the pipeline's
      // scrolling history only replaces ~9 of its 22 bars during the window).
      final frozen = _bars(0.8);
      await tester.pumpWidget(_view(OverlayVisualState.transcribing, frozen));
      await tester.pump(
        const Duration(
          milliseconds: OverlayDesignSpec.waveformReleaseOutMs + 50,
        ),
      );
      // Drain the setState that clears the outgoing crossfade layer.
      await tester.pump();

      final painters = _painters(tester);
      expect(
        painters,
        hasLength(1),
        reason: 'the crossfade must be finished after the release-out window',
      );
      expect(painters.single.state, OverlayDesignState.transcribing);
      expect(
        painters.single.waveformBars,
        isEmpty,
        reason:
            'after the window the overlay must settle on the resting '
            'transcribing waveform, not freeze the last loud bar set',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
