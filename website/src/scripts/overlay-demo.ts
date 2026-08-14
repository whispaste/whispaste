/**
 * Shared marketing-demo driver for the overlay mockup.
 *
 * Both embeds (the hero carousel's scene 2 and the AppPasteDemo storyboard's
 * step 2) run the same calm recording arc through the shared canvas renderer
 * (`overlay-mockup.ts`), mirroring the app's `FloatingOverlayView` controller
 * stack:
 *
 *   appear spring (scale 0.88 → 1.0 + fade, easeOutCubic 300 ms)
 *     → recording (live waveform, timer, progress timeline, liquid wobble)
 *     → transcribing (150 ms content crossfade + pill-width spring)
 *     → done — or, every 4th episode, error (280 ms status reveal:
 *       check draws on stroke-first / error icon settles in)
 *     → brief fade-out, short rest, next episode.
 *
 * One episode ≈ 9.7 s — a quiet, legible narrative, not a strobe. The 8 s
 * liquid-glass drift loop and the silhouette wobble run continuously
 * underneath. Timings/curves come from `OVERLAY_ARC` / `OVERLAY_LIQUID`
 * (mirrored from the Dart SSOT); only the episode phase lengths are
 * demo-pacing choices.
 *
 * Reduced motion: `start()` draws the deterministic frozen frame (recording
 * state, spike-verified bars, glass phase 0, rigid capsule — the same frame
 * the cross-engine parity test snapshots) and never animates.
 *
 * The driver owns canvas clearing and the appear transform; the renderer
 * multiplies against `ctx.globalAlpha` (it never overwrites it), which is
 * what makes the fade and the content crossfade composable.
 */

import {
  drawOverlayPill,
  easeOutCubic,
  pillWidthForText,
  Spring,
  WaveformHistory,
  FROZEN_BARS,
  OVERLAY_ARC,
  OVERLAY_GEOMETRY,
  OVERLAY_LIQUID,
  OVERLAY_TEXT_FONT,
  OVERLAY_WAVEFORM_MOTION,
  type OverlayFrame,
  type OverlayState,
  type OverlayTheme,
} from './overlay-mockup';

/** Demo languages — mirrors the site's two locales. */
export type OverlayDemoLang = 'de' | 'en';

/**
 * Status texts per state, verbatim from the app's own localisations
 * (`app_localizations_{en,de}.dart`: overlayTranscribing / overlayDonePasted /
 * overlayError) — the demo shows exactly what the real overlay says.
 */
const LABELS: Readonly<
  Record<OverlayDemoLang, Readonly<Record<'transcribing' | 'done' | 'error', string>>>
> = {
  en: { transcribing: 'Transcribing…', done: 'Pasted', error: 'Error' },
  de: { transcribing: 'Wird transkribiert…', done: 'Eingefügt', error: 'Fehler' },
};

export interface OverlayDemoOptions {
  readonly canvas: HTMLCanvasElement;
  /** `prefers-reduced-motion` at page load — frozen frame only when true. */
  readonly reducedMotion: boolean;
  /** Resolved per frame so the running demo follows live theme toggles. */
  readonly getTheme: () => OverlayTheme;
  /** Resolved per frame so the demo follows live language toggles. */
  readonly getLang: () => OverlayDemoLang;
}

const FRAME_MS = 1000 / 30; // 30 fps redraw (OverlayMotion cadence)
const TICK_EVERY = Math.max(1, Math.round(OVERLAY_WAVEFORM_MOTION.tickMs / FRAME_MS));
const DOT_PERIOD_MS = 900; // OverlayMotion.dotPulsePeriod
const DEMO_MAX_SECONDS = 8; // mockup pace so the timeline visibly fills

/** Demo episode phases (recording arc + rest between episodes). */
type DemoPhase = 'recording' | 'transcribing' | 'end' | 'fadeout' | 'gap';

/** Phase lengths (ms) — demo pacing, deliberately calm. */
const PHASE_MS: Readonly<Record<DemoPhase, number>> = {
  recording: 4600,
  transcribing: 1600,
  end: 2600,
  fadeout: 240,
  gap: 700,
};

