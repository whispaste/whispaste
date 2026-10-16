// Design-system lint for the website source. Finds values that bypass the
// token scales (see design-tokens/README.md, "Checks"):
//   radius      border-radius written as a length instead of a --wp-radius token
//   font-size   font-size written as a length instead of a --wp-font-size/type token
//   spacing     padding/margin/gap lengths off the 4px grid (em and position offsets
//               are geometry, not rhythm, and stay free)
//   duration    transition durations written as ms/s instead of a --wp-duration token
//   tw-arbitrary Tailwind arbitrary lengths such as p-[13px] or text-[15px]
// Colours have their own check in color-literals.mjs.
//   node scripts/design-lint.mjs [--verbose] [rule]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const SRC = join(ROOT, 'src');
const SKIP = new Set(['src/styles/tokens.css']);

const LENGTH = /(-?\d*\.?\d+)(px|rem)\b/g;

/** True when a length sits on the 4px grid (rem/em assume 16px). 1px and 2px hairlines pass. */
function onGrid(value, unit) {
  const px = unit === 'px' ? value : value * 16;
  return Math.abs(px) <= 2 || Math.abs(px % 4) < 0.01 || Math.abs((px % 4) - 4) < 0.01;
}

const RULES = [
  {
    id: 'radius',
    // 1px/2px radii round off hairline bars and pass.
    test: (prop, value) => /^border(?:-[a-z]+)*-radius$/.test(prop) && [...value.matchAll(LENGTH)].some(([, v, u]) => (u === 'px' ? +v : v * 16) > 2) && !/var\(/.test(value),
  },
  {
    id: 'font-size',
    test: (prop, value) => prop === 'font-size' && /\d(?:px|rem)/.test(value) && !/var\(/.test(value),
  },
  {
    id: 'spacing',
    test: (prop, value) => {
      if (!/^(?:padding|margin|gap|row-gap|column-gap)(?:-[a-z]+)*$/.test(prop)) return false;
      if (/var\(/.test(value) && !/\d(?:px|rem)/.test(value.replace(/var\([^)]*\)/g, ''))) return false;
      return [...value.replace(/var\([^)]*\)/g, '').replace(/\d*\.?\d+vw/g, '').matchAll(LENGTH)].some(([, v, u]) => !onGrid(Number(v), u));
    },
  },
  {
    id: 'duration',
    test: (prop, value) => /^transition(?:-duration)?$/.test(prop) && /\d(?:ms|s)\b/.test(value),
  },
];

const TW_ARBITRARY = /\b(?:p|px|py|pt|pr|pb|pl|m|mx|my|mt|mr|mb|ml|gap|gap-x|gap-y|space-x|space-y|rounded(?:-[a-z]+)?|text|leading|tracking)-\[(-?\d*\.?\d+(?:px|rem))\]/g;

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path, out);
    else if (/\.(astro|css)$/.test(name)) out.push(path);
  }
  return out;
}

export function lint() {
  const hits = [];
  for (const file of walk(SRC)) {
    const rel = relative(ROOT, file);
    if (SKIP.has(rel) || rel.includes('/design-system/')) continue;
    const text = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
    const isCss = file.endsWith('.css');
    let inStyle = isCss;
    text.split('\n').forEach((line, i) => {
      if (!isCss && /<style\b/.test(line)) inStyle = true;
      if (!isCss && /<\/style>/.test(line)) inStyle = false;
      if (!line.includes('mockup-colours')) {
        for (const m of line.matchAll(TW_ARBITRARY)) hits.push({ file: rel, line: i + 1, rule: 'tw-arbitrary', text: m[0] });
      }
      if (!inStyle) return;
      const decl = line.match(/^\s*([a-z-]+)\s*:\s*([^;{]+);?\s*$/);
      if (!decl || decl[1].startsWith('--')) return;
      const [, prop, value] = decl;
      for (const rule of RULES) {
        LENGTH.lastIndex = 0;
        if (rule.test(prop, value)) hits.push({ file: rel, line: i + 1, rule: rule.id, text: `${prop}: ${value.trim()}` });
      }
    });
  }
  return hits;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const only = process.argv.slice(2).find((a) => !a.startsWith('--'));
  const hits = lint().filter((h) => !only || h.rule === only);
  const byRule = new Map();
  for (const h of hits) byRule.set(h.rule, (byRule.get(h.rule) ?? 0) + 1);
  if (process.argv.includes('--verbose')) for (const h of hits) console.log(`${h.file}:${h.line}  ${h.rule}  ${h.text}`);
  const byFile = new Map();
  for (const h of hits) byFile.set(h.file, (byFile.get(h.file) ?? 0) + 1);
  console.log([...byFile].sort((a, b) => b[1] - a[1]).slice(0, 25).map(([f, n]) => `${String(n).padStart(4)}  ${f}`).join('\n'));
  console.log([...byRule].map(([r, n]) => `${r}: ${n}`).join(' · '), `· total ${hits.length}`);
}
