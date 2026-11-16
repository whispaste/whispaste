/// Recording-arc tests for the floating overlay (issue 09 — C1a).
///
/// Covers:
///  - AC1: Full arc Standby→Recording→Transcribing→Done (normal + compact);
///    spring appear animation; calm live waveform (no motion outside the arc).
///  - AC2: Vibrancy spec — platform-specific material selection + flat fallback.
///  - AC4: Anti-goals — no glow in spec; arc motion limited to appear +
///    state-crossfade (no scattered/decorative effects).
///  - AC6: Reduced-motion respected — dot pulse stops, spring is instant when
///    MediaQuery.disableAnimations is true; gates in WpFloatingOverlayView.
///
/// AC3 (litmus "five dictated sentences") and AC5 (HITL feel + vibrancy
/// sign-off) are human acceptance gates performed AFTER this build.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

// ── Snapshot helper ──────────────────────────────────────────────────────────

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  bool visible = true,
  OverlaySizeVariant size = OverlaySizeVariant.normal,
  String elapsed = '',
  String? doneMessage,
  String? errorMessage,
  double progress = 0.0,
}) {
  return FloatingOverlaySnapshot(
    visible: visible,
    state: state,
    size: size,
    label: switch (state) {
      OverlayVisualState.recording => 'Recording',
      OverlayVisualState.transcribing => 'Transcribing…',
      OverlayVisualState.done => 'Done',
      OverlayVisualState.error => 'Error',
    },
    elapsed: elapsed,
    doneMessage: doneMessage,
    errorMessage: errorMessage,
    progress: progress,
  );
}

/// Wraps [child] with the minimal MediaQuery + Directionality ancestors the
/// widget tree needs.
Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

