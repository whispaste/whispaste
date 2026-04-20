#!/usr/bin/env node
/**
 * Extracts and filters the cumulative changelog for a minor version series.
 *
 * Usage: node scripts/extract-cumulative-changelog.mjs <version>
 *   e.g.: node scripts/extract-cumulative-changelog.mjs 1.2.2
 *
 * Outputs to stdout the combined, filtered changelog text for ALL X.Y.* patches
 * that belong to the same minor series as the given version. Website, CI/CD, and
 * landing-page changes are removed — app-only content.
 *
 * Used by release.yml to feed content into generate-release-notes.ps1.
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dir, '../');
const changelogMd = resolve(repoRoot, 'CHANGELOG.md');

const versionArg = process.argv[2];
if (!versionArg) {
  process.stderr.write('Usage: node extract-cumulative-changelog.mjs <version>\n');
  process.exit(1);
}

const parts = versionArg.replace(/^v/, '').split('.');
const major = parts[0];
const minor = parts[1];
const minorPrefix = `${major}.${minor}.`;

/**
 * Patterns that identify website/infrastructure lines — these are excluded from
 * user-facing app release notes. Only applied to bullet-point lines.
 */
const EXCLUDE_PATTERNS = [
  /landing.?page/i,
  /landingpage/i,
  /\bwebsite\b/i,
  /\.astro\b/i,
  /\bhero.?(section|button|area|bereich)\b/i,
  /\bdownload.?page\b/i,
  /\bdownload-seite\b/i,
  /apple.?button|store.?button/i,
  /github.?pages|deploy.?pages|pages.?deploy/i,
  /\bplaywright\b/i,
  /\bci[\s/]?cd\b/i,
  /github.?actions?/i,
  /github.?workflow/i,
  /release.?workflow|workflow.?fix/i,
  /sync.?changelog|changelog.?json/i,
  /\bnsis\b|\bmsix\b|\binstaller\b/i,
  /astro.?build|astro.?config/i,
  /golden.?screenshot|screenshot.*golden/i,
  /deploy.*workflow|workflow.*deploy/i,
];

function isWebsiteOrInfra(line) {
  const trimmed = line.trim();
  if (!/^[-*]/.test(trimmed)) return false;
  return EXCLUDE_PATTERNS.some((p) => p.test(trimmed));
}

const content = readFileSync(changelogMd, 'utf8');

// Match all version headers — handle legacy 4-part versions like "1.1.3.0"
const versionRegex = /^## (\d+\.\d+(?:\.\d+)?(?:\.\d+)?)/gm;
const matches = [...content.matchAll(versionRegex)];

/** Normalise version string to X.Y.Z (drop 4th component). */
function normalise(ver) {
  return ver.split('.').slice(0, 3).join('.');
}

// Collect all patches for this minor series
const patches = [];
for (let i = 0; i < matches.length; i++) {
  const normVer = normalise(matches[i][1]);
  if (normVer.startsWith(minorPrefix)) {
    const start = matches[i].index + matches[i][0].length;
    const end = matches[i + 1]?.index ?? content.length;
    patches.push({ version: normVer, body: content.slice(start, end).trim() });
  }
}

if (patches.length === 0) {
  process.stdout.write('No changelog content found.\n');
  process.exit(0);
}

// Sort ascending (oldest patch first) so narrative builds chronologically
patches.sort((a, b) => {
  const ap = parseInt(a.version.split('.')[2] ?? '0');
  const bp = parseInt(b.version.split('.')[2] ?? '0');
  return ap - bp;
});

/**
 * Filter a patch body: remove website/infra bullets, collapse empty section
 * headers (header with zero bullets after filtering becomes invisible).
 */
function filterPatchBody(body) {
  const lines = body.split('\n');
  const sections = [];
  let current = null;

  for (const line of lines) {
    const trimmed = line.trim();
    if (/^###/.test(trimmed)) {
      if (current) sections.push(current);
      current = { header: line, bullets: [] };
    } else if (/^[-*]/.test(trimmed)) {
      if (!isWebsiteOrInfra(line)) {
        (current ?? (current = { header: null, bullets: [] })).bullets.push(line);
      }
    } else if (trimmed && !/^##/.test(trimmed) && trimmed !== '---') {
      // Plain paragraph text (not a section header, not a bullet)
      (current ?? (current = { header: null, bullets: [] })).bullets.push(line);
    }
  }
  if (current) sections.push(current);

  const out = [];
  for (const { header, bullets } of sections) {
    if (bullets.length === 0) continue;
    if (header) {
      out.push(header);
      out.push('');
    }
    out.push(...bullets);
    out.push('');
  }
  return out.join('\n').trim();
}

const parts2 = [];
for (const { version, body } of patches) {
  const filtered = filterPatchBody(body);
  if (filtered) {
    parts2.push(`### From v${version}\n\n${filtered}`);
  }
}

if (parts2.length === 0) {
  process.stdout.write('Minor improvements and bug fixes.\n');
} else {
  process.stdout.write(parts2.join('\n\n') + '\n');
}
