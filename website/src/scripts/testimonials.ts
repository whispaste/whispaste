// Testimonials from the WhisPaste API, read at build time (Testimonials.astro).
// The API enforces consent and withdrawal and never serves store reviews
// (internal-notes §6.7a); only the shape of the answer is checked here.
export const TESTIMONIALS_URL = 'https://api.whispaste.de/v1/public/testimonials';
export const MAX_TESTIMONIALS = 6;
const FETCH_TIMEOUT_MS = 10_000;

export interface Testimonial {
  rating: number;
  text: string;
}

/** Valid items of a schema-1 answer, at most {@link MAX_TESTIMONIALS}; anything else yields none. */
export function parseTestimonials(payload: unknown): Testimonial[] {
  const body = payload as { schema?: unknown; items?: unknown } | null;
  if (body?.schema !== 1 || !Array.isArray(body.items)) return [];
  return body.items
    .filter(
      (item): item is Testimonial =>
        typeof item?.text === 'string' && item.text !== '' && Number.isFinite(item?.rating),
    )
    .slice(0, MAX_TESTIMONIALS)
    .map(({ rating, text }) => ({ rating, text }));
}

/** Fetches the testimonials; an unreachable or broken API yields none so the build goes on. */
export async function loadTestimonials(
  fetchImpl: typeof fetch = fetch,
  warn: (message: string, detail?: unknown) => void = console.warn,
): Promise<Testimonial[]> {
  try {
    const res = await fetchImpl(TESTIMONIALS_URL, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    if (!res.ok) {
      warn(`[testimonials] API answered HTTP ${res.status}; section omitted at build time`);
      return [];
    }
    return parseTestimonials(await res.json());
  } catch (err) {
    warn('[testimonials] API unavailable at build time; section omitted', err);
    return [];
  }
}

/** Star count shown for a rating: whole stars, clamped to 0..5. */
export function starCount(rating: number): number {
  return Math.max(0, Math.min(5, Math.round(rating) || 0));
}

/** Index of the longest quote, which leads the grid; the first one wins a tie. */
export function featuredIndex(items: readonly Testimonial[]): number {
  return items.reduce((best, item, i) => (item.text.length > items[best].text.length ? i : best), 0);
}
