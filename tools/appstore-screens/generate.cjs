/**
 * WhisPaste — Store Screenshot Generator
 *
 * Builds decorated store screenshots from real localized UI screenshots,
 * then copies composites and raw UI screens into the website's public assets.
 *
 * Each enabled store renders its own panorama at its own dimensions and
 * uses its own golden screenshot set (per `goldenBase` in config.js), so
 * Microsoft Store gets Windows chrome and Mac App Store gets macOS chrome.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');

const {
  STORE_SIZES,
  ENABLED_STORES,
  FUTURE_STORES,
  SCREENS,
  OUTPUT,
  GOLDENS,
  WEBSITE_SCREENSHOTS_ROOT,
  WEBSITE_STORE_SCREENSHOTS,
  WEBSITE_UI_SCREENSHOTS,
} = require('./config');

const TEMPLATE_PATH = path.resolve(__dirname, 'template.html');
const NUM_SCREENS = SCREENS.length;

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function cleanDir(dir) {
  if (fs.existsSync(dir)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  fs.mkdirSync(dir, { recursive: true });
}

function removeRootPngs(dir) {
  if (!fs.existsSync(dir)) {
    return;
  }

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.toLowerCase().endsWith('.png')) {
      fs.rmSync(path.join(dir, entry.name), { force: true });
    }
  }
}

function toDataUri(filePath) {
  const buffer = fs.readFileSync(filePath);
  return `data:image/png;base64,${buffer.toString('base64')}`;
}

/**
 * Resolves the golden screenshot path for a given screen, language, and store.
 *
 * Mac goldens live under `mac/` while Windows goldens are at the root.
 */
function screenshotPathFor(screen, lang, storeId) {
  const store = STORE_SIZES[storeId];
  const base = store.goldenBase || '';
  return path.join(GOLDENS, base + screen.screenshot[lang]);
}

function verifySourceImages() {
  for (const storeId of ENABLED_STORES) {
    for (const lang of ['en', 'de']) {
      for (const screen of SCREENS) {
        const filePath = screenshotPathFor(screen, lang, storeId);
        if (!fs.existsSync(filePath)) {
          throw new Error(
            `Missing golden screenshot for store="${storeId}" lang="${lang}":\n  ${filePath}\nRun: flutter test --update-goldens test/screenshots/`,
          );
        }
      }
    }
  }
}

/**
 * Renders a full-width panorama (all screens side-by-side) at the store's
 * native resolution and injects the store's CSS variables so layout is exact.
 */
async function renderPanorama(lang, storeId) {
  const store = STORE_SIZES[storeId];
  const { width: W, height: H } = store;
  const browser = await chromium.launch();

  try {
    const page = await browser.newPage({
      viewport: { width: W * NUM_SCREENS, height: H },
      deviceScaleFactor: 1,
    });

    await page.setContent(fs.readFileSync(TEMPLATE_PATH, 'utf-8'), {
      waitUntil: 'networkidle',
    });

    // Inject store-specific CSS variables so the template layout matches the
    // target resolution exactly (template.html has fallback defaults).
    await page.addStyleTag({
      content: `:root { --screen-w: ${W}px; --screen-h: ${H}px; }`,
    });

    const imageMap = {};
    for (const screen of SCREENS) {
      imageMap[screen.id] = toDataUri(screenshotPathFor(screen, lang, storeId));
    }

    await page.evaluate(
      ({ screens, locale, imageData }) => {
        screens.forEach((screen, index) => {
          const screenNode = document.getElementById(`screen-${index}`);
          const category = document.getElementById(`cat-${index}`);
          const headline = document.getElementById(`hl-${index}`);
          const subtitle = document.getElementById(`sub-${index}`);
          const screenshot = document.getElementById(`ss-${index}`);

          if (screenNode) {
            screenNode.className = `screen ${screen.theme === 'light' ? 'bg-light' : 'bg-dark'}`;
          }

          if (category) {
            category.textContent = screen.category[locale];
          }

          if (headline) {
            headline.innerHTML = screen.headline[locale].replace(/\n/g, '<br>');
          }

          if (subtitle) {
            subtitle.textContent = screen.subtitle[locale];
          }

          if (screenshot) {
            screenshot.src = imageData[screen.id];
          }
        });
      },
      { screens: SCREENS, locale: lang, imageData: imageMap },
    );

    await page.waitForFunction(
      () => {
        const images = document.querySelectorAll('img[src]');
        return Array.from(images).every((img) => img.complete && img.naturalWidth > 0);
      },
      { timeout: 10000 },
    );

    await page.waitForTimeout(500);

    const panoramaDir = path.join(OUTPUT, 'panorama');
    ensureDir(panoramaDir);
    const panoramaPath = path.join(panoramaDir, `panorama-${storeId}-${lang}.png`);

    await page.screenshot({ path: panoramaPath, type: 'png' });
    console.log(
      `  📸 Panorama [${storeId}/${lang}]: ${W * NUM_SCREENS}×${H}`,
    );

    return panoramaPath;
  } finally {
    await browser.close();
  }
}

