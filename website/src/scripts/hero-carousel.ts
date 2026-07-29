// Hero carousel — auto-advancing slides with a canvas overlay mockup + typing.
//
// Scene 2 renders the WhisPaste recording overlay on a <canvas> via the shared
// `overlay-mockup` renderer, which mirrors the in-app `OverlayPainter` 1:1 (same
// SSOT tokens + math, incl. the liquid-glass drift/wobble and the full
// recording arc — see `overlay-demo.ts`). Canvas — not CSS chrome — guarantees
// Safari/WebKit and Chrome/Chromium draw the pill identically (browser
// parity, issue 10 / ADR 0002).

import { OverlayDemo, type OverlayDemoLang } from "./overlay-demo";
import type { OverlayTheme } from "./overlay-mockup";

const track = document.getElementById("carousel-track");
const dotButtons = document.querySelectorAll<HTMLButtonElement>(".carousel-dot-hit");
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

function currentTheme(): OverlayTheme {
  return document.documentElement.classList.contains("light")
    ? "light"
    : "dark";
}

function currentLang(): OverlayDemoLang {
  const lang = (window as unknown as { currentLang?: string }).currentLang;
  return lang === "de" ? "de" : "en";
}

const overlayDemo = canvas
  ? new OverlayDemo({
      canvas,
      reducedMotion,
      getTheme: currentTheme,
      getLang: currentLang,
    })
  : null;

function startOverlay() {
  overlayDemo?.start();
}

function stopOverlay() {
  overlayDemo?.stop();
  overlayDemo?.drawFrozen();
}

// ── Carousel ────────────────────────────────────────────────────────────────

function goToSlide(n: number) {
  currentSlide = n;
  if (track) track.style.transform = `translateX(-${n * 100}%)`;
  dotButtons.forEach((btn, i) => {
    const dot = btn.querySelector<HTMLElement>(".carousel-dot");
    if (!dot) return;
    if (i === n) {
      dot.classList.remove("bg-white/20");
      dot.classList.add("bg-brand-cyan");
      dot.style.width = "16px";
      btn.setAttribute("aria-current", "true");
    } else {
      dot.classList.add("bg-white/20");
      dot.classList.remove("bg-brand-cyan");
      dot.style.width = "8px";
      btn.removeAttribute("aria-current");
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

dotButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    stopCarousel();
    goToSlide(parseInt(btn.dataset.slide!));
    scheduleNext();
  });
});

// Redraw the resting/reduced frame on theme toggle so the mockup follows the
// site theme even when it is not animating (the running demo reads the theme
// live every frame).
if (overlayDemo) {
  overlayDemo.resize();
  const themeObserver = new MutationObserver(() => {
    if (!overlayDemo.running) overlayDemo.drawFrozen();
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
