// "Spatial Journey" — the site's one signature WebGL/GSAP moment.
//
// A camera dollies through a line of floating "app windows" in Z-depth as the
// visitor scrolls, each panel's caption typing itself in as the camera
// arrives. It embodies WhisPaste's actual mechanic (same cursor, same text,
// any app) as literal spatial travel rather than a slideshow, and closes on
// the one claim neither competitor can make: macOS + Windows + Linux parity.
//
// Loaded only via dynamic import from SpatialJourney.astro, only when
// `prefers-reduced-motion` allows it and WebGL is available — this module
// must never be part of the initial page bundle.

import * as THREE from 'three';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

export interface SpatialPanelSpec {
  id: string;
  label: string;
  caption: string;
  /** The closing "platform parity" panel gets a distinct, wider treatment. */
  variant?: 'app' | 'platform';
}

export interface SpatialJourneyOptions {
  triggerEl: HTMLElement;
  canvas: HTMLCanvasElement;
  labelEl: HTMLElement;
  captionEl: HTMLElement;
  dotsEl: HTMLElement;
  panels: SpatialPanelSpec[];
}

// Tightened from 5.2: at the old spacing, the opacity falloff below left a
// dead trough at the midpoint between two panels (~29% opacity on both
// neighbours) that read as "too much gap between windows" — a visitor
// scrolling through it saw neither panel clearly for a stretch of the
// journey. Closer spacing raises that midpoint opacity substantially (see
// PLATEAU_DIST/FALLOFF_DIST below) without shortening how long each panel
// stays framed, since the pinned scroll distance (CSS `min-height` on
// `.spj-stage-outer`) is unchanged — the same scroll length now maps to a
// shorter total Z range, i.e. more dwell time per unit of panel spacing.
const PANEL_SPACING = 4.2;
const PANEL_WIDTH = 3.4;
const PANEL_HEIGHT = 2.05;
const TEX_W = 1024;
const TEX_H = 616;

const STAGE_BG = '#171d3f';
const STAGE_BG_2 = '#1f1a45';
const CYAN = '#6fddf0';
const INK_DIM = 'rgba(226, 232, 245, 0.55)';
const INK = 'rgba(238, 242, 250, 0.92)';

function supportsWebGL(): boolean {
  try {
    const c = document.createElement('canvas');
    return !!(
      c.getContext('webgl2') ||
      c.getContext('webgl') ||
      c.getContext('experimental-webgl')
    );
  } catch {
    return false;
  }
}

/**
 * Greedy word-wrap for the caption texture. Requires `ctx.font` to already be
 * set to the caption's font — measurements use the current context state.
 */