/**
 * Slices the panorama into individual per-screen images.
 *
 * Since each panorama is already rendered at the store's native resolution,
 * no resize is needed — each slice is exactly `W × H`.
 */
async function sliceForStore(panoramaPath, lang, storeId) {
  const store = STORE_SIZES[storeId];
  const { width: W, height: H } = store;
  const outputDir = path.join(OUTPUT, lang, storeId);
  cleanDir(outputDir);

  const storeFiles = [];
  for (let index = 0; index < NUM_SCREENS; index += 1) {
    const number = String(index + 1).padStart(2, '0');
    const outputPath = path.join(outputDir, `${number}_${SCREENS[index].id}.png`);

    await sharp(panoramaPath)
      .extract({ left: index * W, top: 0, width: W, height: H })
      .png()
      .toFile(outputPath);

    console.log(`  🖼️  [${storeId}] ${path.basename(outputPath)} (${W}×${H})`);
    storeFiles.push(outputPath);
  }

  return storeFiles;
}

function copyUiScreensToWebsite(lang) {
  const langDir = path.join(WEBSITE_UI_SCREENSHOTS, lang);
  cleanDir(langDir);

  // Use the first enabled store (microsoft = Windows) for the website UI shots.
  const primaryStore = ENABLED_STORES[0];
  for (const screen of SCREENS) {
    const sourcePath = screenshotPathFor(screen, lang, primaryStore);
    const fileName = path.basename(sourcePath);
    fs.copyFileSync(sourcePath, path.join(langDir, fileName));
  }

  console.log(`📋 Copied ${SCREENS.length} raw UI screenshots → website/public/screenshots/ui/${lang}/`);
}

function copyStoreScreensToWebsite(lang, files) {
  const langDir = path.join(WEBSITE_STORE_SCREENSHOTS, lang);
  cleanDir(langDir);

  for (const filePath of files) {
    fs.copyFileSync(filePath, path.join(langDir, path.basename(filePath)));
  }

  console.log(`📋 Copied ${files.length} store screenshots → website/public/screenshots/store/${lang}/`);
}

async function generateForStore(storeId, lang, copyWebsite) {
  const panoramaPath = await renderPanorama(lang, storeId);
  const files = await sliceForStore(panoramaPath, lang, storeId);

  // Copy only the primary store's screenshots to the website.
  if (copyWebsite && storeId === ENABLED_STORES[0]) {
    copyStoreScreensToWebsite(lang, files);
    copyUiScreensToWebsite(lang);
  }

  return files;
}

async function main() {
  const args = process.argv.slice(2);
  const langArg = args.find((arg) => arg.startsWith('--lang='))?.split('=')[1] || 'all';
  const langs = langArg === 'all' ? ['en', 'de'] : [langArg];
  const copyWebsite = !args.includes('--no-website');

  verifySourceImages();
  ensureDir(OUTPUT);
  cleanDir(path.join(OUTPUT, 'panorama'));

  if (copyWebsite) {
    ensureDir(WEBSITE_SCREENSHOTS_ROOT);
    ensureDir(WEBSITE_STORE_SCREENSHOTS);
    ensureDir(WEBSITE_UI_SCREENSHOTS);
    removeRootPngs(WEBSITE_SCREENSHOTS_ROOT);
  }

  console.log('🚀 WhisPaste Store Screenshot Generator');
  console.log(`   Screens: ${NUM_SCREENS}`);
  console.log(`   Languages: ${langs.join(', ')}`);
  console.log(`   Stores: ${ENABLED_STORES.map((id) => `${STORE_SIZES[id].label} (${STORE_SIZES[id].width}×${STORE_SIZES[id].height})`).join(', ')}`);

  if (FUTURE_STORES.length > 0) {
    const stores = FUTURE_STORES
      .map((storeId) => {
        const store = STORE_SIZES[storeId];
        return `${store.label} (${store.width}×${store.height})`;
      })
      .join(', ');
    console.log(`   Future-ready sizes: ${stores}`);
  }

  for (const lang of langs) {
    console.log(`\n🎨 Generating ${lang.toUpperCase()} screenshots...`);
    for (const storeId of ENABLED_STORES) {
      await generateForStore(storeId, lang, copyWebsite);
    }
    console.log(`✅ ${lang.toUpperCase()} done`);
  }

  console.log('\n🎉 All done!');
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});
