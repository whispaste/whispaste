/**
 * Overlay-mockup renderer — the website's mirror of the in-app overlay.
 *
 * WhisPaste treats the marketing site as the "fourth platform" of overlay
 * parity. The app draws its floating recording overlay with one shared
 * `CustomPainter` (`lib/widgets/floating_overlay/overlay_painter.dart`) whose
 * every dimension, colour and timing comes from the Dart SSOT
 * (`lib/core/theme/overlay_design_spec.dart`). This module reproduces that
 * exact look on an HTML canvas so Safari (WebKit) and Chrome/Edge (Chromium)
 * render the same drawing the app uses — a canvas was chosen over CSS chrome
 * because the spike proved 98.45 % cross-engine pixel parity with it, whereas
 * CSS `backdrop-filter`/`box-shadow`/gradients diverge per engine.
 *
 * Every constant below is copied verbatim from `OverlayDesignSpec` (normal-size
 * pill, light + dark theme colour sets). There are deliberately no invented
 * values: change the Dart SSOT, then mirror it here.
 *
 * The module has no top-level DOM access so the pure parts (tokens +
 * {@link WaveformHistory}) are unit-testable under Node/Vitest. Only
 * {@link drawOverlayPill} touches a canvas context, and it is never called at
 * import time.
 */

/** Theme variants the mockup mirrors — same two the app SSOT defines. */
export type OverlayTheme = 'light' | 'dark';

/** One theme-resolved colour set (verbatim from `OverlayDesignSpec`). */
export interface OverlayThemeTokens {
  /** Capsule tint gradient top-left stop. */
  readonly fillStart: string;
  /** Capsule tint gradient bottom-right stop. */
  readonly fillEnd: string;
  /** Accent — recording dot, waveform bars, progress timeline, hairline border. */
  readonly accent: string;
  /** Opaque content colour — close glyph, timer text, stop square. */
  readonly content: string;
}

/**
 * Light + dark colour sets, copied from `OverlayDesignSpec.light` /
 * `OverlayDesignSpec.dark`. The light tint-fill is the canonical V4 capsule
 * (`#F7FAFD → #E6EEF5`) named in the design spec.
 */
export const OVERLAY_TOKENS: Readonly<Record<OverlayTheme, OverlayThemeTokens>> = {
  light: {
    fillStart: '#F7FAFD', // OverlayDesignSpec.light.capsuleFillStart
    fillEnd: '#E6EEF5', //   OverlayDesignSpec.light.capsuleFillEnd
    accent: '#0887A8', //    OverlayDesignSpec.light.accent
    content: '#101828', //   OverlayDesignSpec.light.text
  },
  dark: {
    fillStart: '#1E2738', // OverlayDesignSpec.dark.capsuleFillStart
    fillEnd: '#12161F', //   OverlayDesignSpec.dark.capsuleFillEnd
    accent: '#38D9F0', //    OverlayDesignSpec.dark.accent
    content: '#F0F4FA', //   OverlayDesignSpec.dark.text
  },
};

/**
 * Normal-size pill geometry, from `OverlaySizeSpec.normal` +
 * `OverlayLayoutSpec.normal`. `capsuleRadius = height / 2` (full capsule).
 * `shadowPad` mirrors `OverlayDesignSpec.shadowPadding` (room for the painted
 * shadow around the pill box).
 */
export const OVERLAY_GEOMETRY = {
  width: 330,
  height: 64,
  capsuleRadius: 32, // height / 2
  shadowPad: 8,
  padH: 22,
  closeArm: 4,
  closeStroke: 1.6,
  closeOffset: 5,
  dotInset: 28,
  dotRadius: 4.5,
  timerGap: 16,
  timerFontSize: 14,
  waveStartGap: 18,
  waveEndGap: 16,
  stopSize: 12,
  lineStrokeMin: 2,
} as const;

/**
 * Waveform render parameters, from `OverlayDesignSpec.waveform` + the painter's
 * line-rendering constants. `minNorm` is the normalised floor
 * (`minBarHeightPx 3 / waveformMaxHeight 24`).
 */
export const OVERLAY_WAVEFORM = {
  barCount: 22,
  activeCount: 5, // trailing bars drawn bright (painter: i > count - 5)
  activeOpacity: 0.95,
  mutedOpacity: 0.5,
  heightFactor: 0.6, // loudest bar reaches 60 % of pill height
  lineStrokeFactor: 0.5,
  minNorm: 3 / 24, // minBarHeightPx / waveformMaxHeight = 0.125
} as const;

/**
 * Capsule chrome + content opacities, from `OverlayDesignSpec`. The mockup
 * renders at full master opacity (1.0), so the fill alpha is `fillOpacity`.
 */
export const OVERLAY_CHROME = {
  fillOpacity: 0.92,
  borderOpacity: 0.2, // capsuleBorder alpha 0x33 / 255 ≈ 0.20
  shadowOpacity: 0.2,
  shadowBlur: 7,
  shadowDy: 3,
  dotMinAlpha: 0.6, // motion.dotPulseMinAlpha
  timelineInsetBottom: 6,
  timelineStroke: 2,
  timelineEndOpacity: 0.25,
  stopRadius: 2,
  stopOpacity: 0.9,
} as const;

