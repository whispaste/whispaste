/// Legibility-Regressions-Goldens (final: softShadow, Maintainer-Entscheid
/// 2026-07-30): weiße Glyphen + weicher Schlagschatten, gerendert gegen die
/// beiden Worst-Case-Hintergründe (sehr hell / sehr dunkel), Recording- und
/// Done-Zustand, Normalgröße (dort lebt der Text). Schützt die
/// hintergrundunabhängige Lesbarkeit mechanisch gegen künftige Drifts.
///
/// Golden-Namensschema:
/// `goldens/legibility/legibility_softShadow_<state>_<bg>.png`
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

/// Worst-Case-Hintergründe: nahezu weißer und nahezu schwarzer Desktop.
const _backgrounds = <String, Color>{
  'light': Color(0xFFFAFAFA),
  'dark': Color(0xFF101010),
};

FloatingOverlaySnapshot _snap(OverlayVisualState state) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    label: switch (state) {
      OverlayVisualState.recording => 'Recording',
      OverlayVisualState.done => 'Pasted',
      _ => '',
    },
    elapsed: state == OverlayVisualState.recording ? '1:30' : '',
    doneMessage: state == OverlayVisualState.done ? 'Pasted' : null,
    progress: state == OverlayVisualState.recording ? 0.4 : 0.0,
  );
}

Widget _frame({
  required FloatingOverlaySnapshot snapshot,
  required Color background,
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
      child: Container(
        color: background,
        padding: const EdgeInsets.all(12),
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

  group('Glyph-Legibility (softShadow) über Worst-Case-Hintergründen', () {
    for (final state in [
      OverlayVisualState.recording,
      OverlayVisualState.done,
    ]) {
      for (final bg in _backgrounds.entries) {
        final goldenName = 'legibility_softShadow_${state.name}_${bg.key}';
        final testKey = ValueKey(goldenName);

        testWidgets('golden: $goldenName', (tester) async {
          await tester.pumpWidget(
            Center(
              child: _frame(
                snapshot: _snap(state),
                background: bg.value,
                key: testKey,
              ),
            ),
          );
          await tester.pump();

          await expectLater(
            find.byKey(testKey),
            matchesGoldenFile('goldens/legibility/$goldenName.png'),
          );
        });
      }
    }
  });
}
