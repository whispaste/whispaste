/**
 * Unit tests for the overlay-mockup renderer's pure parts.
 *
 * Two acceptance criteria of issue 10 are locked here without a browser:
 *
 *   - AC1: the colour/measure tokens match the SSOT design spec
 *     (`lib/core/theme/overlay_design_spec.dart`). If the Dart spec changes,
 *     these assertions force the website mirror to be updated in lockstep.
 *   - AC3: the waveform mirrors the final history model (issue 04) — scrolling
 *     right→left, volume-faithful amplitude, and silence decaying to a flat
 *     floor with no perpetual jitter.
 *
 * The cross-engine pixel parity (AC4) is proven separately by
 * `tests/overlay-parity.spec.ts` (WebKit vs Chromium).
 */
import { describe, expect, it } from "vitest";
import {
  OVERLAY_TOKENS,
  OVERLAY_GEOMETRY,
  OVERLAY_WAVEFORM,
  OVERLAY_WAVEFORM_MOTION,
  FROZEN_BARS,
  WaveformHistory,
} from "../overlay-mockup";

describe("AC1: tokens mirror the SSOT design spec", () => {
  it("uses the canonical V4 light tint-fill and accent (OverlayDesignSpec.light)", () => {
    expect(OVERLAY_TOKENS.light.fillStart).toBe("#F7FAFD");
    expect(OVERLAY_TOKENS.light.fillEnd).toBe("#E6EEF5");
    expect(OVERLAY_TOKENS.light.accent).toBe("#0887A8");
    expect(OVERLAY_TOKENS.light.content).toBe("#14202E"); // OverlayDesignSpec.light.text
  });

  it("uses the dark colour set (OverlayDesignSpec.dark = light — one single capsule design)", () => {
    // The SSOT declares `static const OverlayThemeColors dark = light;`
    // There is deliberately no separate dark capsule variant.
    expect(OVERLAY_TOKENS.dark.fillStart).toBe("#F7FAFD");
    expect(OVERLAY_TOKENS.dark.fillEnd).toBe("#E6EEF5");
    expect(OVERLAY_TOKENS.dark.accent).toBe("#0887A8");
    expect(OVERLAY_TOKENS.dark.content).toBe("#14202E");
  });

  it("uses the normal-size geometry anchors (full capsule = height / 2)", () => {
    expect(OVERLAY_GEOMETRY.width).toBe(330);
    expect(OVERLAY_GEOMETRY.height).toBe(64);
    expect(OVERLAY_GEOMETRY.capsuleRadius).toBe(OVERLAY_GEOMETRY.height / 2);
    expect(OVERLAY_GEOMETRY.padH).toBe(22);
    expect(OVERLAY_GEOMETRY.shadowPad).toBe(8);
  });

  it("uses the SSOT waveform parameters (22 bars, last 5 active, 60% height)", () => {
    expect(OVERLAY_WAVEFORM.barCount).toBe(22);
    expect(OVERLAY_WAVEFORM.activeCount).toBe(5);
    expect(OVERLAY_WAVEFORM.activeOpacity).toBe(0.95);
    expect(OVERLAY_WAVEFORM.mutedOpacity).toBe(0.5);
    expect(OVERLAY_WAVEFORM.heightFactor).toBe(0.6);
    expect(OVERLAY_WAVEFORM.minNorm).toBeCloseTo(3 / 24, 10);
  });

  it("uses the SSOT smoothing constants with release slower than attack", () => {
    expect(OVERLAY_WAVEFORM_MOTION.attackMs).toBe(20);
    expect(OVERLAY_WAVEFORM_MOTION.releaseMs).toBe(300);
    expect(OVERLAY_WAVEFORM_MOTION.releaseMs).toBeGreaterThan(
      OVERLAY_WAVEFORM_MOTION.attackMs,
    );
  });

  it("ships a 22-value frozen snapshot for the parity baseline", () => {
    expect(FROZEN_BARS).toHaveLength(OVERLAY_WAVEFORM.barCount);
    for (const v of FROZEN_BARS) {
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
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
