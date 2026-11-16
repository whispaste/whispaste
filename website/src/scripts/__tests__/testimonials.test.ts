import { describe, expect, it, vi } from 'vitest';
import { featuredIndex, loadTestimonials, MAX_TESTIMONIALS, parseTestimonials, starCount } from '../testimonials';

const item = (n: number) => ({ rating: 5, text: `quote ${n}`, received_at: '2026-11-05' });
const asFetch = (fn: unknown) => fn as typeof fetch;

describe('parseTestimonials', () => {
  it('keeps rating and text of a schema 1 answer', () => {
    expect(parseTestimonials({ schema: 1, items: [item(1)] })).toEqual([{ rating: 5, text: 'quote 1' }]);
  });

  it('takes at most six items', () => {
    const items = Array.from({ length: 9 }, (_, i) => item(i));
    expect(parseTestimonials({ schema: 1, items })).toHaveLength(MAX_TESTIMONIALS);
  });

  it('ignores another schema version or a missing item list', () => {
    expect(parseTestimonials({ schema: 2, items: [item(1)] })).toEqual([]);
    expect(parseTestimonials({ schema: 1 })).toEqual([]);
    expect(parseTestimonials(null)).toEqual([]);
  });

  it('drops items without text or with a rating that is not a number', () => {
    const items = [item(1), { rating: Number.NaN, text: 'x' }, { rating: 4, text: '' }, { rating: 4 }, null];
    expect(parseTestimonials({ schema: 1, items })).toEqual([{ rating: 5, text: 'quote 1' }]);
  });
});

describe('loadTestimonials', () => {
  it('returns the parsed items', async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ schema: 1, items: [item(1)] })));
    expect(await loadTestimonials(asFetch(fetchImpl), vi.fn())).toHaveLength(1);
  });

  it('returns none and warns when the API is unreachable', async () => {
    const warn = vi.fn();
    const fetchImpl = vi.fn(async () => {
      throw new TypeError('fetch failed');
    });
    expect(await loadTestimonials(asFetch(fetchImpl), warn)).toEqual([]);
    expect(warn).toHaveBeenCalledOnce();
  });

  it('returns none and warns on an HTTP error', async () => {
    const warn = vi.fn();
    const fetchImpl = vi.fn(async () => new Response('', { status: 503 }));
    expect(await loadTestimonials(asFetch(fetchImpl), warn)).toEqual([]);
    expect(warn).toHaveBeenCalledOnce();
  });
});

describe('starCount', () => {
  it('rounds to whole stars and clamps to 0..5', () => {
    expect([7, -1, 3.6, 0].map(starCount)).toEqual([5, 0, 4, 0]);
  });
});

describe('featuredIndex', () => {
  it('picks the longest quote and the first one on a tie', () => {
    const q = (text: string) => ({ rating: 5, text });
    expect(featuredIndex([q('aa'), q('aaaa'), q('bbbb')])).toBe(1);
  });
});
