/**
 * Regression guard for the homepage LCP element (`#heroLogo` in `Hero.astro`,
 * confirmed via Lighthouse `lcp-breakdown-insight`/`image-delivery-insight`,
 * `.scratch/seo-audit/2026-08-07/issues/01-homepage-lcp-image-optimization.md`).
 *
 * The icon is displayed at a maximum CSS box of 80x80 (`sm:w-20 sm:h-20`).
 * Lighthouse flagged the shipped 256x256 source as ~96% wasted bytes for
 * that display size. This test pins both theme variants (dark/light — the
 * hero swaps between them, see `src/scripts/theme.ts`) to dimensions and a
 * file size that stay close to the real display need, so a future re-export
 * at full app-icon resolution regresses loudly instead of silently.
 */
import { readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const PUBLIC_DIR = resolve(import.meta.dirname, "../../public");

/** Reads width/height from a PNG's IHDR chunk (bytes 16-23, big-endian). */
function pngDimensions(path: string): { width: number; height: number } {
  const buf = readFileSync(path);
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
  };
}

describe("hero logo icon (homepage LCP element)", () => {
  // 2x the largest real display box (80px) so retina stays crisp; well below
  // the previous 256x256 source that Lighthouse flagged as ~96% waste.
  const MAX_DIMENSION = 160;
  const MAX_BYTES = 4096;

  it.each(["app-icon-dark.png", "app-icon-light.png"])(
    "%s is sized for its actual display size, not full app-icon resolution",
    (filename) => {
      const path = resolve(PUBLIC_DIR, filename);
      const { width, height } = pngDimensions(path);
      expect(width).toBeLessThanOrEqual(MAX_DIMENSION);
      expect(height).toBeLessThanOrEqual(MAX_DIMENSION);
      expect(statSync(path).size).toBeLessThanOrEqual(MAX_BYTES);
    },
  );
});
