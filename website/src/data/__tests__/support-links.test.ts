import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  BUY_ME_A_COFFEE_URL,
  GITHUB_SPONSORS_URL,
  KOFI_URL,
  PAYPAL_URL,
  SUPPORT_PROVIDERS,
} from '../support-links';

// Drift guard (#398): the support provider URLs exist in the app, on the
// website, in FUNDING.yml and in README.md. The app constants cannot import the website
// module, so this test reads them and fails on any difference.
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');
const read = (path: string) => readFileSync(join(repoRoot, path), 'utf8');

function dartConst(source: string, name: string): string {
  const match = source.match(new RegExp(`const String ${name}\\s*=\\s*'([^']+)';`));
  if (!match) throw new Error(`${name} not found in lib/core/app_urls.dart`);
  return match[1];
}

function svgPath(svg: string): string {
  const match = svg.match(/\sd="([^"]+)"/);
  if (!match) throw new Error('no path in svg');
  return match[1];
}

describe('support links', () => {
  const appUrls = read('lib/core/app_urls.dart');

  it('match the app constants in lib/core/app_urls.dart', () => {
    expect(PAYPAL_URL).toBe(dartConst(appUrls, 'kPayPalUrl'));
    expect(KOFI_URL).toBe(dartConst(appUrls, 'kKofiUrl'));
    expect(BUY_ME_A_COFFEE_URL).toBe(dartConst(appUrls, 'kBuyMeACoffeeUrl'));
    expect(GITHUB_SPONSORS_URL).toBe(dartConst(appUrls, 'kGitHubSponsorsUrl'));
  });

  it('match .github/FUNDING.yml', () => {
    const funding = read('.github/FUNDING.yml');
    const user = (key: string) => funding.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'))?.[1].trim();
    expect(user('github')).toBe(`[${GITHUB_SPONSORS_URL.split('/').pop()}]`);
    expect(user('ko_fi')).toBe(KOFI_URL.split('/').pop());
    expect(user('buy_me_a_coffee')).toBe(BUY_ME_A_COFFEE_URL.split('/').pop());
    expect(user('custom')).toBe(`["${PAYPAL_URL}"]`);
  });

  it('match the README support section: every provider, guide order, no hotlinked badges', () => {
    const readme = read('README.md');
    const start = readme.indexOf('## Support');
    expect(start, 'README.md has no "## Support" section').toBeGreaterThanOrEqual(0);
    const next = readme.indexOf('\n## ', start + 1);
    const section = readme.slice(start, next === -1 ? undefined : next);
    // Markdown links since the calmer README (#1799); HTML anchors still count.
    const links = [...section.matchAll(/<a href="([^"]+)">([^<]+)<\/a>|\[([^\]]+)\]\((https:[^)\s]+)\)/g)]
      .map(([, aHref, aName, mdName, mdHref]) => ({ href: aHref ?? mdHref, name: aName ?? mdName }))
      .filter(({ href }) => SUPPORT_PROVIDERS.some((p) => p.href === href));
    expect(links).toEqual(SUPPORT_PROVIDERS.map((p) => ({ href: p.href, name: p.name })));
    expect(section).not.toMatch(/<img[^>]+src="https?:\/\//);
  });

  it('list each provider once with an https URL', () => {
    expect(SUPPORT_PROVIDERS.map((p) => p.id)).toEqual(['paypal', 'kofi', 'buymeacoffee', 'github']);
    for (const provider of SUPPORT_PROVIDERS) expect(provider.href).toMatch(/^https:\/\//);
  });

  it('use the same logo paths as the app assets', () => {
    for (const provider of SUPPORT_PROVIDERS) {
      const site = read(`website/src/assets/support/${provider.logo}.svg`);
      const app = read(`assets/social/${provider.logo}-logo.svg`);
      expect(svgPath(site), provider.logo).toBe(svgPath(app));
      expect(site).toContain('fill="currentColor"');
    }
  });
});