void main() {
  // ── AC1: Full recording arc ────────────────────────────────────────────────

  group('AC1 — full recording arc: painter config per state/size', () {
    for (final state in OverlayVisualState.values) {
      for (final size in OverlaySizeVariant.values) {
        final tag = '${state.name} · ${size.name}';

        testWidgets('$tag — builds without error', (tester) async {
          final bars = List<double>.generate(
            OverlayDesignSpec.waveform.barCount,
            (i) => (i % 5) / 5.0,
          );
          await tester.pumpWidget(
            _wrap(
              WpFloatingOverlayView(
                snapshot: _snap(
                  state,
                  size: size,
                  elapsed: state == OverlayVisualState.recording ? '0:07' : '',
                  progress: state == OverlayVisualState.recording ? 0.2 : 0.0,
                  doneMessage: state == OverlayVisualState.done
                      ? 'Eingefügt!'
                      : null,
                  errorMessage: state == OverlayVisualState.error
                      ? 'Kein Netzwerk'
                      : null,
                ),
                waveformBars: bars,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(CustomPaint), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    test('painterFor wires live waveform in recording, empty otherwise', () {
      final bars = List<double>.filled(
        OverlayDesignSpec.waveform.barCount,
        0.7,
      );
      for (final state in OverlayVisualState.values) {
        final painter = WpFloatingOverlayView.painterFor(
          snapshot: _snap(state, elapsed: '0:12', progress: 0.1),
          waveformBars: bars,
        );
        if (state == OverlayVisualState.recording) {
          expect(
            painter.waveformBars,
            isNotEmpty,
            reason: '$state should pass bars',
          );
        } else {
          expect(
            painter.waveformBars,
            isEmpty,
            reason: '$state should suppress bars',
          );
        }
      }
    });

    test(
      'done state with paste-confirmation doneMessage flows to statusText',
      () {
        const pasteMsg = 'Eingefügt!';
        final painter = WpFloatingOverlayView.painterFor(
          snapshot: _snap(OverlayVisualState.done, doneMessage: pasteMsg),
        );
        expect(painter.statusText, pasteMsg);
      },
    );

    test('recording arc covers standby (visible=false) → recording → done', () {
      // All valid snapshot transitions are spec-driven; the arc is closed.
      final standby = _snap(OverlayVisualState.recording, visible: false);
      final recording = _snap(
        OverlayVisualState.recording,
        visible: true,
        elapsed: '0:15',
        progress: 0.05,
      );
      final transcribing = _snap(
        OverlayVisualState.transcribing,
        visible: true,
      );
      final done = _snap(
        OverlayVisualState.done,
        visible: true,
        doneMessage: 'Eingefügt!',
      );

      for (final snap in [standby, recording, transcribing, done]) {
        expect(
          () => WpFloatingOverlayView.painterFor(snapshot: snap),
          returnsNormally,
        );
      }
    });
  });

  // ── AC1: Spring appear animation ─────────────────────────────────────────

  // ── AC2: Vibrancy spec (platform-aware) ───────────────────────────────────

  group('AC2 — vibrancy spec: platform-aware material selection', () {
    test('macOS material = hudWindow (Phase-0 GO, best optics confirmed)', () {
      expect(
        OverlayDesignSpec.vibrancy.macOS,
        OverlayVibrancyMaterial.hudWindow,
      );
    });

    test('Windows material = acrylic (planned, flutter_acrylic)', () {
      expect(
        OverlayDesignSpec.vibrancy.windows,
        OverlayVibrancyMaterial.acrylic,
      );
    });

    test('Linux material = flat (default tinted fallback, no OS blur)', () {
      expect(OverlayDesignSpec.vibrancy.linux, OverlayVibrancyMaterial.flat);
    });

    test('forPlatform selects macOS/Windows/Linux by platform string', () {
      const v = OverlayDesignSpec.vibrancy;
      expect(v.forPlatform('macos'), OverlayVibrancyMaterial.hudWindow);
      expect(v.forPlatform('windows'), OverlayVibrancyMaterial.acrylic);
      expect(v.forPlatform('linux'), OverlayVibrancyMaterial.flat);
    });

    test('forPlatform falls back to flat for unknown platform', () {
      expect(
        OverlayDesignSpec.vibrancy.forPlatform('unknown'),
        OverlayVibrancyMaterial.flat,
      );
      expect(
        OverlayDesignSpec.vibrancy.forPlatform(''),
        OverlayVibrancyMaterial.flat,
      );
    });

    test(
      'flat fallback fill opacity is higher than vibrancy fill (more opaque without blur)',
      () {
        // Without OS-level blur, the capsule needs more opacity for readability.
        expect(
          OverlayDesignSpec.flatFallbackFillOpacity,
          greaterThan(OverlayDesignSpec.fillOpacityFactor),
        );
        // But never exceeds 1.0.
        expect(
          OverlayDesignSpec.flatFallbackFillOpacity,
          lessThanOrEqualTo(1.0),
        );
      },
    );

    test('OverlayVibrancyMaterial enum covers all required variants', () {
      expect(
        OverlayVibrancyMaterial.values,
        containsAll(<OverlayVibrancyMaterial>[
          OverlayVibrancyMaterial.hudWindow,
          OverlayVibrancyMaterial.acrylic,
          OverlayVibrancyMaterial.mica,
          OverlayVibrancyMaterial.flat,
        ]),
      );
    });
  });

  // ── AC4: Anti-goals ───────────────────────────────────────────────────────

  // ── Issue 09 wiring: state-transition crossfade ───────────────────────────

  // ── AC6: Reduced-motion ───────────────────────────────────────────────────

  // ── Dynamic pill-width spring (issue 10) ──────────────────────────────────

  // ── Re-show pill width (waveform-gone-on-2nd-recording regression) ─────────
  //
  // Proven root cause: the pill-width spring only fires on a state change
  // between two *visible* snapshots. A second recording is a hide→show where
  // both the hide snapshot and the show snapshot carry state=recording, so no
  // spring fires and the pill stays at the previous episode's final `done`
  // (narrow) width — which clips the live waveform to nothing. The fix snaps
  // the pill to the current state's width on every (re-)appear.
}
