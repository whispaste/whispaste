/// Widget/painter tests for the shared overlay renderer (issue 05).
///
/// Covers:
///  - AC1: the painter is sourced **only** from [OverlayDesignSpec] — colours,
///    size and layout wired by [FloatingOverlayView.painterFor]
///    equal the spec values, never a platform-local constant.
///  - Spike fidelity: the painter consumes the approved capsule/tint/layout
///    tokens (capsule radius, tint-gradient fill stops, accent dot, spike
///    layout offsets).
///  - painter-per-state: the view builds and paints for all 4 states × 2 themes
///    × 2 sizes without throwing.
///  - AC5: no glow/badge; calm rendering builds for every combination.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

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
  group('FloatingOverlayView.painterFor — spec sourcing (AC1)', () {
    test('theme mapping comes from the spec', () {
      expect(FloatingOverlayView.themeFor(true), OverlayDesignTheme.dark);
      expect(FloatingOverlayView.themeFor(false), OverlayDesignTheme.light);
    });

    test('design-state mapping covers every visual state', () {
      for (final s in OverlayVisualState.values) {
        expect(() => FloatingOverlayView.designStateFor(s), returnsNormally);
      }
      expect(
        FloatingOverlayView.designStateFor(OverlayVisualState.transcribing),
        OverlayDesignState.transcribing,
      );
    });

    test('colours, size and layout are taken from OverlayDesignSpec', () {
      for (final isDark in [true, false]) {
        for (final compact in [true, false]) {
          final painter = FloatingOverlayView.painterFor(
            snapshot: _snap(
              OverlayVisualState.recording,
              isDark: isDark,
              compact: compact,
            ),
          );
          final theme = isDark
              ? OverlayDesignTheme.dark
              : OverlayDesignTheme.light;

          expect(
            painter.colors.capsuleFillStart,
            OverlayDesignSpec.colors(theme).capsuleFillStart,
          );
          expect(painter.colors.accent, OverlayDesignSpec.colors(theme).accent);
          expect(painter.sizeSpec, OverlayDesignSpec.size(compact: compact));
          expect(painter.layout, OverlayDesignSpec.layout(compact: compact));
        }
      }
    });

    test('waveform bars only flow to the recording state', () {
      final bars = List<double>.filled(
        OverlayDesignSpec.waveform.barCount,
        0.5,
      );
      final recording = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          isDark: true,
          compact: false,
        ),
        waveformBars: bars,
      );
      final done = FloatingOverlayView.painterFor(
        snapshot: _snap(OverlayVisualState.done, isDark: true, compact: false),
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

  group('FloatingOverlayView — paints every state/theme/size (AC2)', () {
    for (final state in OverlayVisualState.values) {
      for (final isDark in [true, false]) {
        for (final compact in [true, false]) {
          testWidgets('${state.name} · ${isDark ? 'dark' : 'light'} · '
              '${compact ? 'compact' : 'normal'} builds & paints', (
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
                  child: FloatingOverlayView(
                    snapshot: _snap(state, isDark: isDark, compact: compact),
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
    }
  });
}
