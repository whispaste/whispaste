/**
 * Motion budget: endless decorative animations only run while their section
 * is on screen. The home page carries ~60 infinite CSS animations; left
 * running they keep layers busy for the whole visit, which Safari pays for in
 * memory and battery. One-shot entrance animations are left alone, so content
 * can never get stuck hidden if the observer misses a jump (Safari anchors).
 */
const SCOPES = 'section, footer, [data-motion-scope]';

function setRunning(scope: Element, running: boolean): void {
  for (const animation of scope.getAnimations({ subtree: true })) {
    if (animation.effect?.getTiming().iterations !== Infinity) continue;
    if (!running) {
      animation.pause();
      continue;
    }
    // A nested scope decides for itself whether its part is on screen.
    const target = animation.effect instanceof KeyframeEffect ? animation.effect.target : null;
    if (target && target.closest(SCOPES) !== scope && scope !== document.documentElement) continue;
    animation.play();
  }
}

export function startMotionBudget(): void {
  if (!('IntersectionObserver' in window) || typeof document.getAnimations !== 'function') return;
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) setRunning(entry.target, entry.isIntersecting);
    },
    { rootMargin: '200px 0px' },
  );
  for (const scope of document.querySelectorAll(SCOPES)) observer.observe(scope);
  // A hidden tab needs nothing running at all.
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      setRunning(document.documentElement, false);
      return;
    }
    // Re-observing reports every scope's current visibility once more.
    for (const scope of document.querySelectorAll(SCOPES)) {
      observer.unobserve(scope);
      observer.observe(scope);
    }
  });
}
