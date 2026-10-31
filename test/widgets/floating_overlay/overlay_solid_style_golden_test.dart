/// Golden coverage for the solid overlay style (Settings: "Overlay style" →
/// "Solid"), the opaque WhisPaste-blue alternative to the default glass
/// sheen (`lib/widgets/floating_overlay/overlay_painter.dart`).
///
/// Mirrors `overlay_parity_golden_test.dart`'s 4 states × 3 sizes matrix —
/// the parity suite never exercises `OverlayStyleVariant.solid`, so without
/// this file the solid fill path (`_drawFill` in `WpOverlayPainter`) has no
/// rendered evidence at all, only the structural claim that
/// `OverlayDesignSpec.solidFillGradient` equals `WpColorsDark.frameGradient`.
///
/// Determinism anchors: same as the parity suite (fixed `dotPulse`,
/// deterministic waveform pattern, test-standard DPR).
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  required OverlaySizeVariant size,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    size: size,
    style: OverlayStyleVariant.solid,
    label: switch (state) {
      OverlayVisualState.recording => 'Recording',
      OverlayVisualState.transcribing => 'Transcribing…',
      OverlayVisualState.done => 'Pasted',
      OverlayVisualState.error => 'Error',
    },
    elapsed: state == OverlayVisualState.recording ? '1:30' : '',
    errorMessage: state == OverlayVisualState.error ? 'Network timeout' : null,
    doneMessage: state == OverlayVisualState.done ? 'Pasted' : null,
    progress: state == OverlayVisualState.recording ? 0.4 : 0.0,
  );
}

Widget _buildStaticFrame({
  required FloatingOverlaySnapshot snapshot,
  required Key key,
}) {
  final windowSize = OverlayDesignSpec.windowSizeFor(snapshot.size);
  final bars = List<double>.generate(
    OverlayDesignSpec.waveform.barCount,
    (i) => (i % 7) / 7.0,
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: key,
      child: SizedBox(
        width: windowSize.width,
        height: windowSize.height,
        child: CustomPaint(
          size: windowSize,
          painter: WpFloatingOverlayView.painterFor(
            snapshot: snapshot,
            waveformBars: bars,
            dotPulse: 1.0,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  group('WpOverlayPainter solid-style goldens (4 states × 3 sizes)', () {
    for (final state in OverlayVisualState.values) {
      for (final size in OverlaySizeVariant.values) {
        final stateName = state.name;
        final sizeName = size.name;
        final goldenName = 'overlay_solid_${stateName}_dark_$sizeName';
        final testKey = ValueKey(goldenName);

        testWidgets('golden: $goldenName', (tester) async {
          final snapshot = _snap(state, size: size);

          await tester.pumpWidget(
            _buildStaticFrame(snapshot: snapshot, key: testKey),
          );
          await tester.pump();

          await expectLater(
            find.byKey(testKey),
            matchesGoldenFile('goldens/overlay/$goldenName.png'),
          );
        });
      }
    }
  });
}
