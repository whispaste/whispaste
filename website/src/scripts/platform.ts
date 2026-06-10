/**
 * platform.ts — client-side OS accessor.
 *
 * Reads the `data-os` attribute that the inline head script in Layout.astro
 * sets before first paint. The `data-os` value is sourced from `detectOs`
 * (platforms.ts) — both share the same `Os` contract including `'linux'`.
 *
 * This module does NOT re-run OS detection from the UA; it only reads the
 * pre-computed `data-os` attribute so the DOM is the single runtime source
 * of truth. The pure `detectOs` logic lives in `src/data/platforms.ts` and
 * is unit-tested there without DOM access.
 */
import type { Os } from '../data/platforms.ts';

export type { Os };

/** @deprecated Use `Os` from `src/data/platforms.ts` instead. */
export type Platform = Os;

/**
 * Returns the OS that was detected by the inline head script.
 * Reads `document.documentElement.dataset.os` (set before first paint).
 */
export function detectPlatform(): Os {
  if (typeof document === 'undefined') return 'unknown';
  const os = document.documentElement.dataset.os;
  if (os === 'windows') return 'windows';
  if (os === 'macos') return 'macos';
  if (os === 'linux') return 'linux';
  return 'unknown';
}
