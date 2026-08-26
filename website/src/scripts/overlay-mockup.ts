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
 * CSS `backdrop-filter`/`box-shadow`/gradients diverge per engine (ADR 0002).
 *
 * The app ships two overlay chromes (`OverlayStyleVariant`, Settings:
 * "Overlay-Stil") and this file mirrors both, but the website only ever
 * paints **solid** (2026-08-26, maintainer: no glass/frost material anywhere
 * on the site) — see {@link RENDER_GLASS_SHEEN}:
 *
 *   - `solid` (what the site renders): fully opaque pill filled with the
 *     app's own {@link OVERLAY_SOLID_FILL} (verbatim `WpColorsDark
 *     .frameGradient`, the same navy→violet arc the app's title bar/nav
 *     rail/status bar paint) — no sheen, no rim light, no specular drift;
 *   - `glass` (mirrored, not rendered): near-clear capsule fill
 *     (`fillOpacityFactor 0.14`) plus a Fresnel edge treatment — bright 1 px
 *     top rim, soft inner rim band, a crisp specular streak with a dark
 *     under-halo — and an 8 s "glass drift" loop (the streak drifts ±12 px
 *     and breathes in length/brightness, the rim breathes);
 *   - shared by both styles: the two-layer painted shadow (soft ambient +
 *     tight contact), knocked out underneath the capsule; the liquid
 *     silhouette wobble (two slow "wind" waves plus a faster audio-reactive
 *     ripple, Catmull-Rom smoothed over 28 perimeter samples) — phase 0
 *     renders the exact static baseline frame (reduced-motion / parity
 *     golden); universal-legibility glyphs (timer/status text, close ✕ and
 *     stop square render WHITE over a soft dark drop shadow — the overlay
 *     floats over arbitrary desktops without OS blur, so no single ink
 *     colour works on its own); the mirrored-bar waveform (fully opaque
 *     filled capsules with the "energy axis" in-bar gradient — bright core,
 *     shaded tips); all four recording-arc states (recording / transcribing
 *     / done / error) with their state-dependent pill-width targets.
 *
 * Every constant below is copied verbatim from `OverlayDesignSpec` (normal-size
 * pill; the SSOT declares one single capsule design for both themes). There are
 * deliberately no invented values: change the Dart SSOT, then mirror it here.
 *
 * The module has no top-level DOM access, so the pure parts (tokens,
 * {@link WaveformHistory}, {@link Spring}, the wobble waves and the width
 * helpers) are unit-testable under Node/Vitest. Only {@link drawOverlayPill}
 * touches a canvas context, and it is never called at import time.
 *
 * NOTE: unlike the previous revision, {@link drawOverlayPill} does NOT clear
 * the canvas — the caller owns clearing (and any appear-scale/fade transform),
 * because a state-transition crossfade draws the fill layer once and the two
 * content layers at different alphas onto the same frame.
 */

/** Theme variants the mockup mirrors — same two the app SSOT defines. */
export type OverlayTheme = 'light' | 'dark';

/** The four real recording-arc states (`OverlayDesignState`). */
export type OverlayState = 'recording' | 'transcribing' | 'done' | 'error';

/** One theme-resolved colour set (verbatim from `OverlayDesignSpec`). */
export interface OverlayThemeTokens {
  /** Capsule tint gradient top-left stop. */
  readonly fillStart: string;
  /** Capsule tint gradient bottom-right stop. */
  readonly fillEnd: string;
  /** Accent — recording dot, waveform bars, progress timeline, hairline border. */
  readonly accent: string;
  /** Content ink — since the universal-legibility scheme this is the dark
   * SHADOW behind the white glyphs, no longer the glyph fill. */
  readonly content: string;
  /** Success colour — the done checkmark. */
  readonly success: string;
  /** Error colour — the error status icon. */
  readonly error: string;
}

/**
 * Light + dark colour sets, copied from `OverlayDesignSpec.light` /
 * `OverlayDesignSpec.dark`. The light tint-fill is the canonical capsule
 * (`#F7FAFD → #E6EEF5`) named in the design spec.
 */