/**
 * Waveform attack/release smoothing, from `WaveformSpec`. Tick cadence matches
 * the app's animation timer.
 */
export const OVERLAY_WAVEFORM_MOTION = {
  tickMs: 90,
  attackMs: 20, // attackTimeConstantMs — fast rise (volume-faithful onset)
  releaseMs: 300, // releaseTimeConstantMs — slow fall (silence decays, no jitter)
} as const;

/**
 * Deterministic 22-bar waveform snapshot used for the frozen (reduced-motion)
 * frame and the cross-engine parity baseline — the exact pattern the parity
 * spike verified. Index 0 is the oldest (left) bar, index 21 the newest (right).
 */
export const FROZEN_BARS: readonly number[] = [
  0.06, 0.1, 0.22, 0.45, 0.3, 0.12, 0.07, 0.18, 0.55, 0.8, 0.62, 0.28, 0.1,
  0.09, 0.4, 0.72, 0.95, 0.7, 0.35, 0.14, 0.58, 0.85,
];

/** One immutable overlay frame to draw. */
export interface OverlayFrame {
  readonly theme: OverlayTheme;
  /** Normalised bar levels [0, 1]; index 0 = oldest (left), last = newest (right). */
  readonly bars: readonly number[];
  /** Pre-formatted recording timer, e.g. `0:07`. */
  readonly timerText: string;
  /** Recording progress 0–1; 0 hides the timeline. */
  readonly progress: number;
  /** Recording-dot pulse phase 0–1. */
  readonly dotPulse: number;
}

const clamp01 = (v: number): number => (v < 0 ? 0 : v > 1 ? 1 : v);

