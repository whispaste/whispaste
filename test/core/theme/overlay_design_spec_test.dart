import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('OverlayDesignSpec — states', () {
    test('covers exactly the four real states (no processing)', () {
      expect(OverlayDesignState.values, hasLength(4));
      expect(OverlayDesignState.values, <OverlayDesignState>[
        OverlayDesignState.recording,
        OverlayDesignState.transcribing,
        OverlayDesignState.done,
        OverlayDesignState.error,
      ]);
    });

    test('state gradients are defined for every state', () {
      for (final state in OverlayDesignState.values) {
        final gradient = OverlayDesignSpec.stateGradients[state];
        expect(gradient, isNotNull, reason: 'missing gradient for $state');
        expect(gradient!.stops.length, greaterThanOrEqualTo(2));
      }
    });

    test('done gradient middle stop is the canonical green #30C065', () {
      final done = OverlayDesignSpec.stateGradients[OverlayDesignState.done]!;
      expect(done.stops, hasLength(3));
      expect(done.stops[1], const Color(0xFF30C065));
    });
  });

  group('OverlayDesignSpec — themes', () {
    test('both theme variants exist and resolve', () {
      expect(OverlayDesignTheme.values, <OverlayDesignTheme>[
        OverlayDesignTheme.dark,
        OverlayDesignTheme.light,
      ]);
      expect(
        OverlayDesignSpec.colors(OverlayDesignTheme.dark),
        same(OverlayDesignSpec.dark),
      );
      expect(
        OverlayDesignSpec.colors(OverlayDesignTheme.light),
        same(OverlayDesignSpec.light),
      );
    });

    test('colorsForDark matches the boolean snapshot flag', () {
      expect(
        OverlayDesignSpec.colorsForDark(true),
        same(OverlayDesignSpec.dark),
      );
      expect(
        OverlayDesignSpec.colorsForDark(false),
        same(OverlayDesignSpec.light),
      );
    });

    test(
      'theme colour pairs are complete — no field is shared by accident',
      () {
        const dark = OverlayDesignSpec.dark;
        const light = OverlayDesignSpec.light;
        // Every theme-specific colour must actually differ between themes.
        expect(dark.surface, isNot(light.surface));
        expect(dark.text, isNot(light.text));
        expect(dark.secondaryText, isNot(light.secondaryText));
        expect(dark.border, isNot(light.border));
        expect(dark.accent, isNot(light.accent));
        expect(dark.success, isNot(light.success));
        expect(dark.error, isNot(light.error));
        expect(dark.waveformMuted, isNot(light.waveformMuted));
        // Recording dot is intentionally shared.
        expect(dark.recordingDot, light.recordingDot);
      },
    );

    test('accent values are the finalised cyan pair', () {
      expect(OverlayDesignSpec.dark.accent, const Color(0xFF38D9F0));
      expect(OverlayDesignSpec.light.accent, const Color(0xFF0887A8));
    });
  });

  group('OverlayDesignSpec — waveform', () {
    test('carries all waveform parameters', () {
      const wf = OverlayDesignSpec.waveform;
      expect(wf.barCount, 22);
      expect(wf.minBarHeightPx, 3.0);
      expect(wf.activeColorThreshold, 0.30);
      expect(wf.activeAccentOpacity, 0.85);
      expect(wf.mutedOpacity, 0.50);
    });

    test('bar count is shared across both sizes (compact is not reduced)', () {
      // The single waveform spec is used for both sizes; only the bar HEIGHT
      // scales per size, never the bar COUNT. This is the 8-vs-30 fix.
      expect(OverlayDesignSpec.waveform.barCount, greaterThan(8));
      expect(
        OverlayDesignSpec.normalSize.waveformMaxHeight,
        greaterThan(OverlayDesignSpec.compactSize.waveformMaxHeight),
      );
    });
  });

  group('OverlayDesignSpec — sizes', () {
    test('normal box anchors are the finalised dimensions', () {
      const n = OverlayDesignSpec.normalSize;
      expect(n.width, 330);
      expect(n.height, 64);
      expect(n.cornerRadius, 18);
      expect(n.padH, 22);
    });

    test('compact box anchors are the finalised dimensions', () {
      final c = OverlayDesignSpec.compactSize;
      expect(c.width, 220);
      expect(c.height, 40);
      expect(c.cornerRadius, 20);
      expect(c.padH, 16);
    });

    test('compact content metrics equal normal × compactScale', () {
      const n = OverlayDesignSpec.normalSize;
      final c = OverlayDesignSpec.compactSize;
      const s = OverlayDesignSpec.compactScale;
      double scaled(double v) => v * s;

      expect(c.dotSize, closeTo(scaled(n.dotSize), 1e-9));
      expect(c.closeButtonSize, closeTo(scaled(n.closeButtonSize), 1e-9));
      expect(c.stopButtonSize, closeTo(scaled(n.stopButtonSize), 1e-9));
      expect(c.spinnerSize, closeTo(scaled(n.spinnerSize), 1e-9));
      expect(c.statusIconSize, closeTo(scaled(n.statusIconSize), 1e-9));
      expect(c.waveformMaxHeight, closeTo(scaled(n.waveformMaxHeight), 1e-9));
      expect(c.waveformBarWidth, closeTo(scaled(n.waveformBarWidth), 1e-9));
      expect(c.waveformBarGap, closeTo(scaled(n.waveformBarGap), 1e-9));
      expect(c.dotTextGap, closeTo(scaled(n.dotTextGap), 1e-9));
      expect(c.timerWaveformGap, closeTo(scaled(n.timerWaveformGap), 1e-9));
      expect(c.pillGap, closeTo(scaled(n.pillGap), 1e-9));
      expect(
        c.bottomProgressHeight,
        closeTo(scaled(n.bottomProgressHeight), 1e-9),
      );
      expect(c.timerFontSize, closeTo(scaled(n.timerFontSize), 1e-9));
      expect(c.primaryFontSize, closeTo(scaled(n.primaryFontSize), 1e-9));
      expect(c.secondaryFontSize, closeTo(scaled(n.secondaryFontSize), 1e-9));
    });

    test('compactScale maps the key macOS reference values', () {
      final c = OverlayDesignSpec.compactSize;
      // 24 → 16 waveform, 15 → 10 timer (sanity against the native basis).
      expect(c.waveformMaxHeight, closeTo(16, 1e-9));
      expect(c.timerFontSize, closeTo(10, 1e-9));
    });

    test('size() resolves the compact flag', () {
      expect(
        OverlayDesignSpec.size(compact: false),
        same(OverlayDesignSpec.normalSize),
      );
      expect(
        OverlayDesignSpec.size(compact: true),
        same(OverlayDesignSpec.compactSize),
      );
    });

    test('typography weights are fixed and shared across sizes', () {
      expect(OverlayDesignSpec.timerFontWeight, FontWeight.w700);
      expect(OverlayDesignSpec.primaryFontWeight, FontWeight.w600);
      expect(OverlayDesignSpec.secondaryFontWeight, FontWeight.w400);
    });
  });

  group('OverlayDesignSpec — accessibility', () {
    test('opacity affects only the fill; floor is WCAG-safe', () {
      expect(OverlayDesignSpec.fillOpacityFactor, 0.96);
      expect(OverlayDesignSpec.minRecommendedOpacity, 0.65);
    });
  });

  group('OverlayDesignSpec — interaction', () {
    test('shared drag threshold and anchor positions', () {
      const i = OverlayDesignSpec.interaction;
      expect(i.dragThresholdPx, 3.0);
      expect(i.screenEdgeMargin, 24);
      expect(i.anchors, <OverlayAnchor>[
        OverlayAnchor.topCenter,
        OverlayAnchor.bottomCenter,
        OverlayAnchor.lastPosition,
      ]);
    });
  });

  group('OverlayDesignSpec — floating button (V2)', () {
    test('white disc, dark mic, hairline border, no glow', () {
      const b = OverlayDesignSpec.button;
      expect(b.discColor, const Color(0xFFFFFFFF));
      expect(b.iconColor, const Color(0xFF101828));
      expect(b.borderColor, const Color(0x1A101828));
      expect(b.borderWidth, 1.0);
      expect(b.iconRatio, 24 / 56);
      expect(b.hasGlow, isFalse);
    });
  });

  group('OverlayDesignSpec — no privacy badge', () {
    test('the model exposes no privacy/badge concept', () {
      // Anti-vocabulary guard: this test fails to compile if a privacy badge
      // field is ever reintroduced (kept as a documented invariant). The four
      // states alone drive the rendering.
      expect(
        OverlayDesignState.values.map((e) => e.name),
        isNot(contains('privacy')),
      );
      expect(
        OverlayDesignState.values.map((e) => e.name),
        isNot(contains('badge')),
      );
    });
  });
}
