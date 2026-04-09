// Hero carousel — auto-advancing slides with waveform + typing animations

const track = document.getElementById("carousel-track");
const dots = document.querySelectorAll(".carousel-dot");
let currentSlide = 0;
const totalSlides = 3;
const SLIDE_DURATIONS = [5000, 5000, 8000];
let carouselTimer: ReturnType<typeof setTimeout>;
let reducedMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)",
).matches;

let overlayTimerInterval: ReturnType<typeof setInterval>;

function startOverlayTimer() {
  clearInterval(overlayTimerInterval);
  const timerEl = document.getElementById("overlay-timer");
  if (!timerEl) return;
  let seconds = 0;
  timerEl.textContent = "0:00";
  overlayTimerInterval = setInterval(() => {
    seconds++;
    timerEl.textContent =
      Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
  }, 1000);
}

function stopOverlayTimer() {
  clearInterval(overlayTimerInterval);
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
  if (n === 1) startOverlayTimer();
  else stopOverlayTimer();
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

// Waveform animation
const waveformEl = document.getElementById("overlay-waveform");
const waveBars: {
  el: HTMLElement;
  phase: number;
  speed: number;
  amp: number;
}[] = [];
if (waveformEl) {
  for (let i = 0; i < 25; i++) {
    const bar = document.createElement("div");
    bar.className = "overlay-wave-bar";
    bar.style.height = "2px";
    bar.style.background = "rgba(56,217,240,0.3)";
    waveformEl.appendChild(bar);
    waveBars.push({
      el: bar,
      phase: Math.random() * Math.PI * 2,
      speed: 1.5 + Math.random() * 2.5,
      amp: 0.3 + Math.random() * 0.7,
    });
  }
  let waveRaf: number;
  function animateWave(t: number) {
    if (reducedMotion) return;
    for (let i = 0; i < waveBars.length; i++) {
      const b = waveBars[i];
      const val = ((Math.sin(t * 0.003 * b.speed + b.phase) + 1) / 2) * b.amp;
      const h = Math.max(2, Math.round(val * 24));
      b.el.style.height = h + "px";
      b.el.style.background =
        h > 5 ? "rgba(56,217,240,0.85)" : "rgba(56,217,240,0.3)";
    }
    waveRaf = requestAnimationFrame(animateWave);
  }
  if (!reducedMotion) {
    waveRaf = requestAnimationFrame(animateWave);
  }
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
