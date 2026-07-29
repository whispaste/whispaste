/**
 * Unit tests for the overlay-mockup renderer's pure parts.
 *
 * Two acceptance criteria of issue 10 are locked here without a browser:
 *
 *   - AC1: the colour/measure tokens match the SSOT design spec
 *     (`lib/core/theme/overlay_design_spec.dart`), including the liquid-glass
 *     constants (Dock-glass passes 2026-07-29/30). If the Dart spec changes,
 *     these assertions force the website mirror to be updated in lockstep.
 *   - AC3: the waveform mirrors the final history model (issue 04) — scrolling
 *     right→left, volume-faithful amplitude, and silence decaying to a flat
 *     floor with no perpetual jitter.
 *
 * The recording-arc helpers (pill-width targets, the width spring, the
 * silhouette wobble waves) are pure and covered here too. The cross-engine
 * pixel parity (AC4) is proven separately by `tests/overlay-parity.spec.ts`
 * (WebKit vs Chromium).
 */
import { describe, expect, it } from "vitest";
import {
  OVERLAY_TOKENS,
  OVERLAY_GEOMETRY,
  OVERLAY_CHROME,
  OVERLAY_GLASS,
  OVERLAY_GLYPH,
  OVERLAY_LIQUID,
  OVERLAY_WAVEFORM,
  OVERLAY_WAVEFORM_MOTION,
  OVERLAY_ARC,
  FROZEN_BARS,
  WaveformHistory,
  Spring,
  easeOutCubic,
  wobbleWind,
  wobbleRipple,
  pillWidthRatio,
  pillWidthForText,
  type OverlayState,
} from "../overlay-mockup";

