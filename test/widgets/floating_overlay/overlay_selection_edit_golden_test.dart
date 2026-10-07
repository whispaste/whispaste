/// Goldens for the overlay states of "edit selection by voice"
/// (`.scratch/voice-selection-edit/`): the feature reuses the shared
/// [WpOverlayPainter], so these pin how its own texts (editing label, done
/// message, no-selection error) render in every overlay size. The recording
/// frame is left out: that composition paints no text, so it is pixel-
/// identical to the generic recording golden.
///
/// German strings are used on purpose — they are the longest of the four
/// locales. Same deterministic frame setup as `overlay_parity_golden_test`.
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap(
  L10n l10n,
  OverlayVisualState state, {
  required OverlaySizeVariant size,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    size: size,
    label: switch (state) {
      OverlayVisualState.recording => l10n.overlayRecordingSelectionEdit,
      OverlayVisualState.transcribing => l10n.overlayEditingSelection,
      OverlayVisualState.done => l10n.overlayDoneSelectionEdit,
      OverlayVisualState.error => l10n.overlayError,
    },
    errorMessage: state == OverlayVisualState.error
        ? l10n.errorSelectionEditNoSelection
        : null,
    doneMessage: state == OverlayVisualState.done
        ? l10n.overlayDoneSelectionEdit
        : null,
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

  final l10n = lookupL10n(const Locale('de'));

  group('selection-edit overlay goldens (de)', () {
    for (final state in OverlayVisualState.values.where(
      (s) => s != OverlayVisualState.recording,
    )) {
      for (final size in OverlaySizeVariant.values) {
        final goldenName = 'overlay_selection_edit_${state.name}_${size.name}';
        final testKey = ValueKey(goldenName);

        testWidgets('golden: $goldenName', (tester) async {
          await tester.pumpWidget(
            _buildStaticFrame(
              snapshot: _snap(l10n, state, size: size),
              key: testKey,
            ),
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
