#!/usr/bin/env node
/**
 * generate-store-trailer.mjs — AFK pipeline that turns the website's
 * #app-paste-demo storyboard (the polished "hotkey → speak → text at cursor"
 * animation, which uses the REAL OverlayPainter via shared overlay-mockup)
 * into an MS-Store-conformant trailer.
 *
 * Pipeline:
 *   1. astro build        — deterministic production HTML
 *   2. astro preview      — local static server
 *   3. Playwright headless — 1920x1080 capture of #app-paste-demo (~14s)
 *   4. build-store-trailer.sh — encode webm → MS-Store trailer.mp4 + thumb.png
 *
 * Fully autonomous: one command in, one trailer out. No manual recording.
 *
 * Usage:
 *   node website/scripts/generate-store-trailer.mjs               # DE (/)
 *   node website/scripts/generate-store-trailer.mjs --locale en   # EN (/en/)
 *
 * Requires (already present): website deps + playwright chromium.
 */
import { spawn, execSync } from 'node:child_process';
import { chromium } from '@playwright/test';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const WEBSITE = resolve(__dirname, '..');
const REPO = resolve(WEBSITE, '..');
const OUT = resolve(REPO, 'store/_build');

const args = process.argv.slice(2);
const localeIdx = args.indexOf('--locale');
const LOCALE = localeIdx >= 0 ? args[localeIdx + 1] : 'de';
const PATH_ = LOCALE === 'en' ? '/en/' : '/';
const PORT = 4523;
const CAPTURE_MS = 14000; // AppPasteDemo runs a ~12s cycle; +2s settle buffer

const log = (m) => process.stderr.write(`[trailer] ${m}\n`);

async function waitForUrl(url, ms = 30000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(url);
      if (r.ok) return;
    } catch {
      /* not ready yet */
    }
    await new Promise((j) => setTimeout(j, 500));
  }
  throw new Error(`preview server not ready at ${url} within ${ms}ms`);
}

async function main() {
  log(`locale=${LOCALE} → building site…`);
  execSync('npm run build', { cwd: WEBSITE, stdio: 'inherit' });

  log('starting astro preview…');
  const preview = spawn('npx', ['astro', 'preview', '--port', String(PORT)], {
    cwd: WEBSITE,
    stdio: 'ignore',
  });
  try {
    await waitForUrl(`http://localhost:${PORT}/`);

    log(`playwright headless capture (1920x1080, ${CAPTURE_MS / 1000}s)…`);
    const browser = await chromium.launch();
    const ctx = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      deviceScaleFactor: 1,
      recordVideo: { dir: OUT, size: { width: 1920, height: 1080 } },
    });
    const page = await ctx.newPage();
    await page.goto(`http://localhost:${PORT}${PATH_}`, { waitUntil: 'networkidle' });

    // Drive the demo deterministically: scroll it into view + force the
    // scroll-reveal `.visible` state so all entrance/keyframe animations run.
    await page.locator('#app-paste-demo').scrollIntoViewIfNeeded();
    await page.evaluate(() => {
      document.getElementById('app-paste-demo')?.classList.add('visible');
    });
    await page.waitForTimeout(CAPTURE_MS);

    const video = page.video();
    await ctx.close();
    await browser.close();
    const webm = await video.path();
    log(`captured: ${webm}`);

    log('encoding to MS-Store spec via build-store-trailer.sh…');
    execSync(
      `"${resolve(REPO, 'scripts/build-store-trailer.sh')}" "${webm}" --out "${OUT}"`,
      { stdio: 'inherit' },
    );
    log('done.');
  } finally {
    preview.kill('SIGTERM');
  }
}

main().catch((e) => {
  process.stderr.write(`✗ ${e.stack || e.message}\n`);
  process.exit(1);
});