describe("AC1: tokens mirror the SSOT design spec", () => {
  it("uses the canonical light tint-fill, accent and status colours (OverlayDesignSpec.light)", () => {
    expect(OVERLAY_TOKENS.light.fillStart).toBe("#F7FAFD");
    expect(OVERLAY_TOKENS.light.fillEnd).toBe("#E6EEF5");
    expect(OVERLAY_TOKENS.light.accent).toBe("#0887A8");
    expect(OVERLAY_TOKENS.light.content).toBe("#14202E"); // OverlayDesignSpec.light.text
    expect(OVERLAY_TOKENS.light.success).toBe("#05875C");
    expect(OVERLAY_TOKENS.light.error).toBe("#CC1C1C");
  });

  it("uses the dark colour set (OverlayDesignSpec.dark = light — one single capsule design)", () => {
    // The SSOT declares `static const OverlayThemeColors dark = light;`
    // There is deliberately no separate dark capsule variant.
    expect(OVERLAY_TOKENS.dark).toEqual(OVERLAY_TOKENS.light);
  });

  it("uses the normal-size geometry anchors (full capsule = height / 2)", () => {
    expect(OVERLAY_GEOMETRY.width).toBe(330);
    expect(OVERLAY_GEOMETRY.height).toBe(64);
    expect(OVERLAY_GEOMETRY.capsuleRadius).toBe(OVERLAY_GEOMETRY.height / 2);
    expect(OVERLAY_GEOMETRY.padH).toBe(22);
    expect(OVERLAY_GEOMETRY.shadowPad).toBe(8);
    expect(OVERLAY_GEOMETRY.statusIconSize).toBe(16);
  });

  it("uses the Dock-glass near-clear fill (fillOpacityFactor 0.14)", () => {
    expect(OVERLAY_CHROME.fillOpacity).toBe(0.14);
    expect(OVERLAY_CHROME.borderOpacity).toBeCloseTo(0x33 / 255, 2);
  });

  it("carries the two-layer shadow (soft ambient + tight contact)", () => {
    expect(OVERLAY_CHROME.shadowOpacity).toBe(0.2);
    expect(OVERLAY_CHROME.shadowBlur).toBe(9);
    expect(OVERLAY_CHROME.shadowDy).toBe(3);
    expect(OVERLAY_CHROME.contactShadowOpacity).toBe(0.12);
    expect(OVERLAY_CHROME.contactShadowBlur).toBe(2);
    expect(OVERLAY_CHROME.contactShadowDy).toBe(1);
  });

  it("uses the universal-legibility glyph scheme (white fill + soft dark shadow)", () => {
    expect(OVERLAY_GLYPH.fill).toBe("#FFFFFF");
    expect(OVERLAY_GLYPH.shadowColor).toBe("#14202E");
    expect(OVERLAY_GLYPH.shadowOpacity).toBe(0.85);
    expect(OVERLAY_GLYPH.shadowBlur).toBe(1.75);
    expect(OVERLAY_GLYPH.shadowDy).toBe(0.75);
  });

  it("mirrors the Fresnel edge + specular streak constants", () => {
    expect(OVERLAY_GLASS.sheenOpacity).toBe(0.15);
    expect(OVERLAY_GLASS.rimTopOpacity).toBe(0.55);
    expect(OVERLAY_GLASS.rimBottomOpacity).toBe(0.1);
    expect(OVERLAY_GLASS.innerRimWidth).toBe(2.5);
    expect(OVERLAY_GLASS.innerRimInset).toBe(1.25);
    expect(OVERLAY_GLASS.specularOpacity).toBe(0.5);
    expect(OVERLAY_GLASS.specularStrokeWidth).toBe(2.6);
    expect(OVERLAY_GLASS.specularWidthFactor).toBe(0.55);
    expect(OVERLAY_GLASS.specularInsetTop).toBe(5.5);
    expect(OVERLAY_GLASS.specularHaloOpacity).toBe(0.16);
  });

  it("mirrors the liquid-glass drift + wobble parameters", () => {
    expect(OVERLAY_LIQUID.driftPeriodMs).toBe(8000);
    expect(OVERLAY_LIQUID.specularDriftPx).toBe(12);
    expect(OVERLAY_LIQUID.sheenParallaxFactor).toBe(0.5);
    expect(OVERLAY_LIQUID.specularBreatheFactor).toBe(0.18);
    expect(OVERLAY_LIQUID.specularBrightBreatheFactor).toBe(0.25);
    expect(OVERLAY_LIQUID.rimBreatheFactor).toBe(0.15);
    expect(OVERLAY_LIQUID.wobbleSamples).toBe(28);
    expect(OVERLAY_LIQUID.wobbleBaseAmplitudePx).toBe(1.2);
    expect(OVERLAY_LIQUID.wobbleAudioAmplitudePx).toBe(2.4);
    // Total wobble stays comfortably inside the 8 px shadow padding so the
    // deformed silhouette never clips (SSOT: total ≤ 3.6 px).
    expect(
      OVERLAY_LIQUID.wobbleBaseAmplitudePx + OVERLAY_LIQUID.wobbleAudioAmplitudePx,
    ).toBeLessThanOrEqual(OVERLAY_GEOMETRY.shadowPad);
  });

  it("uses the SSOT mirrored-bar waveform parameters (22 bars, last 5 wider/hotter)", () => {
    expect(OVERLAY_WAVEFORM.barCount).toBe(22);
    expect(OVERLAY_WAVEFORM.activeCount).toBe(5);
    // Fully opaque bars while recording — identity via width + core brightness.
    expect(OVERLAY_WAVEFORM.activeOpacity).toBe(1);
    expect(OVERLAY_WAVEFORM.mutedOpacity).toBe(1);
    expect(OVERLAY_WAVEFORM.inactiveStateOpacity).toBe(0.5);
    expect(OVERLAY_WAVEFORM.barFillFactor).toBe(0.62);
    expect(OVERLAY_WAVEFORM.activeBarFillFactor).toBe(0.74);
    expect(OVERLAY_WAVEFORM.levelGamma).toBe(0.65);
    expect(OVERLAY_WAVEFORM.coreMutedLightFraction).toBe(0.1);
    expect(OVERLAY_WAVEFORM.coreActiveLightFraction).toBe(0.35);
    expect(OVERLAY_WAVEFORM.tipShadeFraction).toBe(0.15);
    expect(OVERLAY_WAVEFORM.heightFactor).toBe(0.6);
    expect(OVERLAY_WAVEFORM.restLevel).toBe(0.06);
    expect(OVERLAY_WAVEFORM.minNorm).toBeCloseTo(3 / 24, 10);
  });

  it("uses the SSOT smoothing constants with release slower than attack", () => {
    expect(OVERLAY_WAVEFORM_MOTION.attackMs).toBe(20);
    expect(OVERLAY_WAVEFORM_MOTION.releaseMs).toBe(300);
    expect(OVERLAY_WAVEFORM_MOTION.releaseMs).toBeGreaterThan(
      OVERLAY_WAVEFORM_MOTION.attackMs,
    );
  });

  it("mirrors the recording-arc motion (appear spring, crossfades, pill spring)", () => {
    expect(OVERLAY_ARC.appearMs).toBe(300);
    expect(OVERLAY_ARC.appearScale).toBe(0.88);
    expect(OVERLAY_ARC.stateTransitionMs).toBe(150);
    expect(OVERLAY_ARC.statusRevealMs).toBe(280);
    expect(OVERLAY_ARC.spring).toEqual({ mass: 1, stiffness: 170, damping: 26 });
  });

  it("ships a 22-value frozen snapshot for the parity baseline", () => {
    expect(FROZEN_BARS).toHaveLength(OVERLAY_WAVEFORM.barCount);
    for (const v of FROZEN_BARS) {
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
    }
  });
});