export const OVERLAY_TOKENS: Readonly<Record<OverlayTheme, OverlayThemeTokens>> = {
  light: {
    fillStart: '#F7FAFD', // OverlayDesignSpec.light.capsuleFillStart
    fillEnd: '#E6EEF5', //   OverlayDesignSpec.light.capsuleFillEnd
    accent: '#0887A8', //    OverlayDesignSpec.light.accent
    content: '#14202E', //   OverlayDesignSpec.light.text (glyph SHADOW ink)
    success: '#05875C', //   OverlayDesignSpec.light.success
    error: '#CC1C1C', //     OverlayDesignSpec.light.error
  },
  // The SSOT declares `dark = light` — one single capsule design renders
  // identically over light AND dark desktops (OverlayDesignSpec: "There is
  // deliberately no separate dark capsule variant").
  dark: {
    fillStart: '#F7FAFD', // OverlayDesignSpec.dark.capsuleFillStart (= light)
    fillEnd: '#E6EEF5', //   OverlayDesignSpec.dark.capsuleFillEnd   (= light)
    accent: '#0887A8', //    OverlayDesignSpec.dark.accent            (= light)
    content: '#14202E', //   OverlayDesignSpec.dark.text              (= light)
    success: '#05875C', //   OverlayDesignSpec.dark.success           (= light)
    error: '#CC1C1C', //     OverlayDesignSpec.dark.error             (= light)
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
  statusIconSize: 16, // OverlaySizeSpec.normal.statusIconSize
} as const;

/** The exact text style `OverlayPainter._drawText` paints with (weight 600). */
export const OVERLAY_TEXT_FONT = `600 ${OVERLAY_GEOMETRY.timerFontSize}px system-ui, -apple-system, "Segoe UI", sans-serif`;

/**
 * Capsule chrome opacities + two-layer shadow, from `OverlayDesignSpec`. The
 * mockup renders at full master opacity (1.0), so the fill alpha is
 * `fillOpacity` (= `fillOpacityFactor`, the Dock-glass near-clear fill).
 */
export const OVERLAY_CHROME = {
  fillOpacity: 0.14, //         fillOpacityFactor (Dock-glass, 2026-07-29)
  borderOpacity: 0.2, //        capsuleBorder alpha 0x33 / 255 ≈ 0.20
  // Two-layer ambient depth (mirrors WpShadows.card): a soft wide-blur layer
  // plus a tight contact shadow. Both knocked out under the capsule.
  shadowOpacity: 0.2, //        shadowOpacity
  shadowBlur: 9, //             shadowBlur (Gaussian sigma)
  shadowDy: 3, //               shadowOffset.dy
  contactShadowOpacity: 0.12, //contactShadowOpacity
  contactShadowBlur: 2, //      contactShadowBlur (Gaussian sigma)
  contactShadowDy: 1, //        contactShadowOffset.dy
  dotMinAlpha: 0.6, //          motion.dotPulseMinAlpha
  dotMinScale: 0.88, //         motion.dotPulseMinScale
  timelineInsetBottom: 6,
  timelineStroke: 2,
  timelineEndOpacity: 0.25,
  timelineLeadDotRadius: 2.2, //timelineLeadDotRadius
  stopRadius: 2,
  stopOpacity: 0.9,
} as const;

/**
 * Fill for `OverlayStyleVariant.solid` — verbatim `WpColorsDark.frameGradient`
 * (`lib/core/theme/colors.dart`), the same navy→violet arc the app's title
 * bar/nav rail/status bar paint. Painted fully opaque (no `fillOpacity`),
 * unlike `OVERLAY_TOKENS`' near-clear glass tint: "no sheen, no rim light, no
 * specular drift... the fill is the app's own frame gradient instead of a
 * near-clear tint" (`OverlayStyleVariant.solid` doc comment). Theme-invariant,
 * same precedent as `OVERLAY_TOKENS` (`dark = light`) — the SSOT declares one
 * gradient, not a per-theme pair.
 */
export const OVERLAY_SOLID_FILL = {
  colors: ['#051A3E', '#071144', '#0E0941', '#140A2F'],
  stops: [0, 0.42, 0.74, 1.0],
} as const;

/**
 * The maintainer has ruled the Dock-glass sheen/rim/specular stack out
 * sitewide (2026-08-26) — the website shows the app's real `solid` overlay
 * style, not `glass`. {@link drawGlassSheen} still mirrors the SSOT's glass
 * constants verbatim (kept in step with `OverlayDesignSpec`, covered by the
 * AC1 unit tests); this switch is the one place that decides whether
 * {@link drawOverlayPill} actually paints it.
 */
const RENDER_GLASS_SHEEN = false;

/**
 * Faux-glass highlight layers (Fresnel edge treatment + specular streak), from
 * the `OverlayDesignSpec` glass constants. All neutral white/dark — the chrome
 * carries no state colour anywhere (ADR 0002: no glow, no colour bleed).
 */
export const OVERLAY_GLASS = {
  sheenOpacity: 0.15, //          glassSheenOpacity
  sheenStops: [0, 0.32, 0.55], // glassSheenStops (bright → soft → clear)
  bottomSheenFactor: 0.25, //     glassBottomSheenFactor
  bottomSheenStops: [0.78, 1], // glassBottomSheenStops
  innerShadeOpacity: 0.04, //     glassInnerShadeOpacity
  innerShadeStops: [0.85, 1], //  glassInnerShadeStops
  rimTopOpacity: 0.55, //         glassRimTopOpacity (1 px outer rim, lit from above)
  rimBottomOpacity: 0.1, //       glassRimBottomOpacity
  innerRimWidth: 2.5, //          glassInnerRimWidth (soft inner Fresnel band)
  innerRimInset: 1.25, //         glassInnerRimInset
  innerRimOpacity: 0.1, //        glassInnerRimOpacity
  specularOpacity: 0.5, //        glassSpecularOpacity
  specularStrokeWidth: 2.6, //    glassSpecularStrokeWidth
  specularWidthFactor: 0.55, //   glassSpecularWidthFactor (× pill width)
  specularInsetTop: 5.5, //       glassSpecularInsetTop
  specularHaloOpacity: 0.16, //   glassSpecularHaloOpacity (dark under-halo)
  specularHaloBlur: 2, //         glassSpecularHaloBlurSigma
  specularHaloStrokeWidth: 5, //  glassSpecularHaloStrokeWidth
  specularHaloOffsetY: 1.5, //    glassSpecularHaloOffsetY
} as const;

/**
 * Liquid-glass motion parameters (drift loop + silhouette wobble), from the
 * `OverlayDesignSpec` liquid constants. Phase 0 renders EXACTLY the static
 * frame — reduced-motion and the parity golden live there.
 */
export const OVERLAY_LIQUID = {
  driftPeriodMs: 8000, //            liquidDriftPeriod (8 s loop)
  specularDriftPx: 12, //            liquidSpecularDriftPx (±12 px, anchored — no sweep)
  sheenParallaxFactor: 0.5, //       liquidSheenParallaxFactor (depth cue)
  specularBreatheFactor: 0.18, //    liquidSpecularBreatheFactor (±18 % length)
  specularBrightBreatheFactor: 0.25, // liquidSpecularBrightBreatheFactor (±25 % alpha)
  rimBreatheFactor: 0.15, //         liquidRimBreatheFactor
  wobbleBaseAmplitudePx: 1.2, //     liquidWobbleBaseAmplitudePx ("Windhauch")
  wobbleAudioAmplitudePx: 2.4, //    liquidWobbleAudioAmplitudePx (louder = more ripple)
  wobbleSamples: 28, //              liquidWobbleSamples (Catmull-Rom smoothed)
} as const;

/**
 * Universal-legibility glyph scheme (`OverlayDesignSpec`, final: soft shadow,
 * 2026-07-30): all neutral content glyphs (timer/status text, close ✕, stop
 * square) render WHITE over a soft blurred dark drop shadow — readable over
 * any desktop behind the near-clear glass. The dot, waveform and done/error
 * icons keep their semantic mid-tone colours (≥3:1 against both extremes).
 */
export const OVERLAY_GLYPH = {
  fill: '#FFFFFF', //       contentGlyphFill
  shadowColor: '#14202E', //glyphShadowColor
  shadowOpacity: 0.85, //   glyphShadowOpacity
  shadowBlur: 1.75, //      glyphShadowBlurSigma
  shadowDy: 0.75, //        glyphShadowOffset.dy
} as const;

/**
 * Waveform render parameters, from `OverlayDesignSpec.waveform` + the painter's
 * mirrored-bar constants (Maintainer decision, 2026-07-29: fully opaque filled
 * capsules mirrored around the centre axis, "energy axis" in-bar gradient —
 * bright core at the centre line, shaded tips; the trailing playhead bars are
 * wider with a hotter core, never a washed-out history). `minNorm` is the
 * normalised floor (`minBarHeightPx 3 / waveformMaxHeight 24`).
 */
export const OVERLAY_WAVEFORM = {
  barCount: 22,
  activeCount: 5, //              trailing bars drawn as playhead (i > count − 5)
  activeOpacity: 1, //            waveformActiveOpacity — fully opaque
  mutedOpacity: 1, //             waveformMutedLineOpacity — also fully opaque
  inactiveStateOpacity: 0.5, //   waveformInactiveStateOpacity (rest waveform)
  barFillFactor: 0.62, //         waveformBarFillFactor (× per-bar slot)
  activeBarFillFactor: 0.74, //   waveformActiveBarFillFactor (wider playhead)
  levelGamma: 0.65, //            waveformLevelGamma (perceptual display gamma)
  coreMutedLightFraction: 0.1, // waveformCoreMutedLightFraction
  coreActiveLightFraction: 0.35, // waveformCoreActiveLightFraction (hotter core)
  tipShadeFraction: 0.15, //      waveformTipShadeFraction
  heightFactor: 0.6, //           loudest bar reaches 60 % of pill height
  restLevel: 0.06, //             waveformRestLevel (flat rest waveform)
  minBarHeightPx: 3, //           waveform.minBarHeightPx
  minNorm: 3 / 24, //             minBarHeightPx / waveformMaxHeight = 0.125
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
 * Signature recording-arc motion (`OverlayArcMotion`): appear spring, state
 * crossfade and the pill-width spring parameters.
 */
export const OVERLAY_ARC = {
  appearMs: 300, //          appearDuration (easeOutCubic, no overshoot)
  appearScale: 0.88, //      appearScale (0.88 → 1.0 + fade-in)
  stateTransitionMs: 150, // stateTransitionDuration (generic crossfade)
  releaseOutMs: 300, //      releaseOutDuration (recording → transcribing only;
  //                         mirrors waveformReleaseOutMs — the outgoing layer
  //                         is the only one painting live waveform decay, so
  //                         the generic 150 ms crossfade cut it off mid-motion)
  statusRevealMs: 280, //    statusRevealDuration (into done/error)
  spring: { mass: 1, stiffness: 170, damping: 26 }, // pillSpring (Gentle preset)
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
  /** Recording-arc state; drives content, icons and (via callers) pill width. */
  readonly state: OverlayState;
  /** Normalised bar levels [0, 1]; index 0 = oldest (left), last = newest (right). */
  readonly bars: readonly number[];
  /** Pre-formatted recording timer, e.g. `0:07` (drawn while recording). */
  readonly timerText: string;
  /** Status text: transcribing label / done / error message (non-recording). */
  readonly statusText: string;
  /** Recording progress 0–1; 0 hides the timeline (recording only). */
  readonly progress: number;
  /** Recording-dot pulse phase 0–1. */
  readonly dotPulse: number;
  /** Liquid-glass drift phase [0, 1); 0 = static baseline frame. */
  readonly glassPhase?: number;
  /** Master switch/scale [0, 1] for the silhouette wobble; 0 = rigid capsule. */
  readonly liquidMotion?: number;
  /** Smoothed live audio level [0, 1] — louder speech ⇒ more ripple. */
  readonly liquidLevel?: number;
  /** Animated pill width (logical px), centred; defaults to the full width. */
  readonly pillWidth?: number;
  /** Done/error icon draw-on fraction [0, 1]; defaults to fully drawn. */
  readonly iconReveal?: number;
}

/** Which layers {@link drawOverlayPill} paints (state-crossfade split). */
export interface OverlayDrawLayers {
  /** Capsule fill layer (shadow, glass, border). Default true. */
  readonly fill?: boolean;
  /** Content layer (glyphs, waveform, timeline). Default true. */
  readonly content?: boolean;
}

const clamp01 = (v: number): number => (v < 0 ? 0 : v > 1 ? 1 : v);

const TAU = Math.PI * 2;

/** easeOutCubic — `OverlayArcMotion.appearCurve` (WpMotion.spring, no overshoot). */
export const easeOutCubic = (t: number): number => 1 - Math.pow(1 - clamp01(t), 3);

/**
 * Base "Windhauch" silhouette wave (mirrors `OverlayPainter._liquidShape`):
 * two slow counter-travelling low-frequency waves (2 and 3 perimeter periods;
 * 1 and 2 time-cycles per loop — integer cycles keep the wrap seamless).
 */
export function wobbleWind(u: number, phase: number): number {
  return (
    Math.sin(TAU * (2 * u + phase)) * 0.6 +
    Math.sin(TAU * (3 * u - 2 * phase) + 1.7) * 0.4
  );
}

/**
 * Audio-reactive ripple — its OWN faster, finer waveform (5 perimeter
 * periods, 6 time-cycles per loop) so the voice reaction reads as a distinct
 * component, not just "more wind".
 */
export function wobbleRipple(u: number, phase: number): number {
  return Math.sin(TAU * (5 * u - 6 * phase));
}

/**
 * Width ratio per state, from `OverlayDesignSpec.pillWidthRatio` (issue 10 —
 * dynamic pill growth): recording 1.0, transcribing/error 0.758, done 0.606.
 */
export function pillWidthRatio(state: OverlayState): number {
  switch (state) {
    case 'recording':
      return 1.0;
    case 'transcribing':
      return 0.758;
    case 'done':
      return 0.606;
    case 'error':
      return 0.758;
  }
}

/**
 * Target pill width for `state`, grown just enough to fit `text` without an
 * ellipsis and clamped to the full width — mirrors
 * `OverlayDesignSpec.pillWidthForText`. `measure` supplies the laid-out text
 * width (canvas `measureText` at {@link OVERLAY_TEXT_FONT}); injected so the
 * function stays pure/Node-testable.
 */
export function pillWidthForText(
  state: OverlayState,
  text: string,
  measure: (text: string) => number,
): number {
  const g = OVERLAY_GEOMETRY;
  const base = g.width * pillWidthRatio(state);
  if (!text) return base;
  // Mirrors OverlayPainter._drawContent's textLeft/maxTextWidth geometry.
  const required = measure(text) + 2 * g.padH + g.dotInset + g.timerGap;
  return Math.min(Math.max(required, base), g.width);
}

/**
 * The pill-width spring (`OverlayArcMotion.pillSpring`): critically-damped
 * Gentle preset (mass 1, stiffness 170, damping 26 ≈ 2√170) — no overshoot,
 * a clean soft width morph between recording-arc states.
 *
 * Integrated with semi-implicit Euler in small sub-steps so a 30 fps frame
 * cadence stays numerically stable. Pure (no DOM) — unit-testable.
 */
export class Spring {
  private pos: number;
  private vel = 0;
  private targetValue: number;

  constructor(
    initial: number,
    private readonly config: {
      readonly mass: number;
      readonly stiffness: number;
      readonly damping: number;
    } = OVERLAY_ARC.spring,
  ) {
    this.pos = initial;
    this.targetValue = initial;
  }

  /** Current animated value. */
  get value(): number {
    return this.pos;
  }

  /** Current target. */
  get target(): number {
    return this.targetValue;
  }

  /** Retargets the spring; position/velocity carry over (smooth interrupt). */
  setTarget(v: number): void {
    this.targetValue = v;
  }

  /** Hard-snaps to `v` (reduced-motion / episode reset — no animation). */
  snapTo(v: number): void {
    this.pos = v;
    this.vel = 0;
    this.targetValue = v;
  }

  /** Advances the simulation by `dtMs` milliseconds. */
  step(dtMs: number): void {
    const dt = Math.min(Math.max(dtMs, 0), 100) / 1000;
    if (dt === 0) return;
    const steps = Math.max(1, Math.ceil(dt / 0.004));
    const h = dt / steps;
    const { mass, stiffness, damping } = this.config;
    for (let i = 0; i < steps; i++) {
      const a = (-stiffness * (this.pos - this.targetValue) - damping * this.vel) / mass;
      this.vel += a * h;
      this.pos += this.vel * h;
    }
  }

  /** True once the spring has visually come to rest at its target. */
  get settled(): boolean {
    return Math.abs(this.pos - this.targetValue) < 0.05 && Math.abs(this.vel) < 0.05;
  }
}

/** Parses `#RRGGBB` into an `rgba(...)` string at the given alpha. */
function rgba(hex: string, alpha: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

/** Channel-wise sRGB mix of two `#RRGGBB` colours (mirrors `Color.lerp`). */
function mixRgba(hexA: string, hexB: string, t: number, alpha: number): string {
  const ch = (o: number): number => {
    const a = parseInt(hexA.slice(o, o + 2), 16);
    const b = parseInt(hexB.slice(o, o + 2), 16);
    return Math.round(a + (b - a) * t);
  };
  return `rgba(${ch(1)},${ch(3)},${ch(5)},${alpha})`;
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

/** One perimeter sample: position + unit tangent (clockwise walk). */
interface PerimeterSample {
  readonly px: number;
  readonly py: number;
  readonly tx: number;
  readonly ty: number;
}

function arcSample(cx: number, cy: number, r: number, a: number): PerimeterSample {
  return {
    px: cx + r * Math.cos(a),
    py: cy + r * Math.sin(a),
    tx: -Math.sin(a),
    ty: Math.cos(a),
  };
}

/**
 * Samples `n` equidistant points (position + tangent) along the rounded-rect
 * perimeter, walking clockwise from the top-left corner's end — the web
 * equivalent of Flutter's `PathMetrics.getTangentForOffset` over the capsule.
 */
function perimeterSamples(
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
  n: number,
): PerimeterSample[] {
  const sw = Math.max(0, w - 2 * r);
  const sh = Math.max(0, h - 2 * r);
  const arc = (Math.PI / 2) * r;
  // Clockwise: top edge, TR arc, right edge, BR arc, bottom edge, BL arc,
  // left edge, TL arc.
  const segs = [sw, arc, sh, arc, sw, arc, sh, arc];
  const total = segs.reduce((a, b) => a + b, 0);
  const out: PerimeterSample[] = [];
  for (let i = 0; i < n; i++) {
    let s = (i / n) * total;
    let k = 0;
    while (k < segs.length - 1 && s >= segs[k]) {
      s -= segs[k];
      k += 1;
    }
    switch (k) {
      case 0:
        out.push({ px: x + r + s, py: y, tx: 1, ty: 0 });
        break;
      case 1:
        out.push(arcSample(x + w - r, y + r, r, -Math.PI / 2 + s / r));
        break;
      case 2:
        out.push({ px: x + w, py: y + r + s, tx: 0, ty: 1 });
        break;
      case 3:
        out.push(arcSample(x + w - r, y + h - r, r, s / r));
        break;
      case 4:
        out.push({ px: x + w - r - s, py: y + h, tx: -1, ty: 0 });
        break;
      case 5:
        out.push(arcSample(x + r, y + h - r, r, Math.PI / 2 + s / r));
        break;
      case 6:
        out.push({ px: x, py: y + h - r - s, tx: 0, ty: -1 });
        break;
      default:
        out.push(arcSample(x + r, y + r, r, Math.PI + s / r));
        break;
    }
  }
  return out;
}

/**
 * Builds the (possibly liquid-deformed) capsule outline as a `Path2D` —
 * mirrors `OverlayPainter._liquidShape`. Both amplitudes 0 returns the plain
 * rigid capsule (static baseline). Otherwise each of the 28 perimeter samples
 * is displaced along its outward normal by the wind + ripple waves and the
 * result is closed with Catmull-Rom smoothing (uniform, tension 0.5 →
 * standard `(p2 − p0) / 6` cubic control points) — organic bulges, never
 * jitter.
 */
function liquidShapePath(
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
  baseAmp: number,
  audioAmp: number,
  phase: number,
): Path2D {
  const path = new Path2D();
  if (baseAmp <= 0 && audioAmp <= 0) {
    path.moveTo(x + r, y);
    path.arcTo(x + w, y, x + w, y + h, r);
    path.arcTo(x + w, y + h, x, y + h, r);
    path.arcTo(x, y + h, x, y, r);
    path.arcTo(x, y, x + w, y, r);
    path.closePath();
    return path;
  }

  const n = OVERLAY_LIQUID.wobbleSamples;
  const samples = perimeterSamples(x, y, w, h, r, n);
  const pts = samples.map((smp, i) => {
    const u = i / n;
    // Normal = (tangent.y, −tangent.x) — outward for the clockwise walk.
    const d = baseAmp * wobbleWind(u, phase) + audioAmp * wobbleRipple(u, phase);
    return { x: smp.px + smp.ty * d, y: smp.py - smp.tx * d };
  });

  path.moveTo(pts[0].x, pts[0].y);
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n];
    const p1 = pts[i];
    const p2 = pts[(i + 1) % n];
    const p3 = pts[(i + 2) % n];
    path.bezierCurveTo(
      p1.x + (p2.x - p0.x) / 6,
      p1.y + (p2.y - p0.y) / 6,
      p2.x - (p3.x - p1.x) / 6,
      p2.y - (p3.y - p1.y) / 6,
      p2.x,
      p2.y,
    );
  }
  path.closePath();
  return path;
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

/** Truncates `text` with an ellipsis to fit `maxWidth` at the current font. */
function ellipsize(
  ctx: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
): string {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let t = text;
  while (t.length > 1 && ctx.measureText(`${t}…`).width > maxWidth) {
    t = t.slice(0, -1);
  }
  return `${t}…`;
}

/**
 * Draws one overlay frame onto a DPR-scaled 2D context. The caller sizes the
 * canvas (`width/height = (pill + 2·shadowPad)·dpr`), applies
 * `setTransform(dpr,0,0,dpr,0,0)` and **clears the canvas**; this function
 * draws in CSS pixels and never clears (see module doc — the crossfade paints
 * multiple layers into one frame). Any appear-scale/fade transform is also the
 * caller's (it multiplies via `ctx.globalAlpha`, which this renderer never
 * overwrites).
 *
 * The layer order mirrors `OverlayPainter.paint`: two-layer knocked-out shadow
 * → near-clear tint fill → glass sheen stack (top sheen, inner shade, bottom
 * counter-sheen, inner Fresnel band, specular halo + streak, lit outer rim) →
 * accent hairline border → clipped opaque content (close ✕, state glyph,
 * white text over soft dark shadow, mirrored-bar waveform, white stop square,
 * inset accent progress timeline with lead dot).
 */
export function drawOverlayPill(
  ctx: CanvasRenderingContext2D,
  frame: OverlayFrame,
  layers: OverlayDrawLayers = {},
): void {
  const g = OVERLAY_GEOMETRY;
  const paintFill = layers.fill ?? true;
  const paintContent = layers.content ?? true;

  const pad = g.shadowPad;
  const H = g.height;
  const effW = Math.min(Math.max(frame.pillWidth ?? g.width, 2), g.width);
  // Dynamic pill width: narrower pills are centred so both sides shrink
  // symmetrically (mirrors OverlayPainter.paint).
  const x = pad + (g.width - effW) / 2;
  const y = pad;

  const glassPhase = frame.glassPhase ?? 0;
  const liquidMotion = clamp01(frame.liquidMotion ?? 0);
  const baseAmp = liquidMotion * OVERLAY_LIQUID.wobbleBaseAmplitudePx;
  const audioAmp =
    liquidMotion *
    OVERLAY_LIQUID.wobbleAudioAmplitudePx *
    clamp01(frame.liquidLevel ?? 0);

  // The painter builds the RRect from pill.deflate(1); the 32 px radius is
  // clamped to the deflated half-height (31).
  const rx = x + 1;
  const ry = y + 1;
  const rw = effW - 2;
  const rh = H - 2;
  const rr = Math.min(g.capsuleRadius, rh / 2, rw / 2);
  const shape = liquidShapePath(rx, ry, rw, rh, rr, baseAmp, audioAmp, glassPhase);

  if (paintFill) {
    drawShadow(ctx, shape, x, y, effW, H);
    drawFill(ctx, shape, x, y, effW, H);
    if (RENDER_GLASS_SHEEN) {
      drawGlassSheen(
        ctx,
        shape,
        { rx, ry, rw, rh, rr, baseAmp, audioAmp, glassPhase },
        x,
        y,
        effW,
        H,
      );
    }
    // Accent hairline border — deliberately state-NEUTRAL (the chrome carries
    // no state colour anywhere; state identity lives in the content glyphs).
    ctx.strokeStyle = rgba(OVERLAY_TOKENS[frame.theme].accent, OVERLAY_CHROME.borderOpacity);
    ctx.lineWidth = 1;
    ctx.stroke(shape);
  }

  if (paintContent) {
    ctx.save();
    ctx.clip(shape);
    drawContent(ctx, frame, x, y, effW, H);
    ctx.restore();
  }
}

/**
 * Two-layer painted shadow (soft ambient + tight contact), knocked OUT under
 * the capsule (Dock-glass pass): with the near-clear fill the blurred shadow
 * ink INSIDE the silhouette would show through the glass and grey it, so the
 * shadow is clipped to the capsule's exterior.
 */
function drawShadow(
  ctx: CanvasRenderingContext2D,
  shape: Path2D,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  const c = OVERLAY_CHROME;
  ctx.save();
  // Exterior-of-shape clip: big rect + capsule with the even-odd rule
  // (mirrors the painter's PathOperation.difference over bounds.inflate(48)).
  const knockout = new Path2D();
  knockout.rect(x - 48, y - 48, w + 96, h + 96);
  knockout.addPath(shape);
  ctx.clip(knockout, 'evenodd');

  // Tight contact shadow — grounds the capsule against the desktop.
  ctx.save();
  ctx.translate(0, c.contactShadowDy);
  ctx.filter = `blur(${c.contactShadowBlur}px)`;
  ctx.fillStyle = rgba('#000000', c.contactShadowOpacity);
  ctx.fill(shape);
  ctx.restore();

  // Soft wide-blur ambient layer — the capsule hovering.
  ctx.save();
  ctx.translate(0, c.shadowDy);
  ctx.filter = `blur(${c.shadowBlur}px)`;
  ctx.fillStyle = rgba('#000000', c.shadowOpacity);
  ctx.fill(shape);
  ctx.restore();

  ctx.restore();
}

/**
 * Opaque `solid` fill — the only fill layer. Unlike the `glass` variant (near-
 * clear tint, identity in the edges), `solid` carries its identity in the
 * fill itself: the app's own frame gradient, painted at full opacity.
 */
function drawFill(
  ctx: CanvasRenderingContext2D,
  shape: Path2D,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  const fill = OVERLAY_SOLID_FILL;
  const grad = ctx.createLinearGradient(x, y, x + w, y + h);
  fill.colors.forEach((color, i) => grad.addColorStop(fill.stops[i], color));
  ctx.fillStyle = grad;
  ctx.fill(shape);
}

/** Geometry of the deflated base capsule the liquid shape was built from. */
interface ShapeGeom {
  readonly rx: number;
  readonly ry: number;
  readonly rw: number;
  readonly rh: number;
  readonly rr: number;
  readonly baseAmp: number;
  readonly audioAmp: number;
  readonly glassPhase: number;
}

/**
 * Faux-glass sheen stack — mirrors `OverlayPainter._drawGlassSheen`. All
 * neutral white/dark, no OS blur, no state tint. The liquid-glass drift phase
 * moves the light layers (specular streak ±12 px, breathing rim); phase 0 is
 * the exact static frame.
 */
function drawGlassSheen(
  ctx: CanvasRenderingContext2D,
  shape: Path2D,
  geom: ShapeGeom,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  const gl = OVERLAY_GLASS;
  const lq = OVERLAY_LIQUID;
  const sheen = gl.sheenOpacity;
  // One slow sinusoidal cycle; secondary modulations run at double frequency
  // so all of them are 0 at phase 0 (static baseline frame).
  const wave = Math.sin(TAU * geom.glassPhase);
  const breathe = Math.sin(2 * TAU * geom.glassPhase);
  const drift = wave * lq.specularDriftPx;

  // 1) Top-down highlight (bright → soft → clear). The Dart painter insets
  //    the shader rect from the end caps and parallax-shifts it with the
  //    drift — both are inert on a purely vertical two-point gradient, so the
  //    canvas mirror omits the no-op transforms (1:1 output).
  let grad = ctx.createLinearGradient(0, y, 0, y + h);
  grad.addColorStop(gl.sheenStops[0], rgba('#FFFFFF', sheen));
  grad.addColorStop(gl.sheenStops[1], rgba('#FFFFFF', sheen * 0.35));
  grad.addColorStop(gl.sheenStops[2], rgba('#FFFFFF', 0));
  ctx.fillStyle = grad;
  ctx.fill(shape);

  // 2) Hair-thin neutral inner shade above the bottom light — the "mass" of
  //    the glass slab.
  grad = ctx.createLinearGradient(0, y, 0, y + h);
  grad.addColorStop(gl.innerShadeStops[0], rgba('#000000', 0));
  grad.addColorStop(gl.innerShadeStops[1], rgba('#000000', gl.innerShadeOpacity));
  ctx.fillStyle = grad;
  ctx.fill(shape);

  // 3) Faint bottom counter-sheen — light catching the lower glass rim.
  grad = ctx.createLinearGradient(0, y, 0, y + h);
  grad.addColorStop(gl.bottomSheenStops[0], rgba('#FFFFFF', 0));
  grad.addColorStop(gl.bottomSheenStops[1], rgba('#FFFFFF', sheen * gl.bottomSheenFactor));
  ctx.fillStyle = grad;
  ctx.fill(shape);

  // 4) Soft inner Fresnel band just inside the rim — the refracting
  //    "thickness" of the slab, fading downward. Follows the wobble at 0.8×.
  const inset = gl.innerRimInset;
  const innerShape = liquidShapePath(
    geom.rx + inset,
    geom.ry + inset,
    geom.rw - 2 * inset,
    geom.rh - 2 * inset,
    Math.max(0, geom.rr - inset),
    geom.baseAmp * 0.8,
    geom.audioAmp * 0.8,
    geom.glassPhase,
  );
  grad = ctx.createLinearGradient(0, y, 0, y + h);
  grad.addColorStop(0, rgba('#FFFFFF', gl.innerRimOpacity));
  grad.addColorStop(1, rgba('#FFFFFF', 0));
  ctx.strokeStyle = grad;
  ctx.lineWidth = gl.innerRimWidth;
  ctx.stroke(innerShape);

  // 5) Specular streak along the top edge — the Dock's signature reflection.
  //    Drifts ±12 px, breathes in length AND brightness; still an anchored
  //    highlight, never a sweeping band (ADR 0002). A soft dark under-halo
  //    guarantees local contrast over light desktops.
  const half =
    ((w * gl.specularWidthFactor) / 2) * (1 + lq.specularBreatheFactor * breathe);
  const streakY = y + gl.specularInsetTop;
  const pillCx = x + w / 2;
  const streakCx = pillCx + drift;
  ctx.save();
  ctx.filter = `blur(${gl.specularHaloBlur}px)`;
  ctx.strokeStyle = rgba(OVERLAY_GLYPH.shadowColor, gl.specularHaloOpacity);
  ctx.lineWidth = gl.specularHaloStrokeWidth;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(streakCx - half, streakY + gl.specularHaloOffsetY);
  ctx.lineTo(streakCx + half, streakY + gl.specularHaloOffsetY);
  ctx.stroke();
  ctx.restore();
  // Gradient rect stays centred on the pill (mirrors the painter): the bright
  // peak holds its resting spot while the streak's extent drifts.
  grad = ctx.createLinearGradient(pillCx - half, 0, pillCx + half, 0);
  grad.addColorStop(0, rgba('#FFFFFF', 0));
  grad.addColorStop(
    0.5,
    rgba('#FFFFFF', clamp01(gl.specularOpacity * (1 + lq.specularBrightBreatheFactor * breathe))),
  );
  grad.addColorStop(1, rgba('#FFFFFF', 0));
  ctx.strokeStyle = grad;
  ctx.lineWidth = gl.specularStrokeWidth;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(streakCx - half, streakY);
  ctx.lineTo(streakCx + half, streakY);
  ctx.stroke();

  // 6) 1 px outer rim, lit from above: bright top edge fading to nearly off
  //    at the bottom. Follows the liquid silhouette; the top light breathes.
  grad = ctx.createLinearGradient(0, y, 0, y + h);
  grad.addColorStop(
    0,
    rgba('#FFFFFF', clamp01(gl.rimTopOpacity * (1 + lq.rimBreatheFactor * breathe))),
  );
  grad.addColorStop(1, rgba('#FFFFFF', gl.rimBottomOpacity));
  ctx.strokeStyle = grad;
  ctx.lineWidth = 1;
  ctx.stroke(shape);
}

// ── Content (always opaque, clipped to the capsule) ─────────────────────────

function drawContent(
  ctx: CanvasRenderingContext2D,
  frame: OverlayFrame,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  const g = OVERLAY_GEOMETRY;
  const tok = OVERLAY_TOKENS[frame.theme];
  const cy = y + h / 2;
  const base = x + g.padH;
  const isRecording = frame.state === 'recording';
  const iconReveal = frame.iconReveal ?? 1;

  drawClose(ctx, base + g.closeOffset, cy);

  // Leading glyph: pulsing accent dot (recording/transcribing) or the
  // done/error status icon.
  const leadX = base + g.dotInset;
  switch (frame.state) {
    case 'recording':
    case 'transcribing':
      drawDot(ctx, tok, leadX, cy, frame.dotPulse);
      break;
    case 'done':
      drawCheckIcon(ctx, leadX, cy, tok.success, iconReveal);
      break;
    case 'error':
      drawErrorIcon(ctx, leadX, cy, tok.error, iconReveal);
      break;
  }

  // Universal-legibility text: white glyphs over a soft dark shadow — state
  // semantics live in the dot and the done/error icons, not in text colour.
  const textLeft = leadX + g.timerGap;
  const maxTextWidth = x + w - g.padH - textLeft;
  const textWidth = drawGlyphText(
    ctx,
    isRecording ? frame.timerText : frame.statusText,
    textLeft,
    cy,
    maxTextWidth,
  );

  // Waveform + stop square: recording (live) and transcribing (faint flat).
  if (frame.state === 'recording' || frame.state === 'transcribing') {
    const waveLeft = textLeft + textWidth + g.waveStartGap;
    const waveRight = isRecording
      ? x + w - g.padH - g.stopSize - g.waveEndGap
      : x + w - g.padH;
    drawWaveform(ctx, tok, frame, waveLeft, waveRight, cy, h);

    if (isRecording) {
      drawStop(ctx, x + w - g.padH - g.stopSize / 2, cy);
    }
  }

  // Inset accent progress timeline (recording only).
  if (isRecording && frame.progress > 0) {
    drawTimeline(ctx, tok, frame.progress, x, y, w, h);
  }
}

/** White close ✕ over its soft dark glyph shadow. */
function drawClose(ctx: CanvasRenderingContext2D, cx: number, cy: number): void {
  const g = OVERLAY_GEOMETRY;
  const gl = OVERLAY_GLYPH;
  const arm = g.closeArm;
  const strokes = (dy: number): void => {
    ctx.beginPath();
    ctx.moveTo(cx - arm, cy - arm + dy);
    ctx.lineTo(cx + arm, cy + arm + dy);
    ctx.moveTo(cx + arm, cy - arm + dy);
    ctx.lineTo(cx - arm, cy + arm + dy);
    ctx.stroke();
  };
  ctx.lineWidth = g.closeStroke;
  ctx.lineCap = 'round';
  ctx.save();
  ctx.filter = `blur(${gl.shadowBlur}px)`;
  ctx.strokeStyle = rgba(gl.shadowColor, gl.shadowOpacity);
  strokes(gl.shadowDy);
  ctx.restore();
  ctx.strokeStyle = gl.fill;
  strokes(0);
}

/** Pulsing accent recording dot — alpha AND scale breathe with the pulse. */
function drawDot(
  ctx: CanvasRenderingContext2D,
  tok: OverlayThemeTokens,
  cx: number,
  cy: number,
  pulse: number,
): void {
  const c = OVERLAY_CHROME;
  const p = clamp01(pulse);
  const alpha = c.dotMinAlpha + (1 - c.dotMinAlpha) * p;
  const scale = c.dotMinScale + (1 - c.dotMinScale) * p;
  ctx.fillStyle = rgba(tok.accent, alpha);
  ctx.beginPath();
  ctx.arc(cx, cy, OVERLAY_GEOMETRY.dotRadius * scale, 0, TAU);
  ctx.fill();
}

/** White text over the soft dark glyph shadow; returns the laid-out width. */
function drawGlyphText(
  ctx: CanvasRenderingContext2D,
  text: string,
  left: number,
  cy: number,
  maxWidth: number,
): number {
  if (!text || maxWidth <= 0) return 0;
  const gl = OVERLAY_GLYPH;
  ctx.font = OVERLAY_TEXT_FONT;
  ctx.textBaseline = 'middle';
  const shown = ellipsize(ctx, text, maxWidth);
  ctx.save();
  ctx.filter = `blur(${gl.shadowBlur}px)`;
  ctx.fillStyle = rgba(gl.shadowColor, gl.shadowOpacity);
  ctx.fillText(shown, left, cy + gl.shadowDy);
  ctx.restore();
  ctx.fillStyle = gl.fill;
  ctx.fillText(shown, left, cy);
  return ctx.measureText(shown).width;
}

/**
 * Mirrored-bar waveform: fully opaque filled capsules mirrored around the
 * centre axis, with the "energy axis" in-bar gradient (bright core at the
 * centre line, shaded tips) shared per bar class. Playhead encoding: the
 * trailing bars are wider with a hotter core — never a washed-out history.
 */
function drawWaveform(
  ctx: CanvasRenderingContext2D,
  tok: OverlayThemeTokens,
  frame: OverlayFrame,
  left: number,
  right: number,
  cy: number,
  pillHeight: number,
): void {
  const waveW = right - left;
  if (waveW <= 20) return;
  const w = OVERLAY_WAVEFORM;
  const count = w.barCount;
  const barW = waveW / count;
  const maxH = pillHeight * w.heightFactor;
  const isRecording = frame.state === 'recording';
  // The class alpha modulates the whole bar (baked into the gradient stops):
  // fully opaque while recording, quieter for the decorative rest state.
  const classAlpha = isRecording ? w.activeOpacity : w.inactiveStateOpacity;
  const zoneTop = cy - maxH / 2;
  const zoneBottom = cy + maxH / 2;
  const tip = mixRgba(tok.accent, '#000000', w.tipShadeFraction, classAlpha);
  const coreGradient = (coreLight: number): CanvasGradient => {
    const grad = ctx.createLinearGradient(0, zoneTop, 0, zoneBottom);
    grad.addColorStop(0, tip);
    grad.addColorStop(0.5, mixRgba(tok.accent, '#FFFFFF', coreLight, classAlpha));
    grad.addColorStop(1, tip);
    return grad;
  };
  const mutedPaint = coreGradient(w.coreMutedLightFraction);
  const activePaint = coreGradient(w.coreActiveLightFraction);

  for (let i = 0; i < count; i++) {
    const raw = isRecording ? clamp01(frame.bars[i] ?? 0) : w.restLevel;
    // Perceptual display gamma lifts quiet syllables (display-only mapping).
    const level = isRecording ? Math.pow(raw, w.levelGamma) : raw;
    const x = left + i * barW + barW / 2;
    const active = isRecording && i > count - w.activeCount;
    const wBar = Math.max(
      OVERLAY_GEOMETRY.lineStrokeMin,
      barW * (active ? w.activeBarFillFactor : w.barFillFactor),
    );
    // Height floor: never below the bar's own width — a resting bar becomes a
    // perfect bead (circle), a speaking bar a capsule.
    const h = Math.max(Math.max(w.minBarHeightPx, wBar), level * maxH);
    ctx.fillStyle = active ? activePaint : mutedPaint;
    roundRectPath(ctx, x - wBar / 2, cy - h / 2, wBar, h, wBar / 2);
    ctx.fill();
  }
}

/** White stop square (alpha 0.9) over its soft dark glyph shadow. */
function drawStop(ctx: CanvasRenderingContext2D, cx: number, cy: number): void {
  const g = OVERLAY_GEOMETRY;
  const gl = OVERLAY_GLYPH;
  const s = g.stopSize;
  ctx.save();
  ctx.filter = `blur(${gl.shadowBlur}px)`;
  ctx.fillStyle = rgba(gl.shadowColor, gl.shadowOpacity);
  roundRectPath(ctx, cx - s / 2, cy - s / 2 + gl.shadowDy, s, s, OVERLAY_CHROME.stopRadius);
  ctx.fill();
  ctx.restore();
  ctx.fillStyle = rgba(gl.fill, OVERLAY_CHROME.stopOpacity);
  roundRectPath(ctx, cx - s / 2, cy - s / 2, s, s, OVERLAY_CHROME.stopRadius);
  ctx.fill();
}

/** Inset accent progress timeline with the small bright lead dot. */
function drawTimeline(
  ctx: CanvasRenderingContext2D,
  tok: OverlayThemeTokens,
  progress: number,
  x: number,
  y: number,
  w: number,
  h: number,
): void {
  const c = OVERLAY_CHROME;
  const radius = OVERLAY_GEOMETRY.capsuleRadius;
  const lineY = y + h - c.timelineInsetBottom;
  const lineL = x + radius;
  const lineR = x + w - radius;
  if (lineR <= lineL) return;
  const end = lineL + (lineR - lineL) * clamp01(progress);
  const grad = ctx.createLinearGradient(lineL, 0, lineR, 0);
  grad.addColorStop(0, rgba(tok.accent, 1));
  grad.addColorStop(1, rgba(tok.accent, c.timelineEndOpacity));
  ctx.strokeStyle = grad;
  ctx.lineWidth = c.timelineStroke;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(lineL, lineY);
  ctx.lineTo(end, lineY);
  ctx.stroke();
  // Small bright lead dot pinpointing the exact current position.
  ctx.fillStyle = rgba(tok.accent, 1);
  ctx.beginPath();
  ctx.arc(end, lineY, c.timelineLeadDotRadius, 0, TAU);
  ctx.fill();
}

/**
 * Done checkmark, revealed stroke-first as `reveal` runs 0→1 — mirrors
 * `OverlayPainter._drawCheckIcon` so the check draws on as the done state
 * fades in instead of appearing instantly fully formed.
 */
function drawCheckIcon(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  tint: string,
  reveal: number,
): void {
  const size = OVERLAY_GEOMETRY.statusIconSize;
  const r = size / 2;
  const pts: ReadonlyArray<readonly [number, number]> = [
    [cx - r * 0.55, cy],
    [cx - r * 0.1, cy + r * 0.45],
    [cx + r * 0.6, cy - r * 0.5],
  ];
  ctx.strokeStyle = tint;
  ctx.lineWidth = Math.max(2, size * 0.14);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  if (reveal >= 1) {
    ctx.lineTo(pts[1][0], pts[1][1]);
    ctx.lineTo(pts[2][0], pts[2][1]);
    ctx.stroke();
    return;
  }
  const dist = (a: readonly [number, number], b: readonly [number, number]): number =>
    Math.hypot(b[0] - a[0], b[1] - a[1]);
  const seg1 = dist(pts[0], pts[1]);
  const seg2 = dist(pts[1], pts[2]);
  let remaining = (seg1 + seg2) * clamp01(reveal);
  if (remaining <= 0) return;
  if (remaining >= seg1) {
    ctx.lineTo(pts[1][0], pts[1][1]);
    remaining -= seg1;
    if (remaining > 0) {
      const t = Math.min(1, remaining / seg2);
      ctx.lineTo(
        pts[1][0] + (pts[2][0] - pts[1][0]) * t,
        pts[1][1] + (pts[2][1] - pts[1][1]) * t,
      );
    }
  } else {
    const t = remaining / seg1;
    ctx.lineTo(
      pts[0][0] + (pts[1][0] - pts[0][0]) * t,
      pts[0][1] + (pts[1][1] - pts[0][1]) * t,
    );
  }
  ctx.stroke();
}

/**
 * Error icon as a calm fade-and-settle: scale 0.85 → 1.0 and alpha 0 → 1 as
 * `reveal` runs 0→1 — mirrors `OverlayPainter._drawErrorIcon` (the same
 * no-overshoot register the capsule's own appear spring uses).
 */
function drawErrorIcon(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  tint: string,
  reveal: number,
): void {
  const size = OVERLAY_GEOMETRY.statusIconSize;
  const r = size / 2;
  const stroke = Math.max(1.5, size * 0.12);
  const clamped = clamp01(reveal);
  const scaleStart = 0.85; // errorIconRevealScaleStart
  const scale = scaleStart + (1 - scaleStart) * clamped;
  const color = rgba(tint, clamped);

  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(scale, scale);
  ctx.translate(-cx, -cy);

  ctx.strokeStyle = color;
  ctx.lineWidth = stroke;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, TAU);
  ctx.stroke();

  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(cx, cy - r * 0.45);
  ctx.lineTo(cx, cy + r * 0.12);
  ctx.stroke();

  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(cx, cy + r * 0.5, Math.max(0.8, size * 0.06), 0, TAU);
  ctx.fill();
  ctx.restore();
}
