// Hero carousel — auto-advancing slides with a canvas overlay mockup + typing.
//
// Scene 2 renders the WhisPaste recording overlay on a <canvas> via the shared
// `overlay-mockup` renderer, which mirrors the in-app `OverlayPainter` 1:1 (same
// SSOT tokens + math). Canvas — not CSS chrome — guarantees Safari/WebKit and
// Chrome/Chromium draw the pill identically (browser parity, issue 10).

import {
  OVERLAY_GEOMETRY,
  OVERLAY_WAVEFORM_MOTION,
  FROZEN_BARS,
  WaveformHistory,
  drawOverlayPill,
  type OverlayTheme,
} from "./overlay-mockup";

const track = document.getElementById("carousel-track");
const dots = document.querySelectorAll(".carousel-dot");
let currentSlide = 0;
const totalSlides = 3;
const SLIDE_DURATIONS = [5000, 5000, 8000];
let carouselTimer: ReturnType<typeof setTimeout>;
const reducedMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)",
).matches;

// ── Overlay mockup (canvas) ────────────────────────────────────────────────

const canvas = document.getElementById(
  "overlay-canvas",
) as HTMLCanvasElement | null;
const ctx = canvas?.getContext("2d") ?? null;
const history = new WaveformHistory();
let overlayInterval: ReturnType<typeof setInterval>;

const OVERLAY_FRAME_MS = 1000 / 30; // 30 fps redraw (OverlayMotion.frameRateFps)
const OVERLAY_TICK_EVERY = Math.max(
  1,
  Math.round(OVERLAY_WAVEFORM_MOTION.tickMs / OVERLAY_FRAME_MS),
);
const OVERLAY_DOT_PERIOD_MS = 900; // OverlayMotion.dotPulsePeriod
const OVERLAY_DEMO_MAX_SECONDS = 12; // mockup pace so the timeline visibly fills

function currentTheme(): OverlayTheme {
  return document.documentElement.classList.contains("light")
    ? "light"
    : "dark";
}

function sizeCanvas() {
  if (!canvas || !ctx) return;
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  const cssW = OVERLAY_GEOMETRY.width + OVERLAY_GEOMETRY.shadowPad * 2;
  const cssH = OVERLAY_GEOMETRY.height + OVERLAY_GEOMETRY.shadowPad * 2;
  canvas.width = Math.round(cssW * dpr);
  canvas.height = Math.round(cssH * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function drawOverlay(
  bars: readonly number[],
  timerText: string,
  progress: number,
  dotPulse: number,
) {
  if (!ctx) return;
  drawOverlayPill(ctx, {
    theme: currentTheme(),
    bars,
    timerText,
    progress,
    dotPulse,
  });
}

function formatTimer(seconds: number) {
  return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
}

// Deterministic resting/reduced-motion frame: the spike-verified snapshot.
function drawFrozenOverlay() {
  drawOverlay(FROZEN_BARS, "0:07", 0.6, 1);
}

// Speech-like envelope with periodic pauses, so the release smoothing visibly
// decays the waveform toward flat during a pause (silence → nearly flat).
function syntheticLevel(tick: number) {
  const t = tick * 0.32;
  if (Math.sin(t * 0.45) < -0.5) return 0; // pause
  const phrase = 0.5 + 0.5 * Math.sin(t);
  const accent = 0.28 * Math.max(0, Math.sin(t * 2.7 + 0.6));
  return Math.min(1, 0.2 + 0.65 * phrase * phrase + accent);
}

function startOverlay() {
  clearInterval(overlayInterval);
  if (!ctx) return;
  if (reducedMotion) {
    drawFrozenOverlay();
    return;
  }
  history.reset();
  let elapsedMs = 0;
  let ticks = 0;
  overlayInterval = setInterval(() => {
    elapsedMs += OVERLAY_FRAME_MS;
    ticks += 1;
    if (ticks % OVERLAY_TICK_EVERY === 0) {
      history.tick(syntheticLevel(ticks));
    }
    const seconds = Math.floor(elapsedMs / 1000);
    const progress =
      Math.min(elapsedMs / (OVERLAY_DEMO_MAX_SECONDS * 1000), 1) * 0.78;
    const dotPulse =
      0.5 + 0.5 * Math.sin((elapsedMs / OVERLAY_DOT_PERIOD_MS) * Math.PI * 2);
    drawOverlay(history.values(), formatTimer(seconds), progress, dotPulse);
  }, OVERLAY_FRAME_MS);
}

function stopOverlay() {
  clearInterval(overlayInterval);
  drawFrozenOverlay();
}

// ── Carousel ────────────────────────────────────────────────────────────────

function goToSlide(n: number) {
  currentSlide = n;
  if (track) track.style.transform = `translateX(-${n * 100}%)`;
  dots.forEach((dot, i) => {
    if (i === n) {
      dot.classList.remove("bg-white/20");
      dot.classList.add("bg-brand-cyan");
      (dot as HTMLElement).style.width = "16px";
      dot.setAttribute("aria-selected", "true");
    } else {
      dot.classList.add("bg-white/20");
      dot.classList.remove("bg-brand-cyan");
      (dot as HTMLElement).style.width = "8px";
      dot.setAttribute("aria-selected", "false");
    }
  });
  if (n === 1) {
    startOverlay();
  } else {
    stopOverlay();
  }
  if (n === 2) startTyping();
}

function scheduleNext() {
  clearTimeout(carouselTimer);
  if (reducedMotion) return;
  carouselTimer = setTimeout(nextSlide, SLIDE_DURATIONS[currentSlide]);
}

function nextSlide() {
  goToSlide((currentSlide + 1) % totalSlides);
  scheduleNext();
}

function startCarousel() {
  scheduleNext();
}

function stopCarousel() {
  clearTimeout(carouselTimer);
}

dots.forEach((dot) => {
  dot.addEventListener("click", () => {
    stopCarousel();
    goToSlide(parseInt((dot as HTMLElement).dataset.slide!));
    scheduleNext();
  });
});

// Redraw the resting/reduced frame on theme toggle so the mockup follows the
// site theme even when it is not animating.
if (canvas) {
  sizeCanvas();
  const themeObserver = new MutationObserver(() => {
    if (currentSlide !== 1 || reducedMotion) drawFrozenOverlay();
  });
  themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class"],
  });
}

