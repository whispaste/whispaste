/**
 * WhisPaste — Device-Photo Hero Renderer (comparison candidate)
 *
 * Standalone renderer for the photographic hero variant: composites a real
 * app-UI golden onto the laptop screen of the fal.ai-generated background
 * (assets/generated/hero-device-v1.png) via a CSS homography, with live
 * HTML headline/subtitle/badges from the hero entry in config.js.
 *
 * Deliberately separate from generate.cjs so the production pipeline stays
 * untouched while the maintainer compares hero candidates.
 *
 * Usage: node render-hero-device.cjs [--lang=en|de|all]
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const { STORE_SIZES, SCREENS, GOLDENS, OUTPUT } = require('./config');

const TEMPLATE_PATH = path.resolve(__dirname, 'hero-device-template.html');
// v2 photo: realistically proportioned widescreen 16:10 panel, so the golden
// can fill the whole glass through the homography with correct perspective.
const BG_PHOTO = path.resolve(__dirname, 'assets', 'generated', 'hero-device-v2.png');

// Pill anchor (top-left) in photo source pixels: hovers off the screen's
// upper-right bezel, detached from the display. The pill itself is built
// natively in CSS in the template (frosted glass per OverlayDesignSpec),
// rendered in its compact size (220x40).
const PILL_POS = [828, 112];
const BG_W = 1344;
const BG_H = 768;

// Laptop screen quad in source-photo pixels: TL, TR, BR, BL.
//
// Measured programmatically, not eyeballed: scanned the raw pixel data for
// the bezel's bright cyan-ish rim-light along each edge (many points per
// edge, away from the hand), least-squares-fit a line to each edge, and
// intersected top/left and top/right for TL/TR. The bottom edge is mostly
// occluded by the hand and too low-contrast against the dark keyboard deck
// to trace directly, so BL/BR come from the (cross-validated) parallel-sides
// assumption: the fitted left-edge line predicted x=660.4 at the one clean
// bottom-left sample point (660, 384) found before the hand — a ~0.5px
// match, confirming the line fit — and BR = TR + (BL - TL), i.e. the same
// side vector applied to the right edge (a real rectangle's opposite sides
// are equal-length and parallel; the independently-fit right-edge slope
// agreed with this within ~2px, cross-validating the whole quad). The
// previous hand-picked corners put BL/BR roughly 120-135px too low, onto
// the keyboard deck instead of the glass — see 660-value discrepancy vs.
// the prior (689, 519).
const SCREEN_QUAD = [[602, 172], [963, 147], [1022, 358], [660, 384]];

// Horizontal focus point (0..1) when cover-cropping the photo.
const FOCUS_X = 0.62;

const STORES = ['mac', 'microsoft'];

function toDataUri(filePath) {
  const buffer = fs.readFileSync(filePath);
  return `data:image/png;base64,${buffer.toString('base64')}`;
}

function goldenFor(lang, storeId) {
  const base = STORE_SIZES[storeId].goldenBase || '';
  return path.join(GOLDENS, `${base}${lang}/dark/01_workspace_overview.png`);
}

async function render(page, lang, storeId, hero) {
  const { width: W, height: H } = STORE_SIZES[storeId];

  await page.setViewportSize({ width: W, height: H });
  await page.setContent(fs.readFileSync(TEMPLATE_PATH, 'utf-8'), {
    waitUntil: 'networkidle',
  });

  await page.evaluate(
    (params) => window.setupHero(params),
    {
      W,
      H,
      imgW: BG_W,
      imgH: BG_H,
      quad: SCREEN_QUAD,
      focusX: FOCUS_X,
      bgData: toDataUri(BG_PHOTO),
      shotData: toDataUri(goldenFor(lang, storeId)),
      pillPos: PILL_POS,
      copy: {
        headline: hero.headline,
        subtitle: hero.subtitle,
        badges: hero.badges,
      },
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

  const outDir = path.join(OUTPUT, 'hero-device', lang, storeId);
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, '01_hero-device.png');
  await page.screenshot({ path: outPath, type: 'png', clip: { x: 0, y: 0, width: W, height: H } });
  console.log(`  🖼️  [${storeId}/${lang}] ${outPath} (${W}×${H})`);
}

async function main() {
  const langArg = process.argv.slice(2).find((a) => a.startsWith('--lang='))?.split('=')[1] || 'all';
  const langs = langArg === 'all' ? ['en', 'de'] : [langArg];

  const hero = SCREENS.find((s) => s.id === 'hero');
  if (!hero) throw new Error('No hero entry in SCREENS');
  if (!fs.existsSync(BG_PHOTO)) throw new Error(`Missing background photo: ${BG_PHOTO}`);

  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ deviceScaleFactor: 1 });
    for (const lang of langs) {
      for (const storeId of STORES) {
        await render(page, lang, storeId, hero);
      }
    }
  } finally {
    await browser.close();
  }
  console.log('✅ hero-device renders done');
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});