/** Parses `#RRGGBB` into an `rgba(...)` string at the given alpha. */
function rgba(hex: string, alpha: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

/** Traces a rounded-rectangle path (arcTo form, identical across engines). */
function roundRectPath(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/**
 * The scrolling-history waveform model (issue 04), reimplemented for the web.
 *
 * Each `tick` smooths a running level toward the live sample with an asymmetric
 * time constant (fast attack, slow release), then pushes it onto the right edge
 * and drops the leftmost bar — so samples scroll right→left, the amplitude is
 * volume-faithful, and sustained silence decays to the floor with no perpetual
 * jitter. Mirrors `lib/services/floating_overlay/waveform_pipeline.dart`.
 */
export class WaveformHistory {
  private readonly bars: number[];
  private level: number;

  constructor(
    private readonly count: number = OVERLAY_WAVEFORM.barCount,
    private readonly floor: number = OVERLAY_WAVEFORM.minNorm,
    private readonly tickMs: number = OVERLAY_WAVEFORM_MOTION.tickMs,
    private readonly attackMs: number = OVERLAY_WAVEFORM_MOTION.attackMs,
    private readonly releaseMs: number = OVERLAY_WAVEFORM_MOTION.releaseMs,
  ) {
    this.level = floor;
    this.bars = new Array<number>(count).fill(floor);
  }

  /** Advances one frame with the live [0, 1] sample. */
  tick(raw: number): void {
    const target = Math.max(this.floor, clamp01(raw));
    const tc = target > this.level ? this.attackMs : this.releaseMs;
    const alpha = 1 - Math.exp(-this.tickMs / tc);
    this.level += (target - this.level) * alpha;
    this.bars.shift();
    this.bars.push(this.level);
  }

  /** Current bars, oldest (left) → newest (right). */
  values(): number[] {
    return this.bars.slice();
  }

  /** Bars scaled to pixel heights for a given max bar height — proves
   * compact = scaled (same data × a smaller max), not a reduced bar set. */
  barHeights(maxHeightPx: number): number[] {
    return this.bars.map((v) => v * maxHeightPx);
  }

  /** Resets every bar to the silent floor. */
  reset(): void {
    this.level = this.floor;
    for (let i = 0; i < this.count; i++) {
      this.bars[i] = this.floor;
    }
  }
}

/**
 * Draws one overlay frame onto a DPR-scaled 2D context. The caller sizes the
 * canvas (`width/height = (pill + 2·shadowPad)·dpr`) and applies
 * `setTransform(dpr,0,0,dpr,0,0)` once; this function draws in CSS pixels.
 *
 * The layer order mirrors `OverlayPainter.paint`: painted shadow → tint fill →
 * accent hairline border → clipped opaque content (close ✕, pulsing accent dot,
 * timer, accent line-bars with the trailing few bright, dark stop square,
 * inset accent progress timeline).
 */
export function drawOverlayPill(
  ctx: CanvasRenderingContext2D,
  frame: OverlayFrame,
): void {
  const g = OVERLAY_GEOMETRY;
  const w = OVERLAY_WAVEFORM;
  const c = OVERLAY_CHROME;
  const tok = OVERLAY_TOKENS[frame.theme];

  const pad = g.shadowPad;
  const x = pad;
  const y = pad;
  const W = g.width;
  const H = g.height;
  const radius = g.capsuleRadius;
  const cy = y + H / 2;
  const cssW = W + pad * 2;
  const cssH = H + pad * 2;

  ctx.clearRect(0, 0, cssW, cssH);

  // ── Painted soft shadow (MaskFilter.blur sigma 7, offset +3y) ──
  ctx.save();
  ctx.filter = `blur(${c.shadowBlur}px)`;
  roundRectPath(ctx, x + 1, y + 1 + c.shadowDy, W - 2, H - 2, radius);
  ctx.fillStyle = `rgba(0,0,0,${c.shadowOpacity})`;
  ctx.fill();
  ctx.restore();

  // ── Tint fill (the only translucent chrome layer) ──
  const grad = ctx.createLinearGradient(x, y, x + W, y + H);
  grad.addColorStop(0, rgba(tok.fillStart, c.fillOpacity));
  grad.addColorStop(1, rgba(tok.fillEnd, c.fillOpacity));
  roundRectPath(ctx, x + 1, y + 1, W - 2, H - 2, radius);
  ctx.fillStyle = grad;
  ctx.fill();

  // ── Accent hairline border ──
  ctx.strokeStyle = rgba(tok.accent, c.borderOpacity);
  ctx.lineWidth = 1;
  ctx.stroke();

  // ── Opaque content, clipped to the capsule ──
  ctx.save();
  roundRectPath(ctx, x + 1, y + 1, W - 2, H - 2, radius);
  ctx.clip();

  const base = x + g.padH;

  // Close ✕
  const closeX = base + g.closeOffset;
  const arm = g.closeArm;
  ctx.strokeStyle = rgba(tok.content, 0.7);
  ctx.lineWidth = g.closeStroke;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(closeX - arm, cy - arm);
  ctx.lineTo(closeX + arm, cy + arm);
  ctx.moveTo(closeX + arm, cy - arm);
  ctx.lineTo(closeX - arm, cy + arm);
  ctx.stroke();

  // Pulsing accent recording dot
  const dotX = base + g.dotInset;
  const dotAlpha = c.dotMinAlpha + (1 - c.dotMinAlpha) * clamp01(frame.dotPulse);
  ctx.fillStyle = rgba(tok.accent, dotAlpha);
  ctx.beginPath();
  ctx.arc(dotX, cy, g.dotRadius, 0, Math.PI * 2);
  ctx.fill();

  // Timer text
  ctx.fillStyle = rgba(tok.content, 1);
  ctx.font = `600 ${g.timerFontSize}px system-ui, -apple-system, "Segoe UI", sans-serif`;
  ctx.textBaseline = 'middle';
  const textLeft = dotX + g.timerGap;
  ctx.fillText(frame.timerText, textLeft, cy);
  const textWidth = ctx.measureText(frame.timerText).width;

  // Waveform line-bars (trailing few bright, rest muted)
  const waveLeft = textLeft + textWidth + g.waveStartGap;
  const waveRight = x + W - g.padH - g.stopSize - g.waveEndGap;
  const waveW = waveRight - waveLeft;
  if (waveW > 20) {
    const count = w.barCount;
    const barW = waveW / count;
    const maxH = H * w.heightFactor;
    ctx.lineCap = 'round';
    ctx.lineWidth = Math.max(g.lineStrokeMin, barW * w.lineStrokeFactor);
    for (let i = 0; i < count; i++) {
      const level = clamp01(frame.bars[i] ?? 0);
      const bh = level * maxH;
      const bx = waveLeft + i * barW + barW / 2;
      const active = i > count - w.activeCount;
      ctx.strokeStyle = rgba(tok.accent, active ? w.activeOpacity : w.mutedOpacity);
      ctx.beginPath();
      ctx.moveTo(bx, cy - bh / 2);
      ctx.lineTo(bx, cy + bh / 2);
      ctx.stroke();
    }
  }

  // Dark stop square
  const stopX = x + W - g.padH - g.stopSize;
  roundRectPath(ctx, stopX, cy - g.stopSize / 2, g.stopSize, g.stopSize, c.stopRadius);
  ctx.fillStyle = rgba(tok.content, c.stopOpacity);
  ctx.fill();

  // Inset accent progress timeline
  const progress = clamp01(frame.progress);
  if (progress > 0) {
    const lineY = y + H - c.timelineInsetBottom;
    const lineL = x + radius;
    const lineR = x + W - radius;
    const tlGrad = ctx.createLinearGradient(lineL, 0, lineR, 0);
    tlGrad.addColorStop(0, rgba(tok.accent, 1));
    tlGrad.addColorStop(1, rgba(tok.accent, c.timelineEndOpacity));
    ctx.strokeStyle = tlGrad;
    ctx.lineWidth = c.timelineStroke;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(lineL, lineY);
    ctx.lineTo(lineL + (lineR - lineL) * progress, lineY);
    ctx.stroke();
  }

  ctx.restore();
}