// Typing animation for scene 3
const typedEl = document.getElementById("typed-text");
let typingTimeout: ReturnType<typeof setTimeout>;

function getTypingSegments() {
  const lang = (window as unknown as { currentLang?: string }).currentLang || "en";
  if (lang === "de") {
    return [
      { text: "Hey, diesen Text habe ich\ngerade eben eingesprochen\nund " },
      { text: "WhisPaste", cls: "text-brand-cyan font-semibold" },
      { text: " hat ihn direkt\nhier eingefügt. " },
      { text: "❤️", cls: "carousel-heart" },
      { text: " 😊" },
    ];
  }
  return [
    { text: "Hey, I just spoke this text\nand " },
    { text: "WhisPaste", cls: "text-brand-cyan font-semibold" },
    { text: " pasted it right\nhere automatically. " },
    { text: "❤️", cls: "carousel-heart" },
    { text: " 😊" },
  ];
}

function startTyping() {
  if (!typedEl) return;
  clearTimeout(typingTimeout);
  const segments = getTypingSegments();
  typedEl.innerHTML = '<span class="typing-cursor"></span>';
  let segIdx = 0,
    charIdx = 0;
  let currentSpan: (HTMLElement & { _segIdx?: number; _isText?: boolean }) | { _segIdx: number; _isText: boolean } | null =
    null;

  function typeChar() {
    if (segIdx >= segments.length || currentSlide !== 2) return;
    const seg = segments[segIdx];
    const cursor = typedEl!.querySelector(".typing-cursor");
    if (!cursor) return;

    if (!currentSpan || currentSpan._segIdx !== segIdx) {
      if (seg.cls) {
        const span = document.createElement("span") as HTMLElement & {
          _segIdx?: number;
        };
        span.className = seg.cls;
        span._segIdx = segIdx;
        typedEl!.insertBefore(span, cursor);
        currentSpan = span;
      } else {
        currentSpan = { _segIdx: segIdx, _isText: true };
      }
    }

    const ch = seg.text[charIdx];
    if ("_isText" in currentSpan && currentSpan._isText) {
      typedEl!.insertBefore(document.createTextNode(ch), cursor);
    } else {
      (currentSpan as HTMLElement).appendChild(document.createTextNode(ch));
    }

    charIdx++;
    if (charIdx >= seg.text.length) {
      segIdx++;
      charIdx = 0;
      currentSpan = null;
    }

    if (segIdx < segments.length) {
      typingTimeout = setTimeout(typeChar, 40 + Math.random() * 40);
    }
  }
  typingTimeout = setTimeout(typeChar, 400);
}

startCarousel();
goToSlide(0);
