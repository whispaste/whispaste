/// Deterministische Goldens für das Liquid-Glass-Verhalten:
///
/// - Bei `liquidMotion = 0` / `glassPhase = 0` (alle anderen Goldens) ist die
///   Kapsel exakt starr — die Parity-Goldens sind die Baseline.
/// - Hier wird EIN eingefrorener animierter Frame gelockt (Phase 0.3, volle
///   Motion, hoher Audio-Pegel): sichtbar gewölbte Silhouette + gedrifteter
///   Specular-Streak. Schützt die Wobble-/Drift-Geometrie gegen Regressions.
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  testWidgets('golden: liquid wobble + drift frame (phase 0.3, level 0.8)', (
    tester,
  ) async {
    const snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      isDark: false,
      label: 'Recording',
      elapsed: '1:30',
      progress: 0.4,
    );
    final windowSize = OverlayDesignSpec.windowSizeFor(snapshot.size);
    final bars = List<double>.generate(
      OverlayDesignSpec.waveform.barCount,
      (i) => (i % 7) / 7.0,
    );
    const key = ValueKey('liquid-frame');

    await tester.pumpWidget(
      Center(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: windowSize.width,
              height: windowSize.height,
              child: CustomPaint(
                size: windowSize,
                painter: FloatingOverlayView.painterFor(
                  snapshot: snapshot,
                  waveformBars: bars,
                  dotPulse: 1.0,
                  glassPhase: 0.3,
                  liquidMotion: 1.0,
                  liquidLevel: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/overlay/overlay_liquid_wobble_frame.png'),
    );
  });
}
