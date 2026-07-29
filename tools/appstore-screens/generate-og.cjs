/**
 * WhisPaste — OG-Image Generator (photographic hero variant)
 *
 * Since 2026-07-29 the OG images ARE the approved hero-device composite
 * (photo background + real overlay pill + headline), cover-cropped from the
 * finished 1920×1080 render to the 1200×630 OG format — a deliberate reuse
 * of the exact shipped pixels instead of a second, drifting template.
 *
 * Aspect math: 1920×1080 (1.778:1) → 1200×630 (1.905:1). Cover scale is
 * 1200/1920 = 0.625 → scaled 1200×675, so only 45 px of vertical overflow
 * are cropped. `object-position` keeps 80 % of that crop at the TOP (empty
 * dark air above the laptop) so headline, badges and the overlay pill stay
 * fully visible near the bottom.
 *
 * The previous CSS-card template lives on in og-template.html (unused).
 *
 * Usage: node generate-og.cjs [--lang=en|de|all]
 */
const path = require('path');
const fs = require('fs');

const { chromium } = require('playwright');
const { ROOT } = require('./config');

const OUTPUT_DIR = path.join(__dirname, 'output', 'og');
const WEBSITE_PUBLIC = path.join(ROOT, 'website', 'public');

const OG_W = 1200;
const OG_H = 630;

// Fraction of the vertical overflow cropped from the TOP (rest from the
// bottom). 0.8 keeps the pill/badges zone with comfortable margin.
const CROP_TOP_BIAS = 0.8;

function heroRenderFor(lang) {
  const candidate = path.join(
    __dirname,
    'output',
    'hero-device',
    lang,
    'microsoft',
    '01_hero-device.png',
  );
  if (fs.existsSync(candidate)) return candidate;
  throw new Error(
    `Missing hero-device render for OG image: ${candidate}\n` +
      'Run: node render-hero-device.cjs --lang=all',
  );
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function toDataUri(filePath) {
  const buffer = fs.readFileSync(filePath);
  return `data:image/png;base64,${buffer.toString('base64')}`;
}

async function generateOgImage(lang) {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: OG_W, height: OG_H },
      deviceScaleFactor: 1,
    });

    const posY = (CROP_TOP_BIAS * 100).toFixed(0);
    await page.setContent(
      `<!DOCTYPE html>
      <html><head><style>
        * { margin: 0; padding: 0; }
        html, body { width: ${OG_W}px; height: ${OG_H}px; overflow: hidden; }
        img {
          width: 100%;
          height: 100%;
          object-fit: cover;
          object-position: 50% ${posY}%;
          display: block;
        }
      </style></head>
      <body><img src="${toDataUri(heroRenderFor(lang))}" alt=""></body></html>`,
      { waitUntil: 'networkidle' },
    );

    await page.waitForFunction(
      () => {
        const img = document.querySelector('img');
        return img && img.complete && img.naturalWidth > 0;
      },
      { timeout: 10000 },
    );

    ensureDir(OUTPUT_DIR);
    const outputPath = path.join(OUTPUT_DIR, `og-image-${lang}.png`);
    await page.screenshot({ path: outputPath, type: 'png' });

    // Fixed filenames — referenced by website/src/layouts/Layout.astro
    // (`/og-image.png` for en, `/og-image-de.png` for de). Do not rename.
    const websiteTarget =
      lang === 'en'
        ? path.join(WEBSITE_PUBLIC, 'og-image.png')
        : path.join(WEBSITE_PUBLIC, `og-image-${lang}.png`);
    fs.copyFileSync(outputPath, websiteTarget);

    console.log(`🖼️  og-image-${lang}.png (${OG_W}×${OG_H}, hero-device crop)`);
    console.log(`📋 Copied to ${path.relative(ROOT, websiteTarget)}`);
  } finally {
    await browser.close();
  }
}

async function main() {
  const langArg = (process.argv.find((a) => a.startsWith('--lang=')) || '--lang=all')
    .split('=')[1];
  const langs = langArg === 'all' ? ['en', 'de'] : [langArg];
  for (const lang of langs) {
    await generateOgImage(lang);
  }
  console.log('✅ OG images done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
