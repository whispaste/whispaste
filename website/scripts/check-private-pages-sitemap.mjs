#!/usr/bin/env node
// Build check: the token-bearing newsletter link pages must never appear in the
// sitemap (and must still exist in dist, so a rename cannot silently void it).
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
const files = readdirSync(dist).filter((f) => /^sitemap.*\.xml$/.test(f));
if (files.length === 0) {
  console.error('check-private-pages-sitemap: no sitemap in dist/ (run the build first)');
  process.exit(1);
}
if (!existsSync(join(dist, 'newsletter', 'confirm', 'index.html'))) {
  console.error('check-private-pages-sitemap: newsletter/confirm page missing from dist/');
  process.exit(1);
}
const leaks = [];
for (const f of files) {
  for (const m of readFileSync(join(dist, f), 'utf8').matchAll(/<loc>([^<]*\/newsletter\/(?:confirm|unsubscribe|device)\/?)<\/loc>/g)) {
    leaks.push(`${f}: ${m[1]}`);
  }
}
if (leaks.length > 0) {
  console.error(`check-private-pages-sitemap: private pages in the sitemap:\n${leaks.join('\n')}`);
  process.exit(1);
}
console.log('check-private-pages-sitemap: ok');
