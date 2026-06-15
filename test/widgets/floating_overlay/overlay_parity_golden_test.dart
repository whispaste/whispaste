/// Parität-Golden-Tests für den geteilten Overlay-Renderer.
///
/// Ein einziger [OverlayPainter] zeichnet auf allen Plattformen. Da alle
/// Plattformen denselben Painter-Output konsumieren, erzwingt ein Golden-Match
/// mechanisch die Parität (ADR 0002 / Issue 06).
///
/// Abdeckung: 4 States × 2 Themes × 2 Sizes = 16 Goldens.
///
/// Determinismus-Ankerpunkte:
/// - [dotPulse] ist auf 1.0 fixiert (keine Animation).
/// - Waveform-Balken sind ein festes deterministisches Muster.
/// - DPR ist Flutter-Test-Standard (1.0).
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

// ── Snapshot-Hilfsfunktion ──────────────────────────────────────────────────

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  required bool isDark,
  required bool compact,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    isDark: isDark,
    compact: compact,
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

// ── Widget-Wrapper ──────────────────────────────────────────────────────────

/// Baut einen statischen, deterministischen Overlay-Frame ohne AnimationController.
///
/// Verwendet [FloatingOverlayView.painterFor] mit festem [dotPulse] = 1.0, damit
/// das PNG-Ergebnis frame-unabhängig ist. Die nativen Hüllen erhalten denselben
/// Painter — das Golden ist damit per Definition der Parität-Beweis.
Widget _buildStaticFrame({
  required FloatingOverlaySnapshot snapshot,
  required Key key,
}) {
  final windowSize = OverlayDesignSpec.windowSize(compact: snapshot.compact);
  final bars = List<double>.generate(
    OverlayDesignSpec.waveform.barCount,
    // Deterministisches Muster: i % 7 / 7 → sichtbare Waveform im recording-State.
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
          painter: FloatingOverlayView.painterFor(
            snapshot: snapshot,
            waveformBars: bars,
            dotPulse: 1.0,
          ),
        ),
      ),
    ),
  );
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('OverlayPainter parität-goldens (4 states × 2 themes × 2 sizes)', () {
    for (final state in OverlayVisualState.values) {
      for (final isDark in [true, false]) {
        for (final compact in [true, false]) {
          final stateName = state.name;
          final themeName = isDark ? 'dark' : 'light';
          final sizeName = compact ? 'compact' : 'normal';
          final goldenName = 'overlay_${stateName}_${themeName}_$sizeName';
          final testKey = ValueKey(goldenName);

          testWidgets('golden: $goldenName', (tester) async {
            final snapshot = _snap(state, isDark: isDark, compact: compact);

            await tester.pumpWidget(
              _buildStaticFrame(snapshot: snapshot, key: testKey),
            );
            // Ein einzelner Frame genügt (kein AnimationController aktiv).
            await tester.pump();

            await expectLater(
              find.byKey(testKey),
              matchesGoldenFile('goldens/overlay/$goldenName.png'),
            );
          });
        }
      }
    }
  });
}
