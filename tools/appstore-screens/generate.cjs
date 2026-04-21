/**
 * WhisPaste — Store Screenshot Generator
 *
 * Builds the decorated Microsoft Store screenshots from real localized UI
 * screenshots, then copies both store composites and raw UI screens into the
 * website's public assets.
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
const PRIMARY_STORE = ENABLED_STORES[0];
const SCREEN_WIDTH = STORE_SIZES[PRIMARY_STORE].width;
const SCREEN_HEIGHT = STORE_SIZES[PRIMARY_STORE].height;
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

function screenshotPathFor(screen, lang) {
  const screenshotName = screen.screenshot[lang];
  return path.join(GOLDENS, screenshotName);
}

function verifySourceImages() {
  for (const lang of ['en', 'de']) {
    for (const screen of SCREENS) {
      const filePath = screenshotPathFor(screen, lang);
      if (!fs.existsSync(filePath)) {
        throw new Error(
          `Missing golden screenshot: ${filePath}\nRun: flutter test --update-goldens test/screenshots/`,
        );
      }
    }
  }
}

async function renderPanorama(lang) {
  const browser = await chromium.launch();

  try {
    const page = await browser.newPage({
      viewport: { width: SCREEN_WIDTH * NUM_SCREENS, height: SCREEN_HEIGHT },
      deviceScaleFactor: 1,
    });

    await page.setContent(fs.readFileSync(TEMPLATE_PATH, 'utf-8'), {
      waitUntil: 'networkidle',
    });

    const imageMap = {};
    for (const screen of SCREENS) {
      imageMap[screen.id] = toDataUri(screenshotPathFor(screen, lang));
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
    const panoramaPath = path.join(panoramaDir, `panorama-${lang}.png`);

    await page.screenshot({ path: panoramaPath, type: 'png' });
    console.log(
      `  📸 Panorama: panorama-${lang}.png (${SCREEN_WIDTH * NUM_SCREENS}×${SCREEN_HEIGHT})`,
    );

    return panoramaPath;
  } finally {
    await browser.close();
  }
}

async function sliceForStore(panoramaPath, lang, storeId) {
  const store = STORE_SIZES[storeId];
  const outputDir = path.join(OUTPUT, lang, storeId);
  cleanDir(outputDir);

  const storeFiles = [];
  for (let index = 0; index < NUM_SCREENS; index += 1) {
    const number = String(index + 1).padStart(2, '0');
    const outputPath = path.join(outputDir, `${number}_${SCREENS[index].id}.png`);

    let pipeline = sharp(panoramaPath).extract({
      left: index * SCREEN_WIDTH,
      top: 0,
      width: SCREEN_WIDTH,
      height: SCREEN_HEIGHT,
    });

    // Resize when the store requires different dimensions than the base render.
    if (store.width !== SCREEN_WIDTH || store.height !== SCREEN_HEIGHT) {
      pipeline = pipeline.resize(store.width, store.height, { fit: 'cover' });
    }

    await pipeline.png().toFile(outputPath);

    console.log(
      `  🖼️  [${storeId}] ${path.basename(outputPath)} (${store.width}×${store.height})`,
    );
    storeFiles.push(outputPath);
  }

  return storeFiles;
}

function copyUiScreensToWebsite(lang) {
  const langDir = path.join(WEBSITE_UI_SCREENSHOTS, lang);
  cleanDir(langDir);

  for (const screen of SCREENS) {
    const sourcePath = screenshotPathFor(screen, lang);
    const fileName = path.basename(sourcePath);
    fs.copyFileSync(sourcePath, path.join(langDir, fileName));
  }

  console.log(`📋 Copied ${SCREENS.length} raw UI screenshots to website/public/screenshots/ui/${lang}/`);
}

function copyStoreScreensToWebsite(lang, files) {
  const langDir = path.join(WEBSITE_STORE_SCREENSHOTS, lang);
  cleanDir(langDir);

  for (const filePath of files) {
    fs.copyFileSync(filePath, path.join(langDir, path.basename(filePath)));
  }

  console.log(`📋 Copied ${files.length} store screenshots to website/public/screenshots/store/${lang}/`);
}

async function generateScreenshots(lang, copyWebsite) {
  console.log(`\n🎨 Generating ${lang.toUpperCase()} screenshots...`);

  const panoramaPath = await renderPanorama(lang);

  let primaryFiles = [];
  for (const storeId of ENABLED_STORES) {
    const files = await sliceForStore(panoramaPath, lang, storeId);
    if (storeId === PRIMARY_STORE) primaryFiles = files;
  }

  if (copyWebsite) {
    copyStoreScreensToWebsite(lang, primaryFiles);
    copyUiScreensToWebsite(lang);
  }

  console.log(`✅ ${lang.toUpperCase()} done — ${ENABLED_STORES.length} store(s), ${primaryFiles.length} screenshots each`);
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
    await generateScreenshots(lang, copyWebsite);
  }

  console.log('\n🎉 All done!');
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});
