// Hero carousel — auto-advancing slides with waveform + typing animations

const track = document.getElementById("carousel-track");
const dots = document.querySelectorAll(".carousel-dot");
let currentSlide = 0;
const totalSlides = 3;
const SLIDE_DURATIONS = [5000, 5000, 8000];
let carouselTimer: ReturnType<typeof setTimeout>;
const reducedMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)",
).matches;

const OVERLAY_MAX_SECONDS = 120;
let overlayTimerInterval: ReturnType<typeof setInterval>;
let waveformInterval: ReturnType<typeof setInterval>;

const WAVE_BAR_COUNT = 30;
const WAVE_HEIGHT = 24;
const WAVE_MIN_HEIGHT = 4;
const WAVE_BRIGHT_THRESHOLD = 0.30;
const WAVE_TICK_MS = 120;

function startOverlayTimer() {
  clearInterval(overlayTimerInterval);
  const timerEl = document.getElementById("overlay-timer");
  if (!timerEl) return;
  let seconds = 0;
  updateOverlayProgress(seconds);
  overlayTimerInterval = setInterval(() => {
    seconds++;
    updateOverlayProgress(seconds);
  }, 1000);
}

function stopOverlayTimer() {
  clearInterval(overlayTimerInterval);
}

function updateOverlayProgress(seconds: number) {
  const timerEl = document.getElementById("overlay-timer");
  const progressFillEl = document.getElementById("overlay-progress-fill");
  if (!timerEl || !progressFillEl) return;

  const fraction = Math.min(seconds / OVERLAY_MAX_SECONDS, 1);
  let activeColor = "var(--overlay-primary)";

  if (fraction >= 0.9) {
    activeColor = "#FF5252";
  } else if (fraction >= 0.75) {
    activeColor = "#FFC107";
  }

  timerEl.textContent =
    Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
  timerEl.style.color = activeColor;
  progressFillEl.style.width = `${fraction * 100}%`;
  progressFillEl.style.backgroundColor = activeColor;
}

const waveformEl = document.getElementById("overlay-waveform");
const waveBars: HTMLElement[] = [];
let waveHistory: number[] = [];
let waveStep = 0;

function boostedLevel(raw: number) {
  const clamped = Math.min(1, Math.max(0, raw));
  return Math.min(1, Math.sqrt(clamped) * 1.5);
}

function nextWaveSample(step: number) {
  const phrase = 0.18 * Math.max(0, Math.sin(step * 0.31 + 0.9));
  const cadence = 0.34 * Math.max(0, Math.sin(step * 0.57));
  const emphasis = 0.22 * Math.max(0, Math.sin(step * 0.93 + 0.45));
  const breath = step % 18 === 0 ? 0.0 : 0.08;
  const raw = Math.min(1, phrase + cadence + emphasis + breath);
  return raw < 0.1 ? 0.0 : raw;
}

function renderWaveform() {
  if (!waveBars.length) return;

  const padded = Array<number>(WAVE_BAR_COUNT).fill(0);
  const visibleHistory = waveHistory.slice(-WAVE_BAR_COUNT);
  padded.splice(WAVE_BAR_COUNT - visibleHistory.length, visibleHistory.length, ...visibleHistory);

  waveBars.forEach((bar, index) => {
    const level = boostedLevel(padded[index]);
    const height = Math.max(WAVE_MIN_HEIGHT, Math.round(level * WAVE_HEIGHT));
    bar.style.height = `${height}px`;
    bar.dataset.bright = level > WAVE_BRIGHT_THRESHOLD ? "true" : "false";
  });
}

function resetWaveform() {
  waveHistory = [];
  waveStep = 0;
  renderWaveform();
}

function tickWaveform() {
  waveStep += 1;
  waveHistory.push(nextWaveSample(waveStep));
  if (waveHistory.length > WAVE_BAR_COUNT) {
    waveHistory.shift();
  }
  renderWaveform();
}

function startWaveform() {
  clearInterval(waveformInterval);
  resetWaveform();
  if (reducedMotion || !waveBars.length) return;
  tickWaveform();
  waveformInterval = setInterval(tickWaveform, WAVE_TICK_MS);
}

function stopWaveform(reset = false) {
  clearInterval(waveformInterval);
  if (reset) {
    resetWaveform();
  }
}

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
    startOverlayTimer();
    startWaveform();
  } else {
    stopOverlayTimer();
    updateOverlayProgress(0);
    stopWaveform(true);
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

// Waveform bars
if (waveformEl) {
  waveformEl.textContent = "";
  for (let i = 0; i < WAVE_BAR_COUNT; i++) {
    const bar = document.createElement("div");
    bar.className = "overlay-wave-bar";
    bar.style.height = `${WAVE_MIN_HEIGHT}px`;
    bar.dataset.bright = "false";
    waveformEl.appendChild(bar);
    waveBars.push(bar);
  }
  renderWaveform();
}

// Typing animation for scene 3
const typedEl = document.getElementById("typed-text");
let typingTimeout: ReturnType<typeof setTimeout>;

function getTypingSegments() {
  const lang = (window as any).currentLang || "en";
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
  let currentSpan: any = null;

  function typeChar() {
    if (segIdx >= segments.length || currentSlide !== 2) return;
    const seg = segments[segIdx];
    const cursor = typedEl!.querySelector(".typing-cursor");
    if (!cursor) return;

    if (!currentSpan || currentSpan._segIdx !== segIdx) {
      if (seg.cls) {
        currentSpan = document.createElement("span");
        currentSpan.className = seg.cls;
        currentSpan._segIdx = segIdx;
        typedEl!.insertBefore(currentSpan, cursor);
      } else {
        currentSpan = { _segIdx: segIdx, _isText: true };
      }
    }

    const ch = seg.text[charIdx];
    if (currentSpan._isText) {
      typedEl!.insertBefore(document.createTextNode(ch), cursor);
    } else {
      currentSpan.appendChild(document.createTextNode(ch));
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

