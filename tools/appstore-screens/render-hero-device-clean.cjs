/**
 * WhisPaste — Clean Device-Photo Renderer (website background variant)
 *
 * Reduced sibling of render-hero-device.cjs: composites the real app-UI
 * golden onto the laptop screen of the device photo via the same CSS
 * homography — but WITHOUT the floating overlay pill and WITHOUT any text
 * layer (no headline/subtitle/badges, no contrast scrim). Output is the
 * full uncropped photo canvas at 2x (2688×1536), meant as a flexible
 * atmosphere/background source the website crops per-slot via CSS
 * `object-fit: cover` / `object-position`. Astro's image pipeline handles
 * AVIF/WebP conversion at build time — this script ships lossless PNG only.
 *
 * All scene constants (photo, screen quad, golden lookup) are imported from
 * render-hero-device.cjs so both pipelines stay single-source.
 *
 * Usage: node render-hero-device-clean.cjs [--lang=en|de|all]
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const {
  TEMPLATE_PATH,
  BG_PHOTO,
  BG_W,
  BG_H,
  SCREEN_QUAD,
  FOCUS_X,
  toDataUri,
  goldenFor,
} = require('./render-hero-device.cjs');

// Website source-asset location: Astro only optimizes images imported from
// src/, so the clean variants live there (not in public/).
const OUT_DIR = path.resolve(__dirname, '..', '..', 'website', 'src', 'assets', 'hero-device');

// 2x the photo's native 1344×768 canvas: the golden inside the screen quad
// is genuinely high-res and stays crisp at 2x, while the photo upscales
// smoothly (same interpolation the approved 1920×1080 store render uses).
const SCALE_FACTOR = 2;

// Root goldens (= the Microsoft-store golden set) are the canonical
// website screenshots: website/public/screenshots/{lang}/dark/01_….png
const GOLDEN_STORE = 'microsoft';

async function render(browser, lang) {
  const page = await browser.newPage({ deviceScaleFactor: SCALE_FACTOR });
  await page.setViewportSize({ width: BG_W, height: BG_H });
  await page.setContent(fs.readFileSync(TEMPLATE_PATH, 'utf-8'), {
    waitUntil: 'networkidle',
  });

  await page.evaluate(
    (params) => window.setupHero(params),
    {
      W: BG_W,
      H: BG_H,
      imgW: BG_W,
      imgH: BG_H,
      quad: SCREEN_QUAD,
      focusX: FOCUS_X,
      bgData: toDataUri(BG_PHOTO),
      shotData: toDataUri(goldenFor(lang, GOLDEN_STORE)),
      // Clean variant: no pill, no copy → template drops those layers.
      pillAnchor: null,
      pillStage: null,
      pillFrac: 0,
      pillData: null,
      copy: null,
      locale: lang,
    },
  );

  await page.waitForFunction(
    () => {
      const images = document.querySelectorAll('img[src]');
      return Array.from(images).every((img) => img.complete && img.naturalWidth > 0);
    },
    { timeout: 10000 },
  );
  await page.waitForTimeout(400);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const outPath = path.join(OUT_DIR, `hero-device-clean-${lang}.png`);
  await page.screenshot({
    path: outPath,
    type: 'png',
    clip: { x: 0, y: 0, width: BG_W, height: BG_H },
  });
  await page.close();
  console.log(`  🖼️  [clean/${lang}] ${outPath} (${BG_W * SCALE_FACTOR}×${BG_H * SCALE_FACTOR})`);
}

async function main() {
  const langArg = process.argv.slice(2).find((a) => a.startsWith('--lang='))?.split('=')[1] || 'all';
  const langs = langArg === 'all' ? ['en', 'de'] : [langArg];

  if (!fs.existsSync(BG_PHOTO)) throw new Error(`Missing background photo: ${BG_PHOTO}`);
  for (const lang of langs) {
    const golden = goldenFor(lang, GOLDEN_STORE);
    if (!fs.existsSync(golden)) throw new Error(`Missing golden: ${golden}`);
  }

  const browser = await chromium.launch();
  try {
    for (const lang of langs) {
      await render(browser, lang);
    }
  } finally {
    await browser.close();
  }
  console.log('✅ hero-device clean renders done');
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});
