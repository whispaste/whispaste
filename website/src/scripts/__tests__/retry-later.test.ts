import { describe, expect, it } from 'vitest';
import { contactStatusKey } from '../contact-status';
import { newsletterOutcome } from '../newsletter';
import { outcomeOf } from '../newsletter-link';

describe('503 store_unavailable maps to a retry-later state, never success', () => {
  const body = JSON.stringify({ code: 'store_unavailable', status: 503 });

  it('contact widget', () => {
    expect(contactStatusKey(503)).toBe('retryLater');
    expect(contactStatusKey(500)).toBe('error');
  });

  it('newsletter sign-up', () => {
    expect(newsletterOutcome(503, body)).toBe('unavailable');
  });

  it('newsletter link pages are neither done nor invalid', () => {
    expect(outcomeOf(503, JSON.parse(body), '120').state).toBe('unavailable');
  });
});