describe("recording arc: pill-width targets (OverlayDesignSpec.pillWidthRatio)", () => {
  it("uses the SSOT per-state ratios", () => {
    expect(pillWidthRatio("recording")).toBe(1.0);
    expect(pillWidthRatio("transcribing")).toBe(0.758);
    expect(pillWidthRatio("done")).toBe(0.606);
    expect(pillWidthRatio("error")).toBe(0.758);
  });

  it("grows just enough to fit long text and clamps to the full width", () => {
    const measure = (t: string) => t.length * 7; // stub layout
    const base = OVERLAY_GEOMETRY.width * pillWidthRatio("done");

    // Short text: the base ratio width wins.
    expect(pillWidthForText("done", "Pasted", measure)).toBe(base);

    // Longer text: grows past the base…
    const grown = pillWidthForText("done", "A somewhat longer done message", measure);
    expect(grown).toBeGreaterThan(base);

    // …but never past the full (recording) width the native window reserves.
    const huge = "x".repeat(400);
    expect(pillWidthForText("done", huge, measure)).toBe(OVERLAY_GEOMETRY.width);
  });

  it("keeps the recording state at full width regardless of text", () => {
    const states: OverlayState[] = ["recording"];
    for (const s of states) {
      expect(pillWidthForText(s, "", () => 0)).toBe(OVERLAY_GEOMETRY.width);
    }
  });
});

describe("recording arc: width spring (OverlayArcMotion.pillSpring)", () => {
  it("converges to a new target without meaningful overshoot (Gentle preset)", () => {
    const spring = new Spring(330);
    spring.setTarget(200);
    let minSeen = spring.value;
    for (let i = 0; i < 90; i++) {
      spring.step(1000 / 30);
      minSeen = Math.min(minSeen, spring.value);
    }
    // Settled at the target after ~3 s of simulated frames…
    expect(spring.value).toBeCloseTo(200, 1);
    expect(spring.settled).toBe(true);
    // …and the near-critically-damped spring never visibly undershoots.
    expect(minSeen).toBeGreaterThan(199);
  });

  it("carries position/velocity across a retarget (smooth interrupt)", () => {
    const spring = new Spring(330);
    spring.setTarget(200);
    for (let i = 0; i < 5; i++) spring.step(1000 / 30);
    const midway = spring.value;
    expect(midway).toBeLessThan(330);
    expect(midway).toBeGreaterThan(200);
    spring.setTarget(330); // interrupt back
    for (let i = 0; i < 120; i++) spring.step(1000 / 30);
    expect(spring.value).toBeCloseTo(330, 1);
  });

  it("snapTo applies the reduced-motion instant jump", () => {
    const spring = new Spring(330);
    spring.snapTo(200);
    expect(spring.value).toBe(200);
    expect(spring.settled).toBe(true);
  });
});

describe("liquid silhouette wobble (OverlayPainter._liquidShape waves)", () => {
  it("keeps both waves inside a unit envelope", () => {
    for (let i = 0; i <= 40; i++) {
      const u = i / 40;
      for (const phase of [0, 0.13, 0.5, 0.77]) {
        expect(Math.abs(wobbleWind(u, phase))).toBeLessThanOrEqual(1.0);
        expect(Math.abs(wobbleRipple(u, phase))).toBeLessThanOrEqual(1.0);
      }
    }
  });

  it("is seamless at the phase wrap (integer time-cycles per loop)", () => {
    for (const u of [0, 0.21, 0.5, 0.83]) {
      expect(wobbleWind(u, 1)).toBeCloseTo(wobbleWind(u, 0), 10);
      expect(wobbleRipple(u, 1)).toBeCloseTo(wobbleRipple(u, 0), 10);
    }
  });

  it("is seamless around the perimeter (integer spatial periods)", () => {
    for (const phase of [0, 0.4]) {
      expect(wobbleWind(1, phase)).toBeCloseTo(wobbleWind(0, phase), 10);
      expect(wobbleRipple(1, phase)).toBeCloseTo(wobbleRipple(0, phase), 10);
    }
  });
});

