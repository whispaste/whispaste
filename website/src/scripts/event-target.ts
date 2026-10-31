/**
 * Closest ancestor of an event target that matches `selector`.
 *
 * `event.target` is not always an Element: a click or pointer event can land
 * on a text node (Safari, some SVG/text layouts), and document-level listeners
 * also see `document` itself. Calling `.closest` on those throws
 * "closest is not a function" (Sentry WHISPASTE-WEBSITE-C). Text nodes resolve
 * through their parent element; anything else yields null.
 */
export function closestFromTarget<E extends Element = Element>(
  target: EventTarget | null,
  selector: string,
): E | null {
  const element = target instanceof Element ? target : target instanceof Node ? target.parentElement : null;
  return element?.closest<E>(selector) ?? null;
}
