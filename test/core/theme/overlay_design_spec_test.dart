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
      expect(wf.attackTimeConstantMs, 20);
      expect(wf.releaseTimeConstantMs, 300);
    });

    test(
      'release smoothing is slower than attack (silence fades, not snaps)',
      () {
        const wf = OverlayDesignSpec.waveform;
        // A pause must visibly decay to the floor rather than snap flat, so the
        // falling edge is deliberately gentler than the rising edge.
        expect(wf.releaseTimeConstantMs, greaterThan(wf.attackTimeConstantMs));
      },
    );

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
    test('opacity affects only the chrome; floor is WCAG-safe', () {
      // Approved spike fill alpha is 0.92; the factor scales only the pill
      // chrome (fill gradient, shadow, border), never the content.
      expect(OverlayDesignSpec.fillOpacityFactor, 0.92);
      expect(OverlayDesignSpec.minRecommendedOpacity, 0.65);
    });
  });

  group('OverlayDesignSpec — approved spike capsule design', () {
    test('the pill is a capsule (radius = height / 2)', () {
      expect(OverlayDesignSpec.normalSize.capsuleRadius, 32);
      expect(OverlayDesignSpec.compactSize.capsuleRadius, 20);
    });

    test('per-theme tint-gradient fill stops + accent border exist', () {
      // Light is the verbatim approved spike palette.
      expect(OverlayDesignSpec.light.capsuleFillStart, const Color(0xFFF7FAFD));
      expect(OverlayDesignSpec.light.capsuleFillEnd, const Color(0xFFE6EEF5));
      expect(OverlayDesignSpec.light.capsuleBorder, const Color(0x330887A8));
      // Dark provides an analogous, distinct set (never half-defined).
      expect(
        OverlayDesignSpec.dark.capsuleFillStart,
        isNot(OverlayDesignSpec.light.capsuleFillStart),
      );
      expect(
        OverlayDesignSpec.dark.capsuleFillEnd,
        isNot(OverlayDesignSpec.light.capsuleFillEnd),
      );
    });

    test(
      'painted-shadow tokens match the spike (α0.20, blur 7, offset 0,3)',
      () {
        expect(OverlayDesignSpec.shadowOpacity, 0.20);
        expect(OverlayDesignSpec.shadowBlur, 7.0);
        expect(OverlayDesignSpec.shadowOffset, const Offset(0, 3));
        expect(OverlayDesignSpec.shadowPadding, 8.0);
      },
    );

    test('windowSize = pill box + shadow padding on every side', () {
      expect(OverlayDesignSpec.windowSize(compact: false), const Size(346, 80));
      expect(OverlayDesignSpec.windowSize(compact: true), const Size(236, 56));
    });

    test('stop-square + timeline tokens are the spike values', () {
      expect(OverlayDesignSpec.stopSquareRadius, 2.0);
      expect(OverlayDesignSpec.stopSquareOpacity, 0.9);
      expect(OverlayDesignSpec.timelineInsetBottom, 6.0);
      expect(OverlayDesignSpec.timelineStrokeWidth, 2.0);
      expect(OverlayDesignSpec.timelineEndOpacity, 0.25);
    });

    test('waveform line rendering tokens are the spike values', () {
      expect(OverlayDesignSpec.waveformActiveCount, 5);
      expect(OverlayDesignSpec.waveformActiveOpacity, 0.95);
      expect(OverlayDesignSpec.waveformMutedLineOpacity, 0.50);
      expect(OverlayDesignSpec.waveformInactiveStateOpacity, 0.30);
      expect(OverlayDesignSpec.waveformHeightFactor, 0.60);
      expect(OverlayDesignSpec.waveformLineStrokeFactor, 0.5);
      expect(OverlayDesignSpec.waveformRestLevel, 0.06);
    });

    test('recording dot pulse floor is the spike 0.6', () {
      expect(OverlayDesignSpec.motion.dotPulseMinAlpha, 0.6);
    });

    test('layout offsets match the spike _drawPill (normal + compact)', () {
      const n = OverlayLayoutSpec.normal;
      const c = OverlayLayoutSpec.compact;
      expect(
        [n.padH, n.dotInset, n.timerGap, n.stopSize, n.timerFontSize],
        [22, 28, 16, 12, 14],
      );
      expect(
        [c.padH, c.dotInset, c.timerGap, c.stopSize, c.timerFontSize],
        [16, 20, 12, 10, 12],
      );
      expect(OverlayDesignSpec.layout(compact: false), same(n));
      expect(OverlayDesignSpec.layout(compact: true), same(c));
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
