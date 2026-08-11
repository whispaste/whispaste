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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  OverlaySizeVariant size = OverlaySizeVariant.normal,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    size: size,
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
  group('WpFloatingOverlayView.painterFor — spec sourcing (AC1)', () {
    // Removed 2026-08-11 (dark-only build): `theme mapping comes from the
    // spec`. It asserted `WpFloatingOverlayView.themeFor(bool)`, which is
    // gone — call sites now use `OverlayDesignTheme.dark` directly.

    test('design-state mapping covers every visual state', () {
      for (final s in OverlayVisualState.values) {
        expect(() => WpFloatingOverlayView.designStateFor(s), returnsNormally);
      }
      expect(
        WpFloatingOverlayView.designStateFor(OverlayVisualState.transcribing),
        OverlayDesignState.transcribing,
      );
    });

    test('colours, size and layout are taken from OverlayDesignSpec', () {
      for (final size in OverlaySizeVariant.values) {
        final painter = WpFloatingOverlayView.painterFor(
          snapshot: _snap(OverlayVisualState.recording, size: size),
        );
        const theme = OverlayDesignTheme.dark;

        expect(
          painter.colors.capsuleFillStart,
          OverlayDesignSpec.colors(theme).capsuleFillStart,
        );
        expect(painter.colors.accent, OverlayDesignSpec.colors(theme).accent);
        expect(painter.sizeSpec, OverlayDesignSpec.sizeFor(size));
        expect(painter.layout, OverlayDesignSpec.layoutFor(size));
      }
    });

    test('waveform bars only flow to the recording state', () {
      final bars = List<double>.filled(
        OverlayDesignSpec.waveform.barCount,
        0.5,
      );
      final recording = WpFloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.recording),
        waveformBars: bars,
      );
      final done = WpFloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.done),
        waveformBars: bars,
      );
      expect(recording.waveformBars, isNotEmpty);
      expect(done.waveformBars, isEmpty);
    });
  });

  group('Spike fidelity — capsule, tint, accent dot, layout', () {
    test('the pill is a capsule (radius = height / 2)', () {
      expect(OverlayDesignSpec.normalSize.capsuleRadius, 32);
      expect(OverlayDesignSpec.compactSize.capsuleRadius, 20);
    });

    test('light tint-gradient stops are the approved spike colours', () {
      expect(OverlayDesignSpec.light.capsuleFillStart, const Color(0xFFF7FAFD));
      expect(OverlayDesignSpec.light.capsuleFillEnd, const Color(0xFFE6EEF5));
      expect(OverlayDesignSpec.light.capsuleBorder, const Color(0x330887A8));
    });

    test('recording dot uses the accent colour, not the red recordingDot', () {
      // The painter draws the dot in colors.accent; the legacy red
      // recordingDot token is no longer the dot colour (spike: teal dot).
      expect(
        OverlayDesignSpec.light.accent,
        isNot(OverlayDesignSpec.light.recordingDot),
      );
    });

    test('window size reserves shadow padding around the pill', () {
      expect(
        OverlayDesignSpec.windowSize(compact: false),
        const Size(330 + 16, 64 + 16),
      );
      expect(
        OverlayDesignSpec.windowSize(compact: true),
        const Size(220 + 16, 40 + 16),
      );
    });

    test('normal layout offsets match the spike _drawPill values', () {
      const n = OverlayLayoutSpec.normal;
      expect(n.padH, 22);
      expect(n.dotInset, 28);
      expect(n.timerGap, 16);
      expect(n.stopSize, 12);
      expect(n.timerFontSize, 14);
    });
  });

  // ── Dynamic pill-width (issue 10) ─────────────────────────────────────────

  group('pillWidthRatio — per-state target widths', () {
    test('recording = 1.0 (full width)', () {
      expect(
        OverlayDesignSpec.pillWidthRatio(OverlayDesignState.recording),
        1.0,
      );
    });

    test('transcribing ≈ 0.758', () {
      expect(
        OverlayDesignSpec.pillWidthRatio(OverlayDesignState.transcribing),
        closeTo(0.758, 0.001),
      );
    });

    test('done ≈ 0.606 (narrowest state)', () {
      expect(
        OverlayDesignSpec.pillWidthRatio(OverlayDesignState.done),
        closeTo(0.606, 0.001),
      );
    });

    test('error ≈ 0.758 (same as transcribing)', () {
      expect(
        OverlayDesignSpec.pillWidthRatio(OverlayDesignState.error),
        closeTo(0.758, 0.001),
      );
    });

    test('pillWidthFor normal — recording = full width (330)', () {
      const spec = OverlaySizeSpec.normal;
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.recording, spec),
        closeTo(330.0, 0.01),
      );
    });

    test('pillWidthFor normal — done ≈ 200 px', () {
      const spec = OverlaySizeSpec.normal;
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.done, spec),
        closeTo(330.0 * 0.606, 0.5),
      );
    });

    test('pillWidthFor compact scales by compact width (220)', () {
      final spec = OverlaySizeSpec.compact;
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.recording, spec),
        closeTo(220.0, 0.01),
      );
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.done, spec),
        closeTo(220.0 * 0.606, 0.5),
      );
    });

    test('pillWidthForText — short text stays at the ratio width', () {
      const spec = OverlaySizeSpec.normal;
      final layout = OverlayDesignSpec.layout(compact: false);
      // 'OK' comfortably fits the ~200 px done pill — no growth needed.
      expect(
        OverlayDesignSpec.pillWidthForText(
          OverlayDesignState.done,
          spec,
          layout,
          'OK',
        ),
        closeTo(
          OverlayDesignSpec.pillWidthFor(OverlayDesignState.done, spec),
          0.5,
        ),
      );
    });

    test('pillWidthForText — long text grows the pill beyond the ratio width '
        '(overlay-text-truncated bug)', () {
      const spec = OverlaySizeSpec.normal;
      final layout = OverlayDesignSpec.layout(compact: false);
      const longMessage = 'Transkription hat keinen Text ergeben';
      final width = OverlayDesignSpec.pillWidthForText(
        OverlayDesignState.done,
        spec,
        layout,
        longMessage,
      );
      expect(
        width,
        greaterThan(
          OverlayDesignSpec.pillWidthFor(OverlayDesignState.done, spec),
        ),
        reason: 'a long done message must grow the pill, not just clip it',
      );
    });

    test('pillWidthForText — clamps at sizeSpec.width so it never exceeds the '
        'native window', () {
      const spec = OverlaySizeSpec.normal;
      final layout = OverlayDesignSpec.layout(compact: false);
      const pathologicallyLongMessage =
          'This status message is deliberately far longer than any pill '
          'could ever reasonably display in one line without wrapping';
      final width = OverlayDesignSpec.pillWidthForText(
        OverlayDesignState.done,
        spec,
        layout,
        pathologicallyLongMessage,
      );
      expect(width, spec.width);
    });

    test(
      'pillSpring is the Gentle preset (mass=1, stiffness=170, damping=26)',
      () {
        const s = OverlayArcMotion.pillSpring;
        expect(s.mass, 1.0);
        expect(s.stiffness, 170.0);
        expect(s.damping, 26.0);
      },
    );
  });

  group('WpOverlayPainter — pillWidth parameter', () {
    test('shouldRepaint detects pillWidth change', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
        elapsed: '0:05',
        progress: 0.1,
      );
      final p330 = WpFloatingOverlayView.painterFor(
        snapshot: snap,
        pillWidth: 330.0,
      );
      final p200 = WpFloatingOverlayView.painterFor(
        snapshot: snap,
        pillWidth: 200.0,
      );
      final p330b = WpFloatingOverlayView.painterFor(
        snapshot: snap,
        pillWidth: 330.0,
      );

      expect(
        p330.shouldRepaint(p200),
        isTrue,
        reason: 'different pillWidth must trigger repaint',
      );
      expect(
        p200.shouldRepaint(p330),
        isTrue,
        reason: 'different pillWidth must trigger repaint (reverse)',
      );
      expect(
        p330.shouldRepaint(p330b),
        isFalse,
        reason: 'same pillWidth must not trigger repaint',
      );
    });

    test('pillWidth field is forwarded to WpOverlayPainter', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.transcribing,
        label: 'Transcribing…',
        elapsed: '',
        progress: 0.0,
      );
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: snap,
        pillWidth: 250.0,
      );
      expect(painter.pillWidth, 250.0);
    });

    test('pillWidth null → uses full sizeSpec.width (default behaviour)', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
        elapsed: '0:01',
        progress: 0.0,
      );
      final painter = WpFloatingOverlayView.painterFor(snapshot: snap);
      expect(painter.pillWidth, isNull);
    });
  });

  group('WpOverlayPainter — mini (waveform-first) wiring', () {
    test('painterFor resolves the mini spec + layout from the snapshot', () {
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          size: OverlaySizeVariant.mini,
        ),
      );
      expect(painter.sizeSpec, same(OverlayDesignSpec.miniSize));
      expect(painter.layout, same(OverlayLayoutSpec.mini));
      expect(painter.sizeSpec.minimalContent, isTrue);
    });

    test('mini pill: full width while the waveform runs, shrinks around '
        'the glyph for done/error', () {
      const m = OverlaySizeSpec.mini;
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.recording, m),
        m.width,
      );
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.transcribing, m),
        m.width,
      );
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.done, m),
        closeTo(m.width * 0.42, 1e-9),
      );
      expect(
        OverlayDesignSpec.pillWidthFor(OverlayDesignState.error, m),
        closeTo(m.width * 0.42, 1e-9),
      );
    });

    test('mini timeline metrics are the scaled per-size set', () {
      const m = OverlaySizeSpec.mini;
      expect(m.timelineInsetBottom, 4.0);
      expect(m.timelineStrokeWidth, 1.5);
      expect(m.timelineLeadDotRadius, 1.6);
    });
  });

  group('WpFloatingOverlayView — paints every state/size (AC2)', () {
    for (final state in OverlayVisualState.values) {
      for (final size in OverlaySizeVariant.values) {
        testWidgets('${state.name} · ${size.name} builds & paints', (
          tester,
        ) async {
          final bars = List<double>.generate(
            OverlayDesignSpec.waveform.barCount,
            (i) => (i % 7) / 7.0,
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: WpFloatingOverlayView(
                  snapshot: _snap(state, size: size),
                  waveformBars: bars,
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));

          expect(find.byType(CustomPaint), findsWidgets);
          expect(tester.takeException(), isNull);

          // Tear down the repeating animation cleanly.
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  });
}
