const path = require('path');
const fs = require('fs');

const { chromium } = require('playwright');
const { ROOT, ASSET_PATHS, GOLDENS } = require('./config');

const TEMPLATE_PATH = path.join(__dirname, 'og-template.html');
const OUTPUT_DIR = path.join(__dirname, 'output', 'og');
const WEBSITE_PUBLIC = path.join(ROOT, 'website', 'public');

const FEATURE_FILES = {
  en: [
    'en/dark/01_workspace_overview.png',
    'en/light/02_workspace_detail.png',
    'en/dark/03_voice_shortcuts.png',
  ],
  de: [
    'de/dark/01_workspace_overview.png',
    'de/light/02_workspace_detail.png',
    'de/dark/03_voice_shortcuts.png',
  ],
};

const OG_CONTENT = {
  en: {
    eyebrow: 'DESKTOP DICTATION',
    headline: 'Speak once.\n<em>Use it anywhere.</em>',
    subtitle:
      'WhisPaste turns short dictation into ready-to-paste text with a desktop workflow that stays private and organized.',
    badges: ['100% Offline', 'Open Source', 'Windows · macOS'],
    trustNote: 'Private by default. Cloud only when you choose it.',
  },
  de: {
    eyebrow: 'DESKTOP-DIKTAT',
    headline: 'Einmal sprechen.\n<em>Überall nutzen.</em>',
    subtitle:
      'WhisPaste macht aus kurzen Diktaten direkt nutzbaren Text — mit einem Desktop-Workflow, der privat und aufgeräumt bleibt.',
    badges: ['100% Offline', 'Open Source', 'Windows · macOS'],
    trustNote: 'Standardmäßig privat. Cloud nur, wenn du sie auswählst.',
  },
};

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function toDataUri(filePath) {
  const buffer = fs.readFileSync(filePath);
  return `data:image/png;base64,${buffer.toString('base64')}`;
}

function resolveScreenshot(lang, relPath) {
  const candidate = path.join(GOLDENS, relPath);
  if (fs.existsSync(candidate)) return candidate;
  throw new Error(
    `Missing screenshot for OG image: ${candidate}\n` +
    `Run: flutter test --update-goldens test/screenshots/ && python3 scripts/generate-screenshots.py --no-composites`,
  );
}

async function generateOgImage(lang) {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 1200, height: 630 },
      deviceScaleFactor: 1,
    });

    await page.setContent(fs.readFileSync(TEMPLATE_PATH, 'utf-8'), {
      waitUntil: 'networkidle',
    });

    const content = OG_CONTENT[lang];
    const cards = FEATURE_FILES[lang].map((relPath) =>
      toDataUri(resolveScreenshot(lang, relPath)),
    );

    await page.evaluate(
      ({ logo, content: injected, cards }) => {
        const logoNode = document.getElementById('logo');
        if (logoNode) logoNode.src = logo;

        const eyebrow = document.getElementById('eyebrow');
        if (eyebrow) eyebrow.textContent = injected.eyebrow;

        const headline = document.getElementById('headline');
        if (headline) headline.innerHTML = injected.headline.replace(/\n/g, '<br>');

        const subtitle = document.getElementById('subtitle');
        if (subtitle) subtitle.textContent = injected.subtitle;

        const badges = document.getElementById('badges');
        if (badges) {
          badges.innerHTML = injected.badges
            .map((badge) => `<div class="badge">${badge}</div>`)
            .join('');
        }

        const trustNote = document.getElementById('trust-note');
        if (trustNote) trustNote.textContent = injected.trustNote;

        cards.forEach((card, index) => {
          const img = document.getElementById(`card-${index + 1}`);
          if (img) img.src = card;
        });
      },
      { logo: toDataUri(ASSET_PATHS.logo), content, cards },
    );

    await page.waitForFunction(
      () => {
        const images = document.querySelectorAll('img[src]');
        return Array.from(images).every((img) => img.complete && img.naturalWidth > 0);
      },
      { timeout: 10000 },
    );
    await page.waitForTimeout(300);

    ensureDir(OUTPUT_DIR);
    const outputPath = path.join(OUTPUT_DIR, `og-image-${lang}.png`);
    await page.screenshot({ path: outputPath, type: 'png' });

    const websiteTarget =
      lang === 'en'
        ? path.join(WEBSITE_PUBLIC, 'og-image.png')
        : path.join(WEBSITE_PUBLIC, `og-image-${lang}.png`);
    fs.copyFileSync(outputPath, websiteTarget);

    console.log(`🖼️  og-image-${lang}.png (1200×630)`);
    console.log(`📋 Copied to ${path.relative(ROOT, websiteTarget)}`);
  } finally {
    await browser.close();
  }
}

async function main() {
  const args = process.argv.slice(2);
  const langArg = args.find((arg) => arg.startsWith('--lang='))?.split('=')[1] || 'all';
  const langs = langArg === 'all' ? ['en', 'de'] : [langArg];

  console.log('🚀 WhisPaste OG Image Generator');
  console.log(`   Languages: ${langs.join(', ')}`);

  for (const lang of langs) {
    await generateOgImage(lang);
  }

  console.log('🎉 OG images ready');
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});
