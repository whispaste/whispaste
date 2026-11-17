#!/usr/bin/env node
// Build check (#1774): every built legal page (imprint, privacy policy) must
// name the provider in full. The public site is built from the exported mirror,
// and the export once rewrote the GbR name to "org …" without anyone noticing.
// Running after `astro build` makes both the export's build check and the
// Pages deploy fail instead of publishing a wrong imprint (§ 5 DDG).
//
// The expected name is assembled from its parts here as well, on its own, so
// this check neither depends on src/legal/entity.ts nor gets rewritten by the
// same export rule it guards against.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const EXPECTED_PROVIDER_NAME = `${[['Silvio', 'Lindstedt'], ['Maik', 'Gräfendorf']]
  .map((p) => p.join(' '))
  .join(' und ')}, GbR`;

/** Legal pages that must exist in dist, relative to dist. */
export const LEGAL_PAGES = [
  'impressum',
  'datenschutz',
  'en/impressum',
  'en/privacy',
  ...['es', 'pt', 'it', 'ru', 'zh', 'fr'].map((lang) => `${lang}/privacy`),
];

/** Returns one message per missing page or page without the full provider name. */
export function checkLegalEntity(dist, pages = LEGAL_PAGES, expected = EXPECTED_PROVIDER_NAME) {
  const problems = [];
  for (const page of pages) {
    const file = join(dist, page, 'index.html');
    if (!existsSync(file)) {
      problems.push(`${page}: page missing from dist/`);
      continue;
    }
    if (!readFileSync(file, 'utf8').includes(expected)) {
      problems.push(`${page}: provider name "${expected}" not found`);
    }
  }
  return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dist = fileURLToPath(new URL('../dist/', import.meta.url));
  const problems = checkLegalEntity(dist);
  if (problems.length > 0) {
    console.error(`check-legal-entity: legal pages without the full provider name:\n${problems.join('\n')}`);
    process.exit(1);
  }
  console.log(`check-legal-entity: ok (${LEGAL_PAGES.length} pages)`);
}
