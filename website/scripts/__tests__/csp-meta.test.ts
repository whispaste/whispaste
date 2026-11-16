import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { forbiddenInline, inlineScripts, policyFor, withCspMeta } from '../csp-meta.mjs';

const hashOf = (s: string) => `'sha256-${createHash('sha256').update(s, 'utf8').digest('base64')}'`;

const PAGE = [
  '<!doctype html><html><head><meta charset="UTF-8"><title>x</title>',
  '<script>var a = 1;</script>',
  '<script type="application/ld+json">{"@type":"Thing"}</script>',
  '<script type="module" src="/_astro/a.js"></script>',
  '<script type="module">import "/b.js";</script>',
  '</head><body><p>hi</p></body></html>',
].join('');

describe('csp-meta (#1629)', () => {
  it('hashes only inline scripts the browser executes', () => {
    expect(inlineScripts(PAGE)).toEqual(['var a = 1;', 'import "/b.js";']);
    const policy = policyFor(PAGE);
    expect(policy).toContain(hashOf('var a = 1;'));
    expect(policy).toContain(hashOf('import "/b.js";'));
    expect(policy).not.toContain(hashOf('{"@type":"Thing"}'));
    expect(policy).not.toContain('unsafe-inline\' https'); // never on script-src
    expect(policy).toMatch(/script-src 'self' 'sha256-/);
  });

  it('puts exactly one meta directly after <meta charset>, before every script', () => {
    const once = withCspMeta(PAGE);
    expect(once.indexOf('<meta charset="UTF-8"><meta http-equiv="content-security-policy"')).toBeGreaterThan(0);
    expect(once.indexOf('content-security-policy')).toBeLessThan(once.indexOf('<script'));
    const twice = withCspMeta(once);
    expect(twice.match(/content-security-policy/g)).toHaveLength(1);
    expect(twice).toBe(once);
  });

  it('lists Matomo only where it loads, and nothing external on private pages', () => {
    const withMatomo = PAGE.replace('</head>', '<script>var u = "https://matomo.silvio-und-maik.de/matomo.js";</script></head>');
    expect(policyFor(PAGE)).not.toContain('matomo');
    expect(policyFor(PAGE)).toContain('ingest.de.sentry.io');
    expect(policyFor(withMatomo)).toMatch(/connect-src [^;]*matomo/);
    expect(policyFor(withMatomo)).toMatch(/script-src 'self' https:\/\/matomo\.silvio-und-maik\.de 'sha256-/);
    const privatePage = withMatomo.replace('<title>', '<meta name="referrer" content="no-referrer"><title>');
    expect(policyFor(privatePage)).not.toMatch(/matomo|sentry/);
  });

  it('flags inline handlers and javascript: URLs, but not script text', () => {
    expect(forbiddenInline(PAGE)).toEqual([]);
    expect(forbiddenInline('<a href="/x" onclick="go()">x</a>')).toEqual(['inline handler onclick']);
    expect(forbiddenInline('<a href="javascript:void(0)">x</a>')).toHaveLength(1);
    expect(forbiddenInline('<script>el.innerHTML = \'<b onclick="x()">\';</script>')).toEqual([]);
    expect(forbiddenInline('<p>turn on="it"</p>')).toEqual([]);
  });
});