function wrapCaption(
  ctx: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
): string[] {
  const words = text.split(' ');
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (line && ctx.measureText(candidate).width > maxWidth) {
      lines.push(line);
      line = word;
    } else {
      line = candidate;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function roundRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** Draws one app-window panel, with `typedChars` of the caption revealed. */
function paintPanel(
  ctx: CanvasRenderingContext2D,
  spec: SpatialPanelSpec,
  typedChars: number,
  showCaret: boolean,
) {
  ctx.clearRect(0, 0, TEX_W, TEX_H);

  const grad = ctx.createLinearGradient(0, 0, TEX_W, TEX_H);
  grad.addColorStop(0, spec.variant === 'platform' ? STAGE_BG_2 : STAGE_BG);
  grad.addColorStop(1, spec.variant === 'platform' ? STAGE_BG : STAGE_BG_2);
  ctx.fillStyle = grad;
  roundRect(ctx, 0, 0, TEX_W, TEX_H, 28);
  ctx.fill();

  ctx.strokeStyle =
    spec.variant === 'platform'
      ? 'rgba(111, 221, 240, 0.55)'
      : 'rgba(111, 221, 240, 0.22)';
  ctx.lineWidth = 2;
  roundRect(ctx, 1, 1, TEX_W - 2, TEX_H - 2, 28);
  ctx.stroke();

  // Window chrome bar.
  ctx.fillStyle = 'rgba(255,255,255,0.05)';
  roundRect(ctx, 0, 0, TEX_W, 56, 28);
  ctx.fill();
  ctx.fillRect(0, 28, TEX_W, 28);

  const dotColors = ['#f27878', '#f2c46d', '#7fd99a'];
  dotColors.forEach((c, i) => {
    ctx.fillStyle = c;
    ctx.globalAlpha = 0.7;
    ctx.beginPath();
    ctx.arc(34 + i * 26, 28, 6, 0, Math.PI * 2);
    ctx.fill();
  });
  ctx.globalAlpha = 1;

  ctx.font = '600 22px ui-monospace, SFMono-Regular, Menlo, monospace';
  ctx.fillStyle = INK_DIM;
  ctx.textBaseline = 'middle';
  ctx.fillText(spec.label, 130, 29);

  // Placeholder body lines (mute — establishes "this is a real app", not content).
  ctx.fillStyle = 'rgba(255,255,255,0.10)';
  const lineY = [130, 170, 210];
  const lineW = [560, 460, 500];
  lineY.forEach((y, i) => {
    roundRect(ctx, 64, y, lineW[i], 14, 7);
    ctx.fill();
  });

  // The caption — typed in, cyan, cursor-anchored, word-wrapped. The German
  // strings routinely run 70-80 chars and overran the single-line layout
  // this used to draw, clipping off the panel's right/bottom edge before a
  // visitor could read the end of the sentence. Wrapping is computed once
  // against the FULL caption (not the typed prefix) so line breaks stay
  // fixed as characters reveal, rather than reflowing mid-type.
  ctx.font =
    spec.variant === 'platform'
      ? '700 46px "Bricolage Grotesque", ui-sans-serif, system-ui, sans-serif'
      : '600 30px "Hanken Grotesk", ui-sans-serif, system-ui, sans-serif';
  ctx.fillStyle = spec.variant === 'platform' ? CYAN : INK;
  const isPlatform = spec.variant === 'platform';
  const capX = isPlatform ? TEX_W / 2 : 64;
  const lineHeight = isPlatform ? 54 : 38;
  const maxWidth = isPlatform ? TEX_W - 160 : TEX_W - capX - 48;
  const lines = wrapCaption(ctx, spec.caption, maxWidth);
  const firstLineY = isPlatform
    ? TEX_H / 2 + 10 - ((lines.length - 1) * lineHeight) / 2
    : 300;

  ctx.textAlign = isPlatform ? 'center' : 'left';
  let remaining = typedChars;
  let caretX = capX;
  let caretY = firstLineY;
  lines.forEach((line, i) => {
    const y = firstLineY + i * lineHeight;
    const revealed = line.slice(0, Math.max(0, remaining));
    if (revealed) ctx.fillText(revealed, capX, y);
    if (remaining > 0) {
      const w = ctx.measureText(revealed).width;
      caretX = isPlatform ? capX + w / 2 + 6 : capX + w + 4;
      caretY = y;
    }
    remaining -= line.length + 1; // +1: the space consumed between wrapped lines
  });
  ctx.textAlign = 'left';

  if (showCaret && typedChars < spec.caption.length) {
    ctx.fillStyle = CYAN;
    ctx.fillRect(caretX, caretY - 20, 3, 40);
  }
}

export function initSpatialJourney(opts: SpatialJourneyOptions): () => void {
  if (!supportsWebGL()) {
    return () => {};
  }

  const { triggerEl, canvas, labelEl, captionEl, dotsEl, panels } = opts;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(50, 1, 0.1, 100);

  const renderer = new THREE.WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    powerPreference: 'low-power',
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

  const meshes = panels.map((spec, i) => {
    const tex = new THREE.CanvasTexture(document.createElement('canvas'));
    const texCanvas = tex.image as HTMLCanvasElement;
    texCanvas.width = TEX_W;
    texCanvas.height = TEX_H;
    const ctx = texCanvas.getContext('2d')!;
    paintPanel(ctx, spec, 0, false);
    tex.needsUpdate = true;
    tex.colorSpace = THREE.SRGBColorSpace;

    const w = spec.variant === 'platform' ? PANEL_WIDTH * 1.15 : PANEL_WIDTH;
    const h = spec.variant === 'platform' ? PANEL_HEIGHT * 1.15 : PANEL_HEIGHT;
    const geo = new THREE.PlaneGeometry(w, h);
    const mat = new THREE.MeshBasicMaterial({
      map: tex,
      transparent: true,
    });
    const mesh = new THREE.Mesh(geo, mat);

    const dir = i % 2 === 0 ? -1 : 1;
    mesh.position.set(dir * 0.55, Math.sin(i * 1.7) * 0.18, -(i + 1) * PANEL_SPACING);
    mesh.rotation.y = dir * -0.12;
    scene.add(mesh);

    return { mesh, ctx, canvas: texCanvas, tex, spec };
  });

  const ambient = new THREE.AmbientLight(0xffffff, 1);
  scene.add(ambient);

  function resize() {
    const rect = triggerEl.getBoundingClientRect();
    const w = triggerEl.clientWidth || rect.width || window.innerWidth;
    const h = window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener('resize', resize);

  // The camera never actually reaches a panel's own z — at close range the
  // plane overflows the frame (its chrome/border crop out, only the centred
  // caption stays on-screen). Instead it dollies past each panel holding a
  // constant standoff (VIEW_DIST); progress `p` maps to this idealised
  // "effective" position (camEff), which lines up exactly with each panel's
  // world z at the moment that panel is framed correctly, while the real
  // `camera.position.z` stays VIEW_DIST in front of camEff throughout.
  const VIEW_DIST = 3.6;
  // Opacity is a plateau, not a pure V-shape: full strength for
  // d <= PLATEAU_DIST, then a linear falloff out to FALLOFF_DIST. The old
  // pure-V curve (opacity = 1 - d / (PANEL_SPACING*0.7)) peaked for a single
  // instant exactly at d=0 and was already declining by the time a caption
  // typed at TYPE_DURATION seconds could finish — so the fully-revealed text
  // routinely appeared while the panel was already fading out, which is what
  // made it feel unreadable. A held plateau gives a real window where the
  // panel sits at full opacity regardless of scroll speed.
  const PLATEAU_DIST = 1.4;
  const FALLOFF_DIST = PANEL_SPACING * 0.85;
  function opacityForDistance(d: number): number {
    if (d <= PLATEAU_DIST) return 1;
    return THREE.MathUtils.clamp(
      1 - (d - PLATEAU_DIST) / (FALLOFF_DIST - PLATEAU_DIST),
      0,
      1,
    );
  }
  const firstPanelZ = meshes[0]!.mesh.position.z;
  const lastPanelZ = meshes[meshes.length - 1]!.mesh.position.z;
  // p=0 does not start at the very first panel's spawn point — it starts
  // already CAM_LEAD units into its approach, so the panel is well into view
  // (not a blank canvas) the instant the pinned stage is reached. Without
  // this, the first ~1/6 of the scroll was spent staring at an empty scene
  // before anything became visible.
  const CAM_LEAD = 1.2;
  const camStart = firstPanelZ + CAM_LEAD;
  const camEnd = lastPanelZ;
  const camRange = camEnd - camStart;
  const dotEls = Array.from(dotsEl.children) as HTMLElement[];
  let activeIndex = -1;
  const revealed = new Set<number>();

  // Caption reveal is time-based (wall-clock), not scroll-distance-based —
  // it always finishes in TYPE_DURATION seconds once a panel becomes active,
  // regardless of how fast the visitor scrolls past it. The old
  // distance-driven version tied "fully typed" to how close the camera got,
  // which a normal scroll gesture routinely never reached in time, leaving
  // the caption perpetually half-typed and unreadable.
  const TYPE_DURATION = 0.45;

  // Each panel gets its OWN tween, tracked independently — switching the
  // active panel never kills another panel's in-flight tween. Under a fast
  // scroll flick, `setActive` can advance through several panels well inside
  // TYPE_DURATION; killing the outgoing tween used to freeze that panel's
  // texture mid-word forever (never marked `revealed`, so a later revisit
  // just restarted it from scratch — the same unreadable half-typed text as
  // before, just triggered by interruption instead of camera distance).
  // Letting every started tween run to completion in the background means
  // each panel's texture is guaranteed fully typed within TYPE_DURATION of
  // first becoming active, no matter how briefly it was "current". Only the
  // (sr-only) mirrored caption text is gated on `i === activeIndex`, so it
  // always reflects whichever panel is current right now.
  const typing: Array<{ tween: gsap.core.Tween; state: { chars: number } } | null> =
    meshes.map(() => null);

  function typePanel(i: number) {
    const m = meshes[i]!;
    if (revealed.has(i)) {
      paintPanel(m.ctx, m.spec, m.spec.caption.length, false);
      m.tex.needsUpdate = true;
      if (i === activeIndex) captionEl.textContent = m.spec.caption;
      render();
      return;
    }
    const existing = typing[i];
    if (existing) {
      if (i === activeIndex) {
        captionEl.textContent = m.spec.caption.slice(0, Math.round(existing.state.chars));
      }
      return;
    }
    if (i === activeIndex) captionEl.textContent = '';
    const state = { chars: 0 };
    const tween = gsap.to(state, {
      chars: m.spec.caption.length,
      duration: TYPE_DURATION,
      ease: 'none',
      onUpdate: () => {
        const chars = Math.round(state.chars);
        paintPanel(m.ctx, m.spec, chars, chars < m.spec.caption.length);
        m.tex.needsUpdate = true;
        if (i === activeIndex) captionEl.textContent = m.spec.caption.slice(0, chars);
        render();
      },
      onComplete: () => {
        revealed.add(i);
        typing[i] = null;
      },
    });
    typing[i] = { tween, state };
  }

  function nearestIndex(camEff: number): number {
    let best = 0;
    let bestDist = Infinity;
    meshes.forEach((m, i) => {
      const d = Math.abs(m.mesh.position.z - camEff);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    });
    return best;
  }

  function setActive(i: number) {
    if (i === activeIndex) return;
    activeIndex = i;
    const spec = panels[i]!;
    gsap.to(labelEl, {
      opacity: 0,
      duration: 0.15,
      onComplete: () => {
        labelEl.textContent = spec.label;
        gsap.to(labelEl, { opacity: 1, duration: 0.25 });
      },
    });
    dotEls.forEach((d, di) => d.classList.toggle('is-active', di === i));
    typePanel(i);
  }

  function render() {
    renderer.render(scene, camera);
  }

  function onProgress(p: number) {
    const camEff = camStart + p * camRange;
    camera.position.z = camEff + VIEW_DIST;

    // Depth-based opacity on every panel — fades each one in as the camera
    // approaches and out again as it moves on, so neighbours never sit at
    // full strength at once (the actual cause of the overlap between
    // adjacent panels at close range).
    meshes.forEach((mm, i) => {
      const d = Math.abs(mm.mesh.position.z - camEff);
      const op = opacityForDistance(d);
      (mm.mesh.material as THREE.MeshBasicMaterial).opacity = op;
      // Start typing the moment a panel becomes visible at all, not only
      // once it becomes THE nearest panel (setActive below) — nearest-
      // neighbour handoff only fires at the midpoint between two panels,
      // which is already inside the old falloff radius but well short of
      // FALLOFF_DIST. Triggering here instead gives typing up to
      // FALLOFF_DIST of lead distance before the panel's opacity peak
      // (vs. half of PANEL_SPACING before), so the caption is reliably
      // finished well before, not after, the panel is fully in view.
      // typePanel() is idempotent — safe to call every frame a panel is
      // visible.
      if (op > 0) typePanel(i);
    });

    const idx = nearestIndex(camEff);
    if (idx !== activeIndex) setActive(idx);

    render();
  }

  const trigger = ScrollTrigger.create({
    trigger: triggerEl,
    start: 'top top',
    end: 'bottom bottom',
    // Lowered from 0.4: that much scrub smoothing let the rendered camera
    // lag up to 0.4s behind the visitor's actual scroll position, so each
    // panel's "arrival" (its opacity/typing peak) landed visibly after the
    // scroll gesture that should have produced it — the concrete cause of
    // "Animationsendpunkte...zu spät". 0.15s keeps just enough smoothing to
    // avoid a hard snap on a fast scroll flick.
    scrub: 0.15,
    onUpdate: (self) => onProgress(self.progress),
  });

  onProgress(0);

  return () => {
    window.removeEventListener('resize', resize);
    trigger.kill();
    typing.forEach((t) => t?.tween.kill());
    meshes.forEach((m) => {
      m.mesh.geometry.dispose();
      (m.mesh.material as THREE.Material).dispose();
      m.tex.dispose();
    });
    renderer.dispose();
  };
}
