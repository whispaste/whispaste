// Content-Security-Policy als <meta http-equiv> für jede gebaute Seite (#1629).
//
// GitHub Pages erlaubt keine eigenen HTTP-Header, darum steht die Policy im
// HTML. Diese Datei schreibt sie nach dem Build (Astro-Hook
// `astro:build:done`, eingebunden in astro.config.mjs) in jede Seite unter
// `dist/`:
//   - direkt hinter <meta charset>, damit sie auch die Inline-Skripte im
//     <head> erfasst (eine Meta-CSP gilt erst ab ihrer Position),
//   - mit dem SHA-256-Hash jedes Inline-Skripts genau dieser Seite (auch
//     `is:inline`, das Astros eigenes `security.csp` nicht hasht),
//   - und sie bricht den Build ab, wenn eine Seite Inline-Event-Handler
//     (`onclick=` …) oder `javascript:`-Links enthält, die die Policy
//     ohnehin blocken würde.
//
// Erlaubt ist genau, was die gebaute Seite lädt (Stand Build-Analyse
// 2026-11-16):
//   - Skripte: eigene Bundles, Matomo (matomo.js, Opt-out auf der
//     Datenschutzseite), die gehashten Inline-Skripte,
//   - Verbindungen: eigene API (Sterne, Kontakt, Newsletter), GitHub-
//     Releases-API (Changelog), Matomo-Tracking, Sentry-EU-Ingest,
//   - Matomo nur auf Seiten, die es laden; private Seiten (Newsletter-
//     Links, `no-referrer`) ohne Matomo und ohne Sentry-Ingest,
//   - Bilder: eigene Domain, data: (Inline-SVG in CSS), Matomo-Pixel,
//   - Schriften und Videos nur von der eigenen Domain,
//   - Formular-Ziel: Google Übersetzer (Blog-Übersetzungsformular).
// style-src braucht 'unsafe-inline' für style-Attribute (Komponenten,
// Matomo-Opt-out, Code-Hervorhebung im Blog).
//
// Was nur als HTTP-Header wirkt (HSTS, frame-ancestors, report-uri,
// X-Content-Type-Options), lässt sich hier nicht setzen; dafür braucht es
// anderes Hosting oder ein CDN davor (internal-notes, Website-Sicherheitsköpfe).
// Im Dev-Server gibt es keine CSP (Vite-HMR arbeitet mit Inline-Code).

import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const MATOMO = 'https://matomo.silvio-und-maik.de';
const SENTRY_INGEST = 'https://o4511065943441408.ingest.de.sentry.io';

/**
 * Directives except script-src, which carries the per-page hashes.
 * Matomo is listed only on pages that load it; private pages (secret in the
 * address, `<meta name="referrer" content="no-referrer">`) get neither
 * Matomo nor the Sentry ingest, so not even a bug could send data from them.
 */
export function baseDirectives({ matomo, sentry }) {
  const m = matomo ? ` ${MATOMO}` : '';
  const s = sentry ? ` ${SENTRY_INGEST}` : '';
  return [
    "default-src 'self'",
    `connect-src 'self' https://api.whispaste.de https://api.github.com${m}${s}`,
    `img-src 'self' data:${m}`,
    "font-src 'self'",
    "media-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self' https://translate.google.com",
    "frame-src 'none'",
    "worker-src 'none'",
    "manifest-src 'self'",
    'upgrade-insecure-requests',
  ];
}

const PRIVATE_RE = /<meta\s+name\s*=\s*["']referrer["']\s+content\s*=\s*["']no-referrer["']/i;

const SCRIPT_RE = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
const EXECUTABLE_TYPES = new Set(['', 'text/javascript', 'application/javascript', 'module']);

function scriptType(attrs) {
  const m = /\btype\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(attrs);
  return (m ? (m[1] ?? m[2] ?? m[3]) : '').trim().toLowerCase();
}

/** Bodies of all inline scripts the browser would execute (no src, JS type). */
export function inlineScripts(html) {
  const bodies = [];
  for (const m of html.matchAll(SCRIPT_RE)) {
    const attrs = m[1];
    if (/\bsrc\s*=/i.test(attrs)) continue;
    if (!EXECUTABLE_TYPES.has(scriptType(attrs))) continue;
    bodies.push(m[2]);
  }
  return bodies;
}

export function sha256(text) {
  return `'sha256-${createHash('sha256').update(text, 'utf8').digest('base64')}'`;
}

/** The full policy for one page (`html` without a CSP meta). */
export function policyFor(html) {
  const isPrivate = PRIVATE_RE.test(html);
  const matomo = !isPrivate && html.includes(MATOMO);
  const hashes = [...new Set(inlineScripts(html).map(sha256))];
  const scriptSrc = ["'self'", ...(matomo ? [MATOMO] : []), ...hashes];
  return [...baseDirectives({ matomo, sentry: !isPrivate }), `script-src ${scriptSrc.join(' ')}`].join('; ');
}

/** Things the policy would block silently; the build fails on them instead. */
export function forbiddenInline(html) {
  // Script bodies may contain anything (strings, regexes); only markup counts.
  const markup = html.replace(SCRIPT_RE, '<script></script>');
  const found = [];
  for (const m of markup.matchAll(/<[a-z][^\s>/]*\s[^>]*?\s(on[a-z]+)\s*=/gi)) found.push(`inline handler ${m[1]}`);
  for (const m of markup.matchAll(/\s(?:href|src|action)\s*=\s*["']?\s*javascript:/gi)) found.push(`javascript: URL (${m[0].trim()})`);
  return found;
}

const CSP_META_RE = /<meta\s+http-equiv\s*=\s*["']content-security-policy["'][^>]*>/gi;

/** Returns the page with exactly one CSP meta directly after <meta charset>. */
export function withCspMeta(html) {
  const clean = html.replace(CSP_META_RE, '');
  const meta = `<meta http-equiv="content-security-policy" content="${policyFor(clean)}">`;
  const charset = /<meta\s+charset\s*=\s*["']?[^"'>\s]+["']?\s*\/?>/i.exec(clean);
  if (charset) {
    const at = charset.index + charset[0].length;
    return clean.slice(0, at) + meta + clean.slice(at);
  }
  const head = /<head\b[^>]*>/i.exec(clean);
  if (!head) throw new Error('no <head> to put the CSP meta into');
  const at = head.index + head[0].length;
  return clean.slice(0, at) + meta + clean.slice(at);
}

async function htmlFiles(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await htmlFiles(path)));
    else if (entry.name.endsWith('.html')) out.push(path);
  }
  return out;
}

/** Astro integration: writes the CSP meta into every built page. */
export function cspMeta() {
  return {
    name: 'wp-csp-meta',
    hooks: {
      'astro:build:done': async ({ dir, logger }) => {
        const root = fileURLToPath(dir);
        const files = await htmlFiles(root);
        const problems = [];
        for (const file of files) {
          const html = await readFile(file, 'utf8');
          for (const p of forbiddenInline(html)) problems.push(`${file.slice(root.length)}: ${p}`);
          await writeFile(file, withCspMeta(html));
        }
        if (problems.length > 0) {
          throw new Error(
            `CSP (#1629): ${problems.length} inline handler(s) or javascript: URL(s) would be blocked; ` +
              `use addEventListener instead.\n${problems.slice(0, 20).join('\n')}`,
          );
        }
        logger.info(`CSP meta written into ${files.length} page(s)`);
      },
    },
  };
}
