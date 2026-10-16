// Lists every colour written as a literal instead of a design token in the
// website source. Used by the design-system guard test and runnable by hand:
//   node scripts/color-literals.mjs            -> report per file
//   node scripts/color-literals.mjs --verbose  -> every hit with line
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const SRC = join(ROOT, 'src');

/**
 * Files that may hold literal colours: the token output itself, and files
 * that only render real app/OS pixels. Inside any other file, a mock-up of
 * the dark-only desktop app (menu bar, app window, recording pill) is fenced
 * with the comments `mockup-colours:start` / `mockup-colours:end`; the site
 * UI around it (tabs, captions, buttons) still has to use tokens.
 */
export const ALLOWED = new Map([
  ['src/styles/tokens.css', 'generated token output'],
  ['src/scripts/overlay-mockup.ts', 'draws the app overlay pill, app pixels only'],
  ['src/components/ScreenshotLightbox.astro', 'full-screen photo viewer, always black'],
]);

const PATTERNS = [
  ['hex', /#[0-9a-fA-F]{3,8}\b/g],
  ['rgb/hsl', /\b(?:rgba?|hsla?)\(\s*\d/g],
  ['tw-colour', /\b(?:text|bg|border|ring|fill|stroke|from|to|via|outline|divide|placeholder|decoration|shadow)-(?:white|black|(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d{2,3})\b/g],
  ['named', /(?:color|background|fill|stroke|border(?:-[a-z]+)?)\s*:\s*(?:white|black)\b/g],
  ['svg-attr', /\b(?:fill|stroke|stop-color)="(?:white|black|#[0-9a-fA-F]{3,8})"/g],
];

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path, out);
    else if (/\.(astro|css|ts|tsx|mjs)$/.test(name) && !/\.test\.ts$/.test(name)) out.push(path);
  }
  return out;
}

/** Strips comments so documentation that mentions a hex value does not count. */
function code(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:"'])\/\/[^\n]*/g, (m, p) => p + ' '.repeat(m.length - p.length));
}

export function findLiterals() {
  const hits = [];
  for (const file of walk(SRC)) {
    const rel = relative(ROOT, file);
    if (ALLOWED.has(rel) || rel.includes('/design-system/')) continue;
    const raw = readFileSync(file, 'utf8').split('\n');
    const lines = code(raw.join('\n')).split('\n');
    let fenced = false;
    lines.forEach((line, i) => {
      if (raw[i].includes('mockup-colours:start')) fenced = true;
      if (raw[i].includes('mockup-colours:end')) fenced = false;
      if (fenced) return;
      // The browser reads theme-color before any CSS loads, so it cannot be a var().
      if (/name="theme-color"/.test(line)) return;
      for (const [kind, re] of PATTERNS) {
        for (const m of line.matchAll(re)) {
          // `#main-content`-style ids and entity refs are not colours.
          if (kind === 'hex' && !/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(m[0])) continue;
          if (kind === 'hex' && /&#|href="#|id="#|url\(#/.test(line.slice(Math.max(0, m.index - 6), m.index + 1))) continue;
          hits.push({ file: rel, line: i + 1, kind, text: m[0] });
        }
      }
    });
  }
  return hits;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const hits = findLiterals();
  const byFile = new Map();
  for (const h of hits) byFile.set(h.file, [...(byFile.get(h.file) ?? []), h]);
  const sorted = [...byFile].sort((a, b) => b[1].length - a[1].length);
  for (const [file, list] of sorted) {
    console.log(`${String(list.length).padStart(4)}  ${file}`);
    if (process.argv.includes('--verbose')) for (const h of list) console.log(`        ${h.line}: ${h.kind} ${h.text}`);
  }
  console.log(`${hits.length} literal colours in ${byFile.size} files`);
}
