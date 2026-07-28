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
const BG_PHOTO = path.resolve(__dirname, 'assets', 'generated', 'hero-device-v1.png');

// Pill anchor (top-left) in photo source pixels: hovers off the screen's
// upper-right corner, detached from the display. The pill itself is built
// natively in CSS in the template (frosted glass per OverlayDesignSpec).
const PILL_POS = [818, 138];
const BG_W = 1344;
const BG_H = 768;

// Laptop screen quad in source-photo pixels: TL, TR, BR, BL.
const SCREEN_QUAD = [[635, 183], [953, 197], [964, 553], [694, 579]];

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