const PHASE_ORDER: readonly DemoPhase[] = [
  'recording',
  'transcribing',
  'end',
  'fadeout',
  'gap',
];

/** Every Nth episode ends in the error state instead of done. */
const ERROR_EVERY_NTH_EPISODE = 4;

/**
 * Speech-like envelope with periodic pauses so the release smoothing visibly
 * decays the waveform toward flat during a pause.
 */
export function syntheticLevel(tick: number): number {
  const t = tick * 0.32;
  if (Math.sin(t * 0.45) < -0.5) return 0; // pause
  const phrase = 0.5 + 0.5 * Math.sin(t);
  const accent = 0.28 * Math.max(0, Math.sin(t * 2.7 + 0.6));
  return Math.min(1, 0.2 + 0.65 * phrase * phrase + accent);
}

function formatTimer(seconds: number): string {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

/** The outgoing side of an in-flight state-transition crossfade. */
interface OutgoingContent {
  readonly state: OverlayState;
  /** Frozen timer (recording) or status text at the moment of transition. */
  readonly text: string;
  /** Frozen recording progress (keeps the outgoing timeline stable). */
  readonly progress: number;
}

/** Drives one canvas through the looping marketing recording arc. */
export class OverlayDemo {
  private readonly ctx: CanvasRenderingContext2D | null;
  private timer: ReturnType<typeof setInterval> | undefined;
  private readonly history = new WaveformHistory();
  private readonly widthSpring = new Spring(OVERLAY_GEOMETRY.width);

  private phase: DemoPhase = 'recording';
  private phaseElapsed = 0;
  private episodeElapsed = 0;
  private totalElapsed = 0;
  private ticks = 0;
  private episode = 0;

  private outgoing: OutgoingContent | null = null;
  private transitionElapsed = 0;
  private transitionDur: number = OVERLAY_ARC.stateTransitionMs;

  constructor(private readonly opts: OverlayDemoOptions) {
    this.ctx = opts.canvas.getContext('2d');
  }

  /** Whether the animation loop is currently running. */
  get running(): boolean {
    return this.timer !== undefined;
  }

  /** (Re-)applies the DPR-aware canvas sizing. */
  resize(): void {
    if (!this.ctx) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    const cssW = OVERLAY_GEOMETRY.width + OVERLAY_GEOMETRY.shadowPad * 2;
    const cssH = OVERLAY_GEOMETRY.height + OVERLAY_GEOMETRY.shadowPad * 2;
    this.opts.canvas.width = Math.round(cssW * dpr);
    this.opts.canvas.height = Math.round(cssH * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  /**
   * Deterministic resting/reduced-motion frame: the spike-verified snapshot —
   * recording state, glass phase 0, rigid capsule (liquid motion 0). This is
   * the exact frame the cross-engine parity test compares.
   */
  drawFrozen(): void {
    if (!this.ctx) return;
    this.clear();
    drawOverlayPill(this.ctx, {
      theme: this.opts.getTheme(),
      state: 'recording',
      bars: FROZEN_BARS,
      timerText: '0:07',
      statusText: '',
      progress: 0.6,
      dotPulse: 1,
      glassPhase: 0,
      liquidMotion: 0,
      liquidLevel: 0,
    });
  }

  /** Starts the looping arc (or draws the frozen frame under reduced motion). */
  start(): void {
    this.stop();
    if (!this.ctx) return;
    if (this.opts.reducedMotion) {
      this.drawFrozen();
      return;
    }
    this.resetEpisode(true);
    this.timer = setInterval(() => this.step(), FRAME_MS);
  }

  /** Halts the loop (keeps the last frame; callers may drawFrozen()). */
  stop(): void {
    if (this.timer !== undefined) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  private clear(): void {
    if (!this.ctx) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.ctx.clearRect(
      0,
      0,
      OVERLAY_GEOMETRY.width + OVERLAY_GEOMETRY.shadowPad * 2,
      OVERLAY_GEOMETRY.height + OVERLAY_GEOMETRY.shadowPad * 2,
    );
  }

  private resetEpisode(fresh: boolean): void {
    if (fresh) {
      this.episode = 0;
      this.totalElapsed = 0;
      this.ticks = 0;
    }
    this.phase = 'recording';
    this.phaseElapsed = 0;
    this.episodeElapsed = 0;
    this.outgoing = null;
    this.history.reset();
    // Re-show: snap the pill width to the recording target (mirrors the
    // app's _snapPillToCurrentState on every re-appear).
    this.widthSpring.snapTo(OVERLAY_GEOMETRY.width);
  }

  private get endState(): OverlayState {
    return this.episode % ERROR_EVERY_NTH_EPISODE === ERROR_EVERY_NTH_EPISODE - 1
      ? 'error'
      : 'done';
  }

  private currentState(): OverlayState {
    switch (this.phase) {
      case 'recording':
        return 'recording';
      case 'transcribing':
        return 'transcribing';
      default:
        return this.endState;
    }
  }

  private labels(): Readonly<Record<'transcribing' | 'done' | 'error', string>> {
    return this.opts.getLang() === 'de' ? LABELS.de : LABELS.en;
  }

  private textFor(state: OverlayState): string {
    const labels = this.labels();
    switch (state) {
      case 'recording':
        return '';
      case 'transcribing':
        return labels.transcribing;
      case 'done':
        return labels.done;
      case 'error':
        return labels.error;
    }
  }

  private measureText(text: string): number {
    if (!this.ctx) return 0;
    this.ctx.font = OVERLAY_TEXT_FONT;
    return this.ctx.measureText(text).width;
  }

  /** Begins the content crossfade + width spring into `to`. */
  private startTransition(from: OverlayState, to: OverlayState): void {
    const fromText =
      from === 'recording' ? this.recordingTimerText() : this.textFor(from);
    this.outgoing = {
      state: from,
      text: fromText,
      progress: from === 'recording' ? this.recordingProgress() : 0,
    };
    this.transitionElapsed = 0;
    // Into done/error the crossfade runs slightly longer so the stroke-first
    // status-icon draw-on has room to land (statusRevealDuration). Recording
    // → transcribing also runs longer (releaseOutDuration): the outgoing
    // layer is the only one painting live waveform decay, and the generic
    // 150 ms crossfade cut that decay off mid-motion.
    if (to === 'done' || to === 'error') {
      this.transitionDur = OVERLAY_ARC.statusRevealMs;
    } else if (from === 'recording' && to === 'transcribing') {
      this.transitionDur = OVERLAY_ARC.releaseOutMs;
    } else {
      this.transitionDur = OVERLAY_ARC.stateTransitionMs;
    }
    this.widthSpring.setTarget(
      pillWidthForText(to, this.textFor(to), (t) => this.measureText(t)),
    );
  }

  private recordingTimerText(): string {
    return formatTimer(Math.floor(Math.min(this.phaseElapsed, PHASE_MS.recording) / 1000));
  }

  private recordingProgress(): number {
    return Math.min(this.phaseElapsed / (DEMO_MAX_SECONDS * 1000), 1);
  }

  private advancePhase(): void {
    const idx = PHASE_ORDER.indexOf(this.phase);
    const next = PHASE_ORDER[(idx + 1) % PHASE_ORDER.length];
    if (next === 'recording') {
      // New episode.
      this.episode += 1;
      this.resetEpisode(false);
      return;
    }
    if (next === 'transcribing') {
      this.startTransition('recording', 'transcribing');
    } else if (next === 'end') {
      this.startTransition('transcribing', this.endState);
    }
    this.phase = next;
    this.phaseElapsed = 0;
  }

  private step(): void {
    this.totalElapsed += FRAME_MS;
    this.episodeElapsed += FRAME_MS;
    this.phaseElapsed += FRAME_MS;
    this.ticks += 1;

    if (this.ticks % TICK_EVERY === 0) {
      // Outside recording the input falls silent, so the live bars decay via
      // the release smoothing — exactly what the app's pipeline does during
      // the release-out window.
      this.history.tick(this.phase === 'recording' ? syntheticLevel(this.ticks) : 0);
    }
    if (this.outgoing) this.transitionElapsed += FRAME_MS;
    this.widthSpring.step(FRAME_MS);

    if (this.phaseElapsed >= PHASE_MS[this.phase]) {
      this.advancePhase();
    }
    this.render();
  }

  private render(): void {
    const ctx = this.ctx;
    if (!ctx) return;
    this.clear();
    if (this.phase === 'gap') return; // hidden between episodes

    const g = OVERLAY_GEOMETRY;
    const cssW = g.width + g.shadowPad * 2;
    const cssH = g.height + g.shadowPad * 2;

    // Appear spring: scale 0.88 → 1.0 + fade-in over the first 300 ms of an
    // episode (easeOutCubic, no overshoot). The fade-out phase is a quick
    // marketing-friendly exit (the real overlay is hidden by its native
    // window shell in one cut).
    let alpha: number;
    let scale: number;
    if (this.phase === 'fadeout') {
      alpha = Math.max(0, 1 - this.phaseElapsed / PHASE_MS.fadeout);
      scale = 1;
    } else {
      const t = easeOutCubic(Math.min(this.episodeElapsed / OVERLAY_ARC.appearMs, 1));
      alpha = t;
      scale = OVERLAY_ARC.appearScale + (1 - OVERLAY_ARC.appearScale) * t;
    }

    ctx.save();
    ctx.translate(cssW / 2, cssH / 2);
    ctx.scale(scale, scale);
    ctx.translate(-cssW / 2, -cssH / 2);

    const state = this.currentState();
    const bars = this.history.values();
    const liquidLevel = state === 'recording' ? this.liquidLevel(bars) : 0;
    const base: OverlayFrame = {
      theme: this.opts.getTheme(),
      state,
      bars,
      timerText: this.phase === 'recording' ? this.recordingTimerText() : '',
      statusText: this.textFor(state),
      progress: this.phase === 'recording' ? this.recordingProgress() : 0,
      dotPulse: 0.5 + 0.5 * Math.sin((this.totalElapsed / DOT_PERIOD_MS) * Math.PI * 2),
      glassPhase: (this.totalElapsed % OVERLAY_LIQUID.driftPeriodMs) / OVERLAY_LIQUID.driftPeriodMs,
      liquidMotion: 1,
      liquidLevel,
      pillWidth: this.widthSpring.value,
    };

    const fade =
      this.outgoing && this.transitionElapsed < this.transitionDur
        ? easeOutCubic(this.transitionElapsed / this.transitionDur)
        : 1;

    if (this.outgoing && fade < 1) {
      // State-transition crossfade: the fill is drawn once (background-only)
      // so the semi-transparent glass gradient is not double-composited; only
      // the content layers crossfade at opposite opacities. All layers share
      // the same animated pill width so they morph in perfect sync.
      const out = this.outgoing;
      ctx.globalAlpha = alpha;
      drawOverlayPill(ctx, base, { fill: true, content: false });
      ctx.globalAlpha = alpha * (1 - fade);
      drawOverlayPill(
        ctx,
        {
          ...base,
          state: out.state,
          timerText: out.state === 'recording' ? out.text : '',
          statusText: out.state === 'recording' ? '' : out.text,
          progress: out.progress,
          iconReveal: 1,
        },
        { fill: false, content: true },
      );
      // Incoming content fades in; the done-check draw-on / error-icon
      // settle-in runs off the same fraction, finishing exactly as the
      // crossfade reaches full opacity.
      ctx.globalAlpha = alpha * fade;
      drawOverlayPill(ctx, { ...base, iconReveal: fade }, { fill: false, content: true });
    } else {
      this.outgoing = null;
      ctx.globalAlpha = alpha;
      drawOverlayPill(ctx, base);
    }

    ctx.restore();
  }

  /** Smoothed live audio level: mean of the newest 4 bars (mirrors the app). */
  private liquidLevel(bars: readonly number[]): number {
    if (bars.length === 0) return 0;
    const n = Math.min(4, bars.length);
    let sum = 0;
    for (let i = bars.length - n; i < bars.length; i++) sum += bars[i];
    return Math.min(1, Math.max(0, sum / n));
  }
}
