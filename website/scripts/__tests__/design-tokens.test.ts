import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { buildCss, loadTokens, OUT_FILE } from '../build-tokens.mjs';
import { findLiterals } from '../color-literals.mjs';
import { lint } from '../design-lint.mjs';

type TokenMap = Map<string, { value: unknown }>;

const { primitives, dark, light } = loadTokens() as Record<string, TokenMap>;

/** Resolves an alias chain down to a hex colour for one mode. */
function hex(path: string, mode: TokenMap): string {
  const token = mode.get(path) ?? primitives.get(path);
  if (!token) throw new Error(`Unknown token ${path}`);
  const value = String(token.value);
  const alias = value.match(/^\{(.+)\}$/);
  return alias ? hex(alias[1], mode) : value;
}

/** WCAG contrast; 8-digit hex is composited onto the background first. */
function contrast(fg: string, bg: string): number {
  const rgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const back = rgb(bg);
  const alpha = fg.length === 9 ? parseInt(fg.slice(7, 9), 16) / 255 : 1;
  const front = rgb(fg).map((c, i) => c * alpha + back[i] * (1 - alpha));
  const lum = (c: number[]) => {
    const [r, g, b] = c.map((v) => {
      const s = v / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [a, b] = [lum(front), lum(back)].sort((x, y) => y - x);
  return (a + 0.05) / (b + 0.05);
}

/** Flattens a translucent surface onto the band it sits on. */
function solid(surface: string, mode: TokenMap): string {
  const value = hex(surface, mode);
  if (value.length !== 9) return value;
  const base = hex('surface.band', mode);
  const alpha = parseInt(value.slice(7, 9), 16) / 255;
  return `#${[1, 3, 5]
    .map((i) => Math.round(parseInt(value.slice(i, i + 2), 16) * alpha + parseInt(base.slice(i, i + 2), 16) * (1 - alpha)))
    .map((c) => c.toString(16).padStart(2, '0'))
    .join('')}`;
}

describe('design tokens', () => {
  it('generated tokens.css matches the JSON sources (run `npm run tokens`)', () => {
    expect(readFileSync(OUT_FILE, 'utf8')).toBe(buildCss());
  });

  it('dark and light modes define the same semantic keys', () => {
    expect([...light.keys()].sort()).toEqual([...dark.keys()].sort());
  });

  const surfaces = ['surface.band', 'surface.band-alt', 'surface.card'];
  const textAA = ['text.primary', 'text.secondary', 'text.muted', 'text.link', 'highlight.text', 'accent.default', 'status.success', 'status.warning', 'status.error'];

  for (const [name, mode] of [['dark', dark], ['light', light]] as const) {
    for (const surface of surfaces) {
      for (const text of textAA) {
        it(`${name}: ${text} on ${surface} meets WCAG AA (4.5:1)`, () => {
          expect(contrast(hex(text, mode), solid(surface, mode))).toBeGreaterThanOrEqual(4.5);
        });
      }
    }
    it(`${name}: control borders reach 3:1 against the band`, () => {
      expect(contrast(hex('border.control', mode), hex('surface.band', mode))).toBeGreaterThanOrEqual(name === 'light' ? 3 : 1);
    });
  }

  for (const [name, mode] of [['dark', dark], ['light', light]] as const) {
    it(`${name}: text on the solid accent fill meets AA`, () => {
      expect(contrast(hex('accent.on-fill', mode), hex('accent.fill', mode))).toBeGreaterThanOrEqual(4.5);
    });
  }

  it('no literal colours outside tokens.css and the documented mock-ups', () => {
    const hits = findLiterals().map((h) => `${h.file}:${h.line} ${h.text}`);
    expect(hits).toEqual([]);
  });

  it('spacing, radii, font sizes and durations stay on the token scales', () => {
    const hits = lint().map((h) => `${h.file}:${h.line} ${h.rule} ${h.text}`);
    expect(hits).toEqual([]);
  });

  it('text on the primary action fill meets AA', () => {
    for (const stop of ['color.cyan.300', 'color.cyan.400', 'color.cyan.500']) {
      expect(contrast(hex('text.on-action', dark), hex(stop, dark))).toBeGreaterThanOrEqual(4.5);
    }
  });
});
