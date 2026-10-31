/// Widget/painter tests for the shared overlay renderer (issue 05).
///
/// Covers:
///  - AC1: the painter is sourced **only** from [OverlayDesignSpec] — colours,
///    size and layout wired by [WpFloatingOverlayView.painterFor]
///    equal the spec values, never a platform-local constant.
///  - Spike fidelity: the painter consumes the approved capsule/tint/layout
///    tokens (capsule radius, tint-gradient fill stops, accent dot, spike
///    layout offsets).
///  - painter-per-state: the view builds and paints for all 4 states × 3 sizes
///    without throwing.
///  - AC5: no glow/badge; calm rendering builds for every combination.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  OverlaySizeVariant size = OverlaySizeVariant.normal,
  OverlayBackground background = OverlayBackground.marine,
  OverlayWave wave = OverlayWave.cyan,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    size: size,
    background: background,
    wave: wave,
    label: switch (state) {
      OverlayVisualState.recording => 'Press Ctrl+Shift+D to stop',
      OverlayVisualState.transcribing => 'Transcribing…',
      OverlayVisualState.done => 'Done',
      OverlayVisualState.error => 'Error',
    },
    elapsed: state == OverlayVisualState.recording ? '0:12' : '',
    errorMessage: state == OverlayVisualState.error ? 'Network timeout' : null,
    doneMessage: state == OverlayVisualState.done ? 'Pasted!' : null,
    progress: state == OverlayVisualState.recording ? 0.4 : 0.0,
  );
}

void main() {
  // ── Dynamic pill-width (issue 10) ─────────────────────────────────────────

  group('Overlay theme presets — background and wave (ticket, ADR 0024)', () {
    test('default presets are marine and cyan', () {
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.recording),
      );
      expect(painter.colors, equals(OverlayDesignSpec.colorsFor()));
    });

    test('painterFor forwards the snapshot background and wave', () {
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          background: OverlayBackground.gletscher,
          wave: OverlayWave.violett,
        ),
      );
      expect(
        painter.colors,
        equals(
          OverlayDesignSpec.colorsFor(
            background: OverlayBackground.gletscher,
            wave: OverlayWave.violett,
          ),
        ),
      );
    });

    test('shouldRepaint detects a background or wave change', () {
      final marine = WpFloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.recording),
      );
      final graphit = WpFloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          background: OverlayBackground.graphit,
        ),
      );
      final coral = WpFloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.recording, wave: OverlayWave.coral),
      );
      expect(graphit.shouldRepaint(marine), isTrue);
      expect(coral.shouldRepaint(marine), isTrue);
      expect(marine.shouldRepaint(marine), isFalse);
    });
  });

  group('live-transcript tail-first text (live-preview spike)', () {
    const longText =
        'eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf '
        'dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn';

    FloatingOverlaySnapshot liveSnap(OverlayVisualState state) =>
        FloatingOverlaySnapshot(
          visible: true,
          state: state,
          size: OverlaySizeVariant.normal,
          label: 'Transcribing…',
          elapsed: state == OverlayVisualState.recording ? longText : '',
          liveTranscript: longText,
        );

    test('painterFor enables tail-first text only for live transcripts', () {
      expect(
        WpFloatingOverlayView.painterFor(
          snapshot: liveSnap(OverlayVisualState.recording),
        ).tailFirstText,
        isTrue,
      );
      expect(
        WpFloatingOverlayView.painterFor(
          snapshot: liveSnap(OverlayVisualState.transcribing),
        ).tailFirstText,
        isTrue,
      );
      expect(
        WpFloatingOverlayView.painterFor(
          snapshot: _snap(OverlayVisualState.recording),
        ).tailFirstText,
        isFalse,
      );
      expect(
        WpFloatingOverlayView.painterFor(
          snapshot: _snap(OverlayVisualState.transcribing),
        ).tailFirstText,
        isFalse,
      );
    });

    test('overflowing live text keeps the newest words, not the oldest', () {
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: liveSnap(OverlayVisualState.recording),
      );
      final shown = painter.fittedTextFor(longText, 400);
      expect(shown, startsWith('…'));
      expect(shown, endsWith(' neunzehn'));
      expect(shown, isNot(contains('eins')));
    });

    test('classic text is passed through untouched (trailing ellipsis '
        'stays with TextPainter)', () {
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.transcribing),
      );
      expect(painter.fittedTextFor(longText, 120), longText);
    });

    test('recording text never runs under the stop square', () {
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: liveSnap(OverlayVisualState.recording),
      );
      const pill = Rect.fromLTWH(0, 0, 300, 40);
      const textLeft = 40.0;
      final stopLeft =
          pill.right - painter.layout.padH - painter.layout.stopSize;
      expect(
        textLeft + painter.recordingTextMaxWidth(pill, textLeft),
        lessThanOrEqualTo(stopLeft),
      );
    });
  });

  group('done after a failed paste (XP-5-07)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    FloatingOverlaySnapshot doneSnap(
      OverlaySizeVariant size, {
      required bool pasteFailed,
    }) => FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.done,
      size: size,
      label: 'Done',
      doneMessage: pasteFailed ? 'Not pasted' : 'Pasted',
      donePasteFailed: pasteFailed,
    );

    // Counts opaque pixels close to the preset's success green, i.e. the
    // painted check mark.
    Future<int> successPixels(FloatingOverlaySnapshot snap) async {
      final window = OverlayDesignSpec.windowSizeFor(snap.size);
      final recorder = ui.PictureRecorder();
      WpFloatingOverlayView.painterFor(
        snapshot: snap,
      ).paint(Canvas(recorder), window);
      final image = await recorder.endRecording().toImage(
        window.width.ceil(),
        window.height.ceil(),
      );
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final green = OverlayDesignSpec.colorsFor(
        background: snap.background,
        wave: snap.wave,
      ).success;
      int channel(double v) => (v * 255).round();
      final (r, g, b) = (channel(green.r), channel(green.g), channel(green.b));
      var count = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 3] > 200 &&
            (bytes[i] - r).abs() < 24 &&
            (bytes[i + 1] - g).abs() < 24 &&
            (bytes[i + 2] - b).abs() < 24) {
          count++;
        }
      }
      return count;
    }

    for (final size in OverlaySizeVariant.values) {
      test(
        '${size.name}: the green check is only drawn for a real paste',
        () async {
          expect(
            await successPixels(doneSnap(size, pasteFailed: false)),
            greaterThan(0),
            reason: 'control: a successful run paints the green check',
          );
          expect(
            await successPixels(doneSnap(size, pasteFailed: true)),
            0,
            reason: '"Not pasted" must not sit next to a green check',
          );
        },
      );
    }

    test('the flag reaches the painter and triggers a repaint', () {
      final failed = WpFloatingOverlayView.painterFor(
        snapshot: doneSnap(OverlaySizeVariant.normal, pasteFailed: true),
      );
      final pasted = WpFloatingOverlayView.painterFor(
        snapshot: doneSnap(OverlaySizeVariant.normal, pasteFailed: false),
      );
      expect(failed.donePasteFailed, isTrue);
      expect(failed.shouldRepaint(pasted), isTrue);
    });
  });
}
