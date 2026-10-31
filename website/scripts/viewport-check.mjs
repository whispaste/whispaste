#!/usr/bin/env node
// Manuelles Viewport-Diagnose-Tool für die Cinematic-Redesign-Arbeit (M10 Set-Pieces).
// Nutzt dieselbe Playwright-Installation wie die E2E-Suite (`npm test`), kein separates
// Browser-Binary/keine separate Version zu pflegen. Kein Teil des CI-Gates.
//
// Usage:
//   node scripts/viewport-check.mjs [url] [--out=<dir>]
//   PLAYWRIGHT_PORT=4321 node scripts/viewport-check.mjs
//
// Screenshottet + prüft horizontales Overflow bei den Standard-Breakpoints
// (390 Mobile, 820 Tablet, 1440 Desktop). Für animationsspezifische Checks
// (getAnimations()/getComputedTiming()) direkt page.evaluate() im Bedarfsfall
// erweitern -- scroll-behavior:smooth auf <html> beachten: nach scrollTo()
// echte Zeit warten (waitForTimeout), nicht nur requestAnimationFrame, sonst
// wird eine noch laufende Scroll-Animation als Endzustand fehlinterpretiert.

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const url = process.argv.find((a) => !a.startsWith('--') && a !== process.argv[0] && a !== process.argv[1])
  ?? `http://127.0.0.1:${process.env.PLAYWRIGHT_PORT ?? 4321}/`;
const outArg = process.argv.find((a) => a.startsWith('--out='));
const outDir = outArg ? outArg.slice('--out='.length) : '.viewport-check';

const VIEWPORTS = [
  { name: 'mobile-390', width: 390, height: 844 },
  { name: 'tablet-820', width: 820, height: 1180 },
  { name: 'desktop-1440', width: 1440, height: 900 },
];

mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch();
let hadOverflow = false;

for (const vp of VIEWPORTS) {
  const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1000); // Load-Choreografie (M10 rise-in etc.) abwarten

  const overflow = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    viewportWidth: window.innerWidth,
  }));
  const overflows = overflow.scrollWidth > overflow.viewportWidth;
  if (overflows) hadOverflow = true;

  console.log(
    `${vp.name.padEnd(14)} scrollWidth=${overflow.scrollWidth} viewportWidth=${overflow.viewportWidth}` +
      (overflows ? '  HORIZONTAL OVERFLOW' : '')
  );

  await page.screenshot({ path: `${outDir}/${vp.name}.png`, fullPage: true });
  await page.close();
}

await browser.close();
console.log(`\nScreenshots: ${outDir}/`);
if (hadOverflow) {
  console.error('Horizontales Overflow gefunden -- siehe oben.');
  process.exit(1);
}
