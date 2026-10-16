import { expect, test } from '@playwright/test';

/**
 * Rendered contrast audit (design-tokens/README.md, "Checks", layer 3). The
 * token test proves the roles pair up; this proves the pages actually use
 * them that way: every visible text node is measured against the background
 * it really sits on, at a phone and a desktop width.
 */
const ROUTES = [
  '/',
  '/en/',
  '/zh/',
  '/download/',
  '/sponsor/',
  '/screenshots/',
  '/changelog/',
  '/impressum/',
  '/datenschutz/',
  '/whisper-desktop/',
  '/gpu-kompatibilitaet/',
  '/whisper-modellgroesse/',
  '/linux-spracherkennung/',
  '/engines/',
  '/engine-benchmarks/',
  '/use-cases/',
  '/blog/',
  '/en/whisper-desktop/',
];
const WIDTHS = [390, 1440];

for (const width of WIDTHS) {
  for (const route of ROUTES) {
    test(`text contrast meets WCAG AA on ${route} at ${width}px`, async ({ page }) => {
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.setViewportSize({ width, height: 900 });
      await page.goto(route);
      await page.evaluate(() => document.fonts.ready);
      const { measured, worst, failures } = await page.evaluate(audit);
      test.info().annotations.push({ type: 'contrast', description: `${measured} elements, worst ${worst.toFixed(2)}` });
      // Guards against a vacuous pass: the page must actually have been measured.
      expect(measured).toBeGreaterThan(20);
      expect(failures).toEqual([]);
    });
  }
}

/** Runs in the page. Returns one line per text element below AA. */
function audit(): { measured: number; worst: number; failures: string[] } {
  const canvas = document.createElement('canvas').getContext('2d', { willReadFrequently: true })!;
  type Rgba = [number, number, number, number];
  // The canvas normalises every CSS colour syntax (oklch, color-mix, …) to sRGB.
  const parse = (css: string): Rgba => {
    canvas.clearRect(0, 0, 1, 1);
    canvas.fillStyle = '#000';
    canvas.fillStyle = css;
    canvas.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = canvas.getImageData(0, 0, 1, 1).data;
    return [r, g, b, a / 255];
  };
  const over = (top: Rgba, base: Rgba): Rgba => {
    const a = top[3];
    return [0, 1, 2].map((i) => top[i] * a + base[i] * (1 - a)).concat(1) as Rgba;
  };
  const lum = ([r, g, b]: Rgba) =>
    [r, g, b]
      .map((v) => v / 255)
      .map((s) => (s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4))
      .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
  const ratio = (a: Rgba, b: Rgba) => {
    const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };

  // The page stage is a gradient on <html>: text on it must work on every stop.
  const rootStyle = getComputedStyle(document.documentElement);
  const stage = ['--wp-color-navy-700', '--wp-color-navy-600', '--wp-color-navy-500'].map((v) =>
    parse(rootStyle.getPropertyValue(v).trim()),
  );

  /** Background layers from the element up; null when an image or gradient decides it. */
  function backgrounds(el: Element): Rgba[][] | null {
    const layers: Rgba[] = [];
    for (let node: Element | null = el; node; node = node.parentElement) {
      const cs = getComputedStyle(node);
      const isRoot = node === document.documentElement || node === document.body;
      if (cs.backgroundImage !== 'none' && !isRoot) return null;
      const bg = parse(cs.backgroundColor);
      if (bg[3] > 0) layers.push(bg);
      if (bg[3] >= 1) return [layers];
      if (isRoot && node === document.documentElement) break;
    }
    return stage.map((stop) => [...layers, stop]);
  }

  const failures: string[] = [];
  let measured = 0;
  let lowest = Infinity;
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const seen = new Set<Element>();
  for (let text = walker.nextNode(); text; text = walker.nextNode()) {
    const el = text.parentElement;
    if (!el || seen.has(el) || !text.textContent?.trim()) continue;
    seen.add(el);
    if (el.closest('[aria-hidden="true"], script, style, noscript, template, .sr-only, dialog:not([open])')) continue;
    const rect = el.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility !== 'visible' || cs.display === 'none') continue;
    // Gradient text paints with background-clip; its colour is transparent.
    if (cs.webkitTextFillColor && parse(cs.webkitTextFillColor)[3] === 0) continue;
    let opacity = 1;
    let hidden = false;
    for (let node: Element | null = el; node; node = node.parentElement) {
      const o = Number(getComputedStyle(node).opacity);
      if (o === 0) hidden = true;
      opacity *= o;
    }
    if (hidden) continue;
    const stack = backgrounds(el);
    if (!stack) continue;
    const size = parseFloat(cs.fontSize);
    const bold = Number(cs.fontWeight) >= 700;
    const need = size >= 24 || (bold && size >= 18.66) ? 3 : 4.5;
    const fg = parse(cs.color);
    const worst = Math.min(
      ...stack.map((layers) => {
        const bg = layers.reduceRight<Rgba>((base, layer) => over(layer, base), [0, 0, 0, 1]);
        return ratio(over([fg[0], fg[1], fg[2], fg[3] * opacity], bg), bg);
      }),
    );
    measured += 1;
    lowest = Math.min(lowest, worst / need);
    if (worst < need) {
      const id = el.closest('[data-testid]')?.getAttribute('data-testid') ?? el.className.toString().slice(0, 40);
      failures.push(`${worst.toFixed(2)} < ${need} "${text.textContent.trim().slice(0, 40)}" (${el.tagName.toLowerCase()} in ${id})`);
    }
  }
  return { measured, worst: lowest, failures };
}
