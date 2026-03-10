/**
 * Screenshot tool for WhisPaste landing page.
 * Captures the AppPreviewMockup section at 2x resolution.
 *
 * Usage: npm run screenshot (from website/ directory)
 * Requires: Astro dev server running on localhost:4321
 */

import { chromium } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUTPUT_DIR = path.join(__dirname, '..', 'website', 'public', 'screenshots');

const SCREENSHOTS = [
  {
    name: 'app-preview',
    selector: '.mockup-nb-container',
    padding: 40,
    viewport: { width: 1440, height: 900 },
  },
  {
    name: 'app-preview-mobile',
    selector: '.mockup-nb-container',
    padding: 20,
    viewport: { width: 375, height: 812 },
  },
];

async function captureScreenshots() {
  const baseURL = process.argv[2] || 'http://localhost:4321';

  console.log(`📸 WhisPaste Screenshot Tool`);
  console.log(`   Base URL: ${baseURL}`);
  console.log(`   Output:   ${OUTPUT_DIR}\n`);

  const browser = await chromium.launch();

  for (const shot of SCREENSHOTS) {
    console.log(`⏳ Capturing ${shot.name} (${shot.viewport.width}x${shot.viewport.height})...`);

    const context = await browser.newContext({
      viewport: shot.viewport,
      deviceScaleFactor: 2,
      colorScheme: 'dark',
    });
    const page = await context.newPage();

    await page.goto(baseURL, { waitUntil: 'networkidle' });

    // Scroll to the app preview section
    await page.evaluate(() => {
      const el = document.getElementById('app-preview');
      if (el) el.scrollIntoView({ behavior: 'instant', block: 'center' });
    });
    await page.waitForTimeout(500);

    const element = await page.$(shot.selector);
    if (!element) {
      console.log(`   ⚠️  Selector "${shot.selector}" not found, skipping.`);
      await context.close();
      continue;
    }

    const outPath = path.join(OUTPUT_DIR, `${shot.name}.png`);
    await element.screenshot({
      path: outPath,
      type: 'png',
    });

    console.log(`   ✅ Saved: ${shot.name}.png`);
    await context.close();
  }

  await browser.close();
  console.log('\n🎉 All screenshots captured!');
}

captureScreenshots().catch((err) => {
  console.error('❌ Screenshot failed:', err.message);
  console.error('   Make sure the Astro dev server is running: npm run dev');
  process.exit(1);
});
