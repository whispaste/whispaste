import 'dart:math' as math;

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

    test('dark and light resolve to the SAME single spike design', () {
      // ADR 0002 / the approved spike (web-parity-board) defines one capsule
      // design — a light teal tint-gradient capsule shown identically over
      // light AND dark backgrounds. There is no separate dark variant.
      expect(OverlayDesignSpec.dark, same(OverlayDesignSpec.light));
    });

    test('accent is the finalised spike teal in BOTH themes', () {
      expect(OverlayDesignSpec.light.accent, const Color(0xFF0887A8));
      expect(OverlayDesignSpec.dark.accent, const Color(0xFF0887A8));
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

    test('sizeFor()/layoutFor() resolve every variant', () {
      expect(
        OverlayDesignSpec.sizeFor(OverlaySizeVariant.normal),
        same(OverlayDesignSpec.normalSize),
      );
      expect(
        OverlayDesignSpec.sizeFor(OverlaySizeVariant.compact),
        same(OverlayDesignSpec.compactSize),
      );
      expect(
        OverlayDesignSpec.sizeFor(OverlaySizeVariant.mini),
        same(OverlayDesignSpec.miniSize),
      );
      expect(
        OverlayDesignSpec.layoutFor(OverlaySizeVariant.normal),
        same(OverlayLayoutSpec.normal),
      );
      expect(
        OverlayDesignSpec.layoutFor(OverlaySizeVariant.compact),
        same(OverlayLayoutSpec.compact),
      );
      expect(
        OverlayDesignSpec.layoutFor(OverlaySizeVariant.mini),
        same(OverlayLayoutSpec.mini),
      );
    });

    test('OverlaySizeVariant.fromName round-trips and falls back safely', () {
      for (final v in OverlaySizeVariant.values) {
        expect(OverlaySizeVariant.fromName(v.name), v);
      }
      expect(OverlaySizeVariant.fromName(null), OverlaySizeVariant.normal);
      expect(OverlaySizeVariant.fromName('bogus'), OverlaySizeVariant.normal);
    });

    test('typography weights are fixed and shared across sizes', () {
      expect(OverlayDesignSpec.timerFontWeight, FontWeight.w700);
      expect(OverlayDesignSpec.primaryFontWeight, FontWeight.w600);
      expect(OverlayDesignSpec.secondaryFontWeight, FontWeight.w400);
    });
  });

  group('OverlayDesignSpec — mini (waveform-first third size)', () {
    test('mini box anchors are the finalised dimensions', () {
      const m = OverlayDesignSpec.miniSize;
      expect(m.width, 150);
      // 28 → 34 (mirrored-bars pass): enough vertical room for visible
      // amplitude without losing the waveform-first micro character.
      expect(m.height, 34);
      expect(m.padH, 12);
      expect(m.capsuleRadius, 17);
      expect(m.statusIconSize, 14);
    });

    test('mini renders the reduced, waveform-first content set', () {
      expect(OverlayDesignSpec.miniSize.minimalContent, isTrue);
      // Normal and compact keep the full content set.
      expect(OverlayDesignSpec.normalSize.minimalContent, isFalse);
      expect(OverlayDesignSpec.compactSize.minimalContent, isFalse);
    });

    test('ONE glass material across all three sizes (impeccable pass)', () {
      // Glass fill/sheen are global constants consumed identically for every
      // size — mini no longer carries its own, more transparent material.
      // Dock-glass values (Maintainer, 2026-07-29, round 2 "noch zu grau"):
      // near-clear fill, soft sheen — the Fresnel edge constants carry the
      // glass identity, and the painted shadow is knocked out under the
      // capsule so no shadow ink greys the glass from behind.
      expect(OverlayDesignSpec.fillOpacityFactor, 0.14);
      expect(OverlayDesignSpec.glassSheenOpacity, 0.15);
    });

    test('mini windowSize = pill box + shadow padding on every side', () {
      expect(
        OverlayDesignSpec.windowSizeFor(OverlaySizeVariant.mini),
        const Size(166, 50),
      );
      // The variant resolver agrees with the legacy bool API for the two
      // original sizes.
      expect(
        OverlayDesignSpec.windowSizeFor(OverlaySizeVariant.normal),
        OverlayDesignSpec.windowSize(compact: false),
      );
      expect(
        OverlayDesignSpec.windowSizeFor(OverlaySizeVariant.compact),
        OverlayDesignSpec.windowSize(compact: true),
      );
    });

    test('mini pill width: full while the waveform runs, shrinks around '
        'the status glyph for done/error', () {
      const m = OverlayDesignSpec.miniSize;
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
      // Mini renders no status text — text never grows the pill.
      for (final state in OverlayDesignState.values) {
        expect(
          OverlayDesignSpec.pillWidthForText(
            state,
            m,
            OverlayLayoutSpec.mini,
            'some long status text that would grow a normal pill',
          ),
          OverlayDesignSpec.pillWidthFor(state, m),
        );
      }
    });

    test('waveform bar count is shared across ALL three sizes', () {
      // Mini reduces content, never the waveform resolution — the bar count
      // stays the single [OverlayDesignSpec.waveform.barCount] everywhere.
      expect(OverlayDesignSpec.waveform.barCount, 22);
      expect(OverlayDesignSpec.miniSize.waveformMaxHeight, 18);
      // Waveform-first means the mini bars claim a LARGER share of their
      // pill than any other size (18/34 ≈ 53 % vs. compact 16/40 = 40 %) —
      // absolute height may exceed compact's since the mirrored-bars pass.
      expect(
        OverlayDesignSpec.miniSize.waveformMaxHeight /
            OverlayDesignSpec.miniSize.height,
        greaterThan(
          OverlayDesignSpec.compactSize.waveformMaxHeight /
              OverlayDesignSpec.compactSize.height,
        ),
      );
    });

    test('mini timeline metrics scale so the timeline clears the waveform '
        '(impeccable layout pass)', () {
      const m = OverlayDesignSpec.miniSize;
      expect(m.timelineInsetBottom, 4.0);
      expect(m.timelineStrokeWidth, 1.5);
      expect(m.timelineLeadDotRadius, 1.6);
      // Geometry: bars span 8..26 (18 px centred in 34), lead dot spans
      // 28.4..31.6 around the line at y 30 — 2.4 px clearance.
      final barBottom = (m.height + m.waveformMaxHeight) / 2;
      final dotTop = m.height - m.timelineInsetBottom - m.timelineLeadDotRadius;
      expect(dotTop, greaterThan(barBottom));
      // Normal keeps the shared spike metrics; compact clears its waveform
      // zone with its own inset/dot (quality-parity pass).
      expect(
        OverlayDesignSpec.normalSize.timelineInsetBottom,
        OverlayDesignSpec.timelineInsetBottom,
      );
      expect(OverlayDesignSpec.compactSize.timelineInsetBottom, 5.0);
      expect(OverlayDesignSpec.compactSize.timelineLeadDotRadius, 1.8);
      expect(
        OverlayDesignSpec.compactSize.timelineStrokeWidth,
        OverlayDesignSpec.timelineStrokeWidth,
      );
    });

    test('universal-legibility glyph scheme (final: white fill + soft '
        'shadow)', () {
      // Subtitle technique, Maintainer-Entscheid nach Varianten-Vergleich:
      // white glyphs over a soft blurred dark drop shadow — readable over
      // any desktop, no hard ring.
      expect(OverlayDesignSpec.contentGlyphFill, const Color(0xFFFFFFFF));
      expect(OverlayDesignSpec.glyphShadowColor, const Color(0xFF14202E));
      expect(OverlayDesignSpec.glyphShadowOpacity, 0.85);
      expect(OverlayDesignSpec.glyphShadowBlurSigma, 1.75);
      expect(OverlayDesignSpec.glyphShadowOffset, const Offset(0, 0.75));
      expect(OverlayDesignSpec.light.text, const Color(0xFF14202E));
    });

    test('glass polish constants (Dock-glass pass) are wired', () {
      expect(OverlayDesignSpec.glassBottomSheenFactor, 0.25);
      expect(OverlayDesignSpec.glassSheenCapInsetFactor, 0.35);
      expect(OverlayDesignSpec.glassInnerShadeOpacity, 0.04);
      expect(OverlayDesignSpec.glassSheenStops, [0.0, 0.32, 0.55]);
      expect(OverlayDesignSpec.glassBottomSheenStops, [0.78, 1.0]);
      expect(OverlayDesignSpec.glassInnerShadeStops, [0.85, 1.0]);
      // Fresnel edge treatment (research pass 2026-07-29): the edges carry
      // the glass identity over the near-clear fill.
      expect(OverlayDesignSpec.glassRimTopOpacity, 0.55);
      expect(OverlayDesignSpec.glassRimBottomOpacity, 0.10);
      expect(OverlayDesignSpec.glassInnerRimWidth, 2.5);
      expect(OverlayDesignSpec.glassInnerRimInset, 1.25);
      expect(OverlayDesignSpec.glassInnerRimOpacity, 0.10);
      // Specular values after the visibility debug (2026-07-30): measured
      // fixes — wider streak, clear of the rim, with a dark under-halo for
      // guaranteed local contrast on light desktops.
      expect(OverlayDesignSpec.glassSpecularOpacity, 0.5);
      expect(OverlayDesignSpec.glassSpecularStrokeWidth, 2.6);
      expect(OverlayDesignSpec.glassSpecularWidthFactor, 0.55);
      expect(OverlayDesignSpec.glassSpecularInsetTop, 5.5);
      expect(OverlayDesignSpec.glassSpecularHaloOpacity, 0.16);
      expect(OverlayDesignSpec.glassSpecularHaloBlurSigma, 2.0);
      expect(OverlayDesignSpec.glassSpecularHaloStrokeWidth, 5.0);
      expect(OverlayDesignSpec.glassSpecularHaloOffsetY, 1.5);
    });

    test('liquid-glass drift constants (calm bounds, phase-0 neutral)', () {
      // An anchored highlight oscillating over one slow cycle; a repeating
      // bright sweep would be a shimmer (ADR 0002) and stays impossible
      // with these parameters. Values raised in the visibility pass
      // (2026-07-30: the drift was imperceptible in live use).
      expect(OverlayDesignSpec.liquidDriftPeriod, const Duration(seconds: 8));
      expect(OverlayDesignSpec.liquidSpecularDriftPx, 12.0);
      expect(OverlayDesignSpec.liquidSheenParallaxFactor, 0.5);
      expect(OverlayDesignSpec.liquidSpecularBreatheFactor, 0.18);
      expect(OverlayDesignSpec.liquidSpecularBrightBreatheFactor, 0.25);
      expect(OverlayDesignSpec.liquidRimBreatheFactor, 0.15);
    });

    test('liquid silhouette wobble constants (Gummibärchen im Windhauch)', () {
      // Base + audio share stay well inside the 8 px shadowPadding, so the
      // deformed capsule can never clip against the native window.
      // Round 2 ("eingeschlossenes Wasser"): base raised moderately, the
      // audio share doubled AND given its own finer ripple waveform.
      expect(OverlayDesignSpec.liquidWobbleBaseAmplitudePx, 1.2);
      expect(OverlayDesignSpec.liquidWobbleAudioAmplitudePx, 2.4);
      expect(
        OverlayDesignSpec.liquidWobbleBaseAmplitudePx +
            OverlayDesignSpec.liquidWobbleAudioAmplitudePx,
        lessThan(OverlayDesignSpec.shadowPadding),
      );
      expect(OverlayDesignSpec.liquidWobbleSamples, 28);
    });

    test('recording bars clear WCAG 1.4.11 (3:1) over worst-case white in '
        'EVERY size — computed, not felt', () {
      // Fully opaque bars: the solid accent and the shaded tip must both
      // stay discernible over a pure white desktop (the worst case for the
      // teal accent). Alphas are 1.0 by decision; the check still guards
      // any future colour drift.
      const white = Color(0xFFFFFFFF);
      final accent = OverlayDesignSpec.light.accent;
      for (final alpha in [
        OverlayDesignSpec.waveformMutedLineOpacity,
        OverlayDesignSpec.waveformActiveOpacity,
      ]) {
        final composited = Color.lerp(white, accent, alpha)!;
        final contrast = 1.05 / (composited.computeLuminance() + 0.05);
        expect(
          contrast,
          greaterThanOrEqualTo(3.0),
          reason:
              'bar at alpha $alpha must reach >=3:1 over white '
              '(got ${contrast.toStringAsFixed(2)}:1)',
        );
      }
      // The old spike muted alpha (0.50) demonstrably failed this bar —
      // that is why the whole ladder was raised, not just mini's.
      final oldMuted = Color.lerp(white, accent, 0.50)!;
      expect(1.05 / (oldMuted.computeLuminance() + 0.05), lessThan(3.0));
    });
  });

  group('OverlayDesignSpec — accessibility', () {
    test('opacity affects only the chrome; slider floor documented', () {
      // Dock-glass fill (Maintainer decision 2026-07-29): the base fill sits
      // deliberately below the old text-safety product — the capsule is
      // meant to read as a bare glass body. The factor scales only the pill
      // chrome (fill gradient, shadow, border), never the content; waveform
      // and icons keep their own >=3:1 guarantees.
      expect(OverlayDesignSpec.fillOpacityFactor, 0.14);
      expect(OverlayDesignSpec.minRecommendedOpacity, 0.65);
    });
  });

  group('OverlayDesignSpec — approved spike capsule design', () {
    test('the pill is a capsule (radius = height / 2)', () {
      expect(OverlayDesignSpec.normalSize.capsuleRadius, 32);
      expect(OverlayDesignSpec.compactSize.capsuleRadius, 20);
    });

    test(
      'tint-gradient fill stops + accent border are the verbatim spike set',
      () {
        // The single approved spike palette (used for both themes).
        expect(
          OverlayDesignSpec.light.capsuleFillStart,
          const Color(0xFFF7FAFD),
        );
        expect(OverlayDesignSpec.light.capsuleFillEnd, const Color(0xFFE6EEF5));
        expect(OverlayDesignSpec.light.capsuleBorder, const Color(0x330887A8));
        // Dark renders the same single design.
        expect(
          OverlayDesignSpec.dark.capsuleFillStart,
          OverlayDesignSpec.light.capsuleFillStart,
        );
        expect(
          OverlayDesignSpec.dark.capsuleFillEnd,
          OverlayDesignSpec.light.capsuleFillEnd,
        );
      },
    );

    test('painted-shadow tokens: spike offset/padding, softened blur '
        '(glass polish pass) plus a tight contact-shadow layer', () {
      expect(OverlayDesignSpec.shadowOpacity, 0.20);
      // Softened from the spike's 7.0 — mirrors the large-blur half of
      // WpShadows.card's two-layer ambient-depth language.
      expect(OverlayDesignSpec.shadowBlur, 9.0);
      expect(OverlayDesignSpec.shadowOffset, const Offset(0, 3));
      expect(OverlayDesignSpec.shadowPadding, 8.0);
      // Contact-shadow layer — the small-blur half of the same two-layer
      // shadow language, grounding the capsule against the desktop.
      expect(OverlayDesignSpec.contactShadowOpacity, 0.12);
      expect(OverlayDesignSpec.contactShadowBlur, 2.0);
      expect(OverlayDesignSpec.contactShadowOffset, const Offset(0, 1));
    });

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

    test('waveform mirrored-bar tokens (Maintainer decision 2026-07-29)', () {
      expect(OverlayDesignSpec.waveformActiveCount, 5);
      // Fully opaque bars — maximum contrast, no alpha wash; the decorative
      // rest state stays quieter.
      expect(OverlayDesignSpec.waveformActiveOpacity, 1.0);
      expect(OverlayDesignSpec.waveformMutedLineOpacity, 1.0);
      expect(OverlayDesignSpec.waveformInactiveStateOpacity, 0.5);
      // Bar construction: filled mirrored capsules; playhead = wider bar +
      // hotter core (no glow — explicitly rejected).
      expect(OverlayDesignSpec.waveformBarFillFactor, 0.62);
      expect(OverlayDesignSpec.waveformActiveBarFillFactor, 0.74);
      expect(OverlayDesignSpec.waveformCoreMutedLightFraction, 0.10);
      expect(OverlayDesignSpec.waveformCoreActiveLightFraction, 0.35);
      expect(OverlayDesignSpec.waveformTipShadeFraction, 0.15);
      expect(OverlayDesignSpec.waveformLevelGamma, 0.65);
      expect(OverlayDesignSpec.waveformHeightFactor, 0.60);
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

    test('additive V2 disc-gradient / border tokens (issue 08)', () {
      const b = OverlayDesignSpec.button;
      expect(b.discGradientEnd, const Color(0xFFEDF1F6));
      expect(b.discFillOpacity, 0.95);
      expect(b.borderInset, 0.5);
      expect(b.mic, same(FloatingButtonMicSpec.spike));
    });

    test('mic geometry is the spike _mic, referenced to a 56px disc', () {
      const m = FloatingButtonMicSpec.spike;
      expect(m.bodyWidthRatio * 56, closeTo(9, 1e-9));
      expect(m.bodyHeightRatio * 56, closeTo(14, 1e-9));
      expect(m.bodyRadiusRatio * 56, closeTo(4.5, 1e-9));
      expect(m.bodyCenterDyRatio * 56, closeTo(-4, 1e-9));
      expect(m.arcRadiusRatio * 56, closeTo(8.5, 1e-9));
      expect(m.arcCenterDyRatio * 56, closeTo(-1, 1e-9));
      expect(m.arcStartAngle, 0.35);
      expect(m.arcSweepAngle, closeTo(math.pi - 0.7, 1e-9));
      expect(m.strokeRatio * 56, closeTo(2, 1e-9));
      expect(m.stemTopDyRatio * 56, closeTo(7.5, 1e-9));
      expect(m.stemBottomDyRatio * 56, closeTo(11, 1e-9));
    });

    test('button window size reserves shadow padding around the disc', () {
      expect(OverlayDesignSpec.buttonWindowSize(56), const Size(72, 72));
      expect(OverlayDesignSpec.buttonWindowSize(44), const Size(60, 60));
      expect(OverlayDesignSpec.buttonWindowSize(80), const Size(96, 96));
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
