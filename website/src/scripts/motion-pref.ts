/**
 * Visitor's own "pause animations" switch (#1910, WCAG 2.2.2).
 *
 * The OS "reduce motion" setting stops the endless decorative motion, but a
 * visitor who has not set it needs an in-page control. The footer button
 * flips this flag; it is stored locally (no cookie, nothing sent) and set on
 * <html data-motion="paused"> by an inline head script before first paint,
 * so a reload keeps it. Everything that loops (CSS animations via
 * motion-budget.ts, the text band, the hero step player, motion videos)
 * asks `motionStopped()` and listens for MOTION_EVENT.
 */

export const MOTION_KEY = 'wp-motion-paused';
export const MOTION_EVENT = 'wp:motion-change';

/** Head inline script (Layout.astro) applying the stored choice early. */
export const APPLY_MOTION_PREF_JS = `try{if(localStorage.getItem(${JSON.stringify(MOTION_KEY)})==='1')document.documentElement.dataset.motion='paused'}catch(e){}`;

/** True when the visitor paused animations on this site. */
export function motionPaused(): boolean {
  return document.documentElement.dataset.motion === 'paused';
}

/** True when nothing should loop: OS reduced motion or the in-page switch. */
export function motionStopped(): boolean {
  return motionPaused() || window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export function setMotionPaused(paused: boolean): void {
  const root = document.documentElement;
  if (paused) root.dataset.motion = 'paused';
  else delete root.dataset.motion;
  try {
    if (paused) localStorage.setItem(MOTION_KEY, '1');
    else localStorage.removeItem(MOTION_KEY);
  } catch {
    // Private mode without storage: the switch still holds for this page.
  }
  document.dispatchEvent(new CustomEvent(MOTION_EVENT, { detail: { paused } }));
}

/** Calls `fn` whenever the switch changes. */
export function onMotionChange(fn: (paused: boolean) => void): void {
  document.addEventListener(MOTION_EVENT, () => fn(motionPaused()));
}

/** Wires every [data-motion-toggle] button (aria-pressed = paused). */
export function installMotionToggle(): void {
  const buttons = document.querySelectorAll<HTMLButtonElement>('[data-motion-toggle]');
  const sync = () => buttons.forEach((b) => b.setAttribute('aria-pressed', String(motionPaused())));
  buttons.forEach((b) => b.addEventListener('click', () => setMotionPaused(!motionPaused())));
  onMotionChange(sync);
  sync();
}
