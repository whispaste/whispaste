/// Golden coverage for the live-transcript overlay option (ticket 11).
///
/// The overlay's `transcribing` composition ([WpOverlayPainter._drawTranscribing])
/// paints whatever `WpFloatingOverlayView.statusTextFor` returns — normally the
/// generic "Transcribing…" label, or (this ticket) the recognized text so far
/// once `FloatingOverlaySnapshot.liveTranscript` is set. Both states are
/// legitimate, user-selectable overlay behaviour (the setting default is OFF —
/// see `AppSettings.overlayShowLiveTranscript`'s doc comment), so both get a
/// golden across all three size variants: 2 states × 3 sizes = 6 goldens.
///
/// Golden-Namensschema: `goldens/overlay/overlay_liveTranscript_offOrOn_dark_
/// sizeName.png` — mirrors `overlay_parity_golden_test.dart`'s scheme
/// (`overlay_stateName_dark_sizeName.png`) in the same directory.
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap({
  required OverlaySizeVariant size,
  String? liveTranscript,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: OverlayVisualState.transcribing,
    size: size,
    label: 'Transcribing…',
    liveTranscript: liveTranscript,
  );
}

Widget _buildStaticFrame({
  required FloatingOverlaySnapshot snapshot,
  required Key key,
}) {
  final windowSize = OverlayDesignSpec.windowSizeFor(snapshot.size);
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
            dotPulse: 1.0,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  group('Live-transcript overlay option (ticket 11) — goldens', () {
    for (final size in OverlaySizeVariant.values) {
      final sizeName = size.name;

      testWidgets('golden: overlay_liveTranscript_off_dark_$sizeName', (
        tester,
      ) async {
        final goldenName = 'overlay_liveTranscript_off_dark_$sizeName';
        final testKey = ValueKey(goldenName);
        // Setting off / no partial text yet: classic "Transcribing…" label —
        // pixel-identical to the existing transcribing-state goldens.
        final snapshot = _snap(size: size, liveTranscript: null);

        await tester.pumpWidget(
          _buildStaticFrame(snapshot: snapshot, key: testKey),
        );
        await tester.pump();

        await expectLater(
          find.byKey(testKey),
          matchesGoldenFile('goldens/overlay/$goldenName.png'),
        );
      });

      testWidgets('golden: overlay_liveTranscript_on_dark_$sizeName', (
        tester,
      ) async {
        final goldenName = 'overlay_liveTranscript_on_dark_$sizeName';
        final testKey = ValueKey(goldenName);
        // Setting on with recognized text so far — replaces the generic
        // label, sharing the identical spinner/notch/pill-spring machinery.
        final snapshot = _snap(
          size: size,
          liveTranscript: 'This is the recognized text so far',
        );

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
  });
}
