// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { closestFromTarget } from '../event-target';

// Regression for Sentry WHISPASTE-WEBSITE-C ("e.target.closest is not a function"):
// document-level pointer/click listeners also receive text nodes and `document`
// as targets, which have no `.closest()`.
describe('closestFromTarget', () => {
  function setup(): { card: HTMLElement; text: Text } {
    document.body.innerHTML = '<div class="wp-spot" data-contact-open><p>Hallo <b>Welt</b></p></div>';
    const card = document.querySelector<HTMLElement>('.wp-spot')!;
    const text = card.querySelector('p')!.firstChild as Text;
    return { card, text };
  }

  it('finds the matching ancestor for an element target', () => {
    const { card } = setup();
    const bold = card.querySelector('b')!;
    expect(closestFromTarget(bold, '.wp-spot')).toBe(card);
  });

  it('resolves a text node target through its parent element', () => {
    const { card, text } = setup();
    expect(closestFromTarget(text, '.wp-spot')).toBe(card);
    expect(closestFromTarget(text, '[data-contact-open]')).toBe(card);
  });

  it('returns null for a text node without a matching ancestor, without throwing', () => {
    const { text } = setup();
    expect(closestFromTarget(text, '.does-not-exist')).toBeNull();
  });

  it('returns null for document and window-like targets instead of throwing', () => {
    setup();
    expect(closestFromTarget(document, '.wp-spot')).toBeNull();
    expect(closestFromTarget(null, '.wp-spot')).toBeNull();
    expect(closestFromTarget(window, '.wp-spot')).toBeNull();
  });

  it('works for events dispatched on a text node and on document (listener path)', () => {
    const { card, text } = setup();
    const seen: Array<Element | null> = [];
    const listener = (e: Event) => seen.push(closestFromTarget(e.target, '.wp-spot'));
    document.addEventListener('click', listener);
    try {
      text.dispatchEvent(new Event('click', { bubbles: true }));
      document.dispatchEvent(new Event('click', { bubbles: true }));
    } finally {
      document.removeEventListener('click', listener);
    }
    expect(seen).toEqual([card, null]);
  });
});
