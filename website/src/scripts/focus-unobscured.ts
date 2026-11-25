/**
 * Keeps the keyboard focus visible above fixed bottom layers (#1909).
 *
 * The sticky mobile download bar (#mobile-cta) and the contact widget with
 * its teaser card (.cw) float over the bottom of the page. Browsers scroll a
 * newly focused element only into the viewport, not above those layers, so a
 * focused link or FAQ question near the bottom could end up fully covered
 * (WCAG 2.4.11). This keeps `scroll-padding-bottom` on <html> equal to the
 * height those layers currently cover; the browser's own focus scrolling
 * (smooth or not) then stops above them.
 */

export interface Box {
  top: number;
  bottom: number;
}

/** Extra room between the focused element and the layer above it, px. */
export const FOCUS_CLEARANCE = 12;

/**
 * Height (px) at the bottom of a viewport of `viewportHeight` that the given
 * fixed layers cover, plus clearance; 0 if none is on screen.
 */
export function coveredBottom(viewportHeight: number, layers: Box[]): number {
  const onScreen = layers.filter((l) => l.bottom > l.top && l.top < viewportHeight && l.bottom > 0);
  if (!onScreen.length) return 0;
  const top = Math.min(...onScreen.map((l) => l.top));
  return Math.max(0, Math.ceil(viewportHeight - top) + FOCUS_CLEARANCE);
}

/** Painted boxes of the fixed bottom layers. The .cw root is a fixed column;
 *  only its visible children (teaser, launcher, panel) cover content. */
function layerBoxes(): Box[] {
  const boxes: Box[] = [];
  const bar = document.querySelector<HTMLElement>('#mobile-cta.visible');
  if (bar) boxes.push(bar.getBoundingClientRect());
  const cw = document.querySelector<HTMLElement>('.cw');
  if (cw) {
    for (const child of Array.from(cw.children)) {
      if (!(child instanceof HTMLElement) || child.hidden) continue;
      const r = child.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) boxes.push(r);
    }
  }
  return boxes;
}

export function installFocusUnobscured(): void {
  const root = document.documentElement;
  const update = () => {
    const px = coveredBottom(window.innerHeight, layerBoxes());
    root.style.setProperty('--wp-fixed-bottom-cover', `${px}px`);
  };
  let queued = false;
  const queue = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      update();
    });
  };
  // Tab's keydown fires before focus moves: the padding is current when the
  // browser scrolls the next element into view.
  document.addEventListener('keydown', (e) => { if (e.key === 'Tab') update(); }, true);
  // The bar and teaser appear on scroll; layers resize with the viewport.
  window.addEventListener('scroll', queue, { passive: true });
  window.addEventListener('resize', queue);
  update();
}