describe("easeOutCubic (OverlayArcMotion.appearCurve)", () => {
  it("maps 0→0 and 1→1 without overshoot", () => {
    expect(easeOutCubic(0)).toBe(0);
    expect(easeOutCubic(1)).toBe(1);
    let prev = 0;
    for (let i = 1; i <= 20; i++) {
      const v = easeOutCubic(i / 20);
      expect(v).toBeGreaterThanOrEqual(prev);
      expect(v).toBeLessThanOrEqual(1);
      prev = v;
    }
  });
});

describe("AC3: waveform history model", () => {
  it("holds exactly barCount bars", () => {
    const wf = new WaveformHistory();
    expect(wf.values()).toHaveLength(OVERLAY_WAVEFORM.barCount);
  });

  it("scrolls right→left: the newest sample lands at the right edge", () => {
    const wf = new WaveformHistory();
    // A loud onset followed by silence: the loud bar must march left over time.
    wf.tick(1);
    const after1 = wf.values();
    const newest = after1.length - 1;
    expect(after1[newest]).toBeGreaterThan(after1[newest - 1]);

    wf.tick(0);
    const after2 = wf.values();
    // The previous newest (loud) sample has shifted one slot to the left and is
    // still louder than the fresh silent bar at the right edge.
    expect(after2[newest - 1]).toBeGreaterThan(after2[newest]);
  });

  it("is volume-faithful: a louder sample yields a taller newest bar", () => {
    const quiet = new WaveformHistory();
    quiet.tick(0.2);
    const loud = new WaveformHistory();
    loud.tick(0.8);
    const i = OVERLAY_WAVEFORM.barCount - 1;
    expect(loud.values()[i]).toBeGreaterThan(quiet.values()[i]);
  });

  it("never lowers the rising edge while the input keeps climbing", () => {
    const wf = new WaveformHistory();
    const i = OVERLAY_WAVEFORM.barCount - 1;
    let prev = -1;
    for (const raw of [0.1, 0.3, 0.5, 0.7, 0.9]) {
      wf.tick(raw);
      const edge = wf.values()[i];
      expect(edge).toBeGreaterThanOrEqual(prev);
      prev = edge;
    }
  });

  it("decays sustained silence to a flat floor with no jitter", () => {
    const wf = new WaveformHistory();
    for (let i = 0; i < 5; i++) wf.tick(1); // get loud
    for (let i = 0; i < 400; i++) wf.tick(0); // hold silence

    const settled = wf.values();
    const floor = OVERLAY_WAVEFORM.minNorm;
    for (const v of settled) {
      expect(v).toBeCloseTo(floor, 5);
    }
    // No perpetual floor jitter: two further silent frames are identical.
    wf.tick(0);
    const a = wf.values();
    wf.tick(0);
    const b = wf.values();
    expect(b).toEqual(a);
  });

  it("starts at the silent floor and resets back to it", () => {
    const wf = new WaveformHistory();
    expect(wf.values().every((v) => v === OVERLAY_WAVEFORM.minNorm)).toBe(true);
    wf.tick(1);
    expect(wf.values().some((v) => v > OVERLAY_WAVEFORM.minNorm)).toBe(true);
    wf.reset();
    expect(wf.values().every((v) => v === OVERLAY_WAVEFORM.minNorm)).toBe(true);
  });

  it("compact = scaled, not reduced: same bar count, heights × a smaller max", () => {
    const wf = new WaveformHistory();
    for (let i = 0; i < 10; i++) wf.tick(0.5 + 0.4 * Math.sin(i));

    const normalMax = 24; // OverlaySizeSpec.normal.waveformMaxHeight
    const compactMax = 16; // OverlaySizeSpec.compact.waveformMaxHeight (24 × 2/3)
    const normal = wf.barHeights(normalMax);
    const compact = wf.barHeights(compactMax);

    expect(compact).toHaveLength(normal.length); // not reduced
    const ratio = compactMax / normalMax;
    for (let i = 0; i < normal.length; i++) {
      expect(compact[i]).toBeCloseTo(normal[i] * ratio, 10); // scaled
    }
  });
});
