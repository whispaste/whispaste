#!/usr/bin/env node
/**
 * Sync changelog.json from CHANGELOG.md
 *
 * Usage: node website/scripts/sync-changelog.mjs
 *
 * Reads CHANGELOG.md (repo root) and maintains website/src/data/changelog.json
 * with one entry per MINOR version series (not one per patch).
 *
 * VERSION GROUPING POLICY:
 * - X.Y.0 (minor release): creates a new entry for this minor series.
 * - X.Y.Z, Z>0 (patch release): REPLACES the existing X.Y.x entry with
 *   cumulative content from all X.Y.* patches, updating the version to X.Y.Z.
 * - Website, CI/CD, and landing-page changes are filtered out — app changes only.
 *
 * IMPORTANT: Only versions with a corresponding git tag (v{version}) are
 * included. This prevents unreleased/pre-release CHANGELOG.md entries from
 * appearing on the website before the release tag is actually pushed.
 *
 * Trigger: deploy-pages.yml on main push OR workflow_dispatch from release.yml.
 */

import { readFileSync, writeFileSync } from 'fs';
import { execSync } from 'child_process';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dir, '../../');
const changelogMd = resolve(repoRoot, 'CHANGELOG.md');
const changelogJson = resolve(__dir, '../src/data/changelog.json');

/** Returns true if a git tag v{version} exists in the repo. */
function isTagged(version) {
  try {
    const out = execSync(`git tag -l "v${version}"`, {
      encoding: 'utf8',
      cwd: repoRoot,
    }).trim();
    return out.length > 0;
  } catch {
    return false;
  }
}

/** Returns "X.Y" series key for any X.Y.Z version string. */
function minorSeries(version) {
  const [major, minor] = version.split('.');
  return `${major}.${minor}`;
}

/** Returns the display version label "X.Y.x" used in release notes and changelog.json. */
function displayVersion(version) {
  const [major, minor] = version.split('.');
  return `${major}.${minor}.x`;
}

/** Returns true for patch releases (Z > 0). */
function isPatch(version) {
  return parseInt(version.split('.')[2] ?? '0') > 0;
}

/**
 * Patterns that identify website/infrastructure bullet points.
 * These are excluded from the user-facing changelog on the website.
 */
const EXCLUDE_PATTERNS = [
  /landing.?page/i,
  /landingpage/i,
  /\bwebsite\b/i,
  /\.astro\b/i,
  /\bhero.?(section|button|area|bereich)\b/i,
  /\bdownload.?page\b/i,
  /apple.?button|store.?button/i,
  /github.?pages|deploy.?pages/i,
  /\bplaywright\b/i,
  /\bci[\s/]?cd\b/i,
  /github.?actions?/i,
  /github.?workflow/i,
  /release.?workflow|workflow.?fix/i,
  /sync.?changelog|changelog.?json/i,
  /\bnsis\b|\bmsix\b/i,
  /astro.?build/i,
  /golden.?screenshot|screenshot.*golden/i,
];

function isExcluded(line) {
  const t = line.trim();
  if (!/^[-*]/.test(t)) return false;
  return EXCLUDE_PATTERNS.some((p) => p.test(t));
}

/** Classify a section header line. */
function sectionType(header) {
  const h = header.toLowerCase();
  if (/what.s new|highlights|features|neu/.test(h)) return 'highlights';
  if (/improvements|fixes|reliability|changes|verbesserungen|architecture|breaking/.test(h)) return 'improvements';
  return 'highlights'; // default unknown sections to highlights
}

/**
 * Parse a single version's CHANGELOG body into { highlights, improvements }.
 * Filters out website/infra bullets.
 */
function parseBody(body) {
  const highlights = [];
  const improvements = [];
  let section = 'highlights';

  for (const raw of body.split('\n')) {
    const line = raw.trim();
    if (!line || line === '---') continue;

    if (/^###/.test(line)) {
      section = sectionType(line);
      continue;
    }
    if (/^[-*]/.test(line) && !isExcluded(raw)) {
      const text = line.replace(/^[-*]\s+/, '').replace(/\*\*(.+?)\*\*/g, '$1');
      (section === 'improvements' ? improvements : highlights).push(text);
    } else if (!/^[-*]/.test(line) && !/^#/.test(line)) {
      // Plain paragraph text — treat as a highlight (e.g. re-release notes)
      highlights.push(line);
    }
  }
  return { highlights, improvements };
}

/**
 * Collect cumulative parsed content for ALL tagged patches in a minor series.
 * Returns merged { highlights, improvements } with deduplication.
 */
function buildCumulativeEntry(allVersions, series, mdContent) {
  const versionRegex = /^## (\d+\.\d+(?:\.\d+)?(?:\.\d+)?)/gm;
  const matches = [...mdContent.matchAll(versionRegex)];

  function normalise(v) { return v.split('.').slice(0, 3).join('.'); }
  const prefix = series + '.';

  // Gather all patches for the series, oldest first
  const patches = [];
  for (let i = 0; i < matches.length; i++) {
    const ver = normalise(matches[i][1]);
    if (ver.startsWith(prefix) && allVersions.has(ver)) {
      const start = matches[i].index + matches[i][0].length;
      const end = matches[i + 1]?.index ?? mdContent.length;
      patches.push({ version: ver, body: mdContent.slice(start, end).trim() });
    }
  }
  patches.sort((a, b) => {
    const ap = parseInt(a.version.split('.')[2] ?? '0');
    const bp = parseInt(b.version.split('.')[2] ?? '0');
    return ap - bp;
  });

  const highlights = [];
  const improvements = [];
  const seen = new Set();

  for (const { body } of patches) {
    const parsed = parseBody(body);
    for (const h of parsed.highlights) {
      if (!seen.has(h)) { seen.add(h); highlights.push(h); }
    }
    for (const imp of parsed.improvements) {
      if (!seen.has(imp)) { seen.add(imp); improvements.push(imp); }
    }
  }

  // Skip pure re-release notes ("No user-visible app changes" etc.)
  const meaningfulHighlights = highlights.filter(
    (h) => !/no user-visible|re-release|pipeline stabilization|version metadata/i.test(h)
  );
  const meaningfulImprovements = improvements.filter(
    (h) => !/no user-visible|re-release|pipeline stabilization|version metadata/i.test(h)
  );

  return {
    highlights: meaningfulHighlights,
    improvements: meaningfulImprovements,
  };
}

// ─── Main ────────────────────────────────────────────────────────────────────

const mdContent = readFileSync(changelogMd, 'utf8');
const existing = JSON.parse(readFileSync(changelogJson, 'utf8'));

// Parse all versions from CHANGELOG.md
const versionRegex = /^## (\d+\.\d+(?:\.\d+)?(?:\.\d+)?)/gm;
const allMatches = [...mdContent.matchAll(versionRegex)];
function normalise(v) { return v.split('.').slice(0, 3).join('.'); }

// Find all tagged versions (released) in the CHANGELOG
const taggedVersions = new Set();
for (const m of allMatches) {
  const ver = normalise(m[1]);
  if (isTagged(ver)) {
    taggedVersions.add(ver);
  } else {
    console.log(`⏭  Skipping ${ver} — no git tag v${ver} found (not yet released)`);
  }
}

// Group by minor series — keep only the latest patch per series
const latestPatchPerSeries = new Map();
for (const ver of taggedVersions) {
  const series = minorSeries(ver);
  const existing = latestPatchPerSeries.get(series);
  if (!existing || parseInt(ver.split('.')[2]) > parseInt(existing.split('.')[2])) {
    latestPatchPerSeries.set(series, ver);
  }
}

// Build a map of series → existing changelog.json entry
const existingBySeries = new Map();
for (const entry of existing) {
  existingBySeries.set(minorSeries(entry.version), entry);
}

let changed = 0;
const toAdd = [];
const toUpdate = [];

for (const [series, latestVer] of latestPatchPerSeries) {
  const existingEntry = existingBySeries.get(series);

  if (!existingEntry) {
    // New minor series — add
    console.log(`Adding new minor series: ${series} (latest: ${latestVer})`);
    const { highlights, improvements } = buildCumulativeEntry(
      taggedVersions, series, mdContent
    );
    if (highlights.length === 0 && improvements.length === 0) {
      console.log(`  ⚠  No app-visible changes found — skipping.`);
      continue;
    }
    toAdd.push({
      version: displayVersion(latestVer),
      date: new Date().toISOString().slice(0, 10),
      en: { highlights, improvements },
      de: { highlights, improvements }, // placeholder DE — AI/manual update
    });
    changed++;
  } else if (existingEntry.version !== displayVersion(latestVer)) {
    // Existing series entry is on an older patch — update with cumulative content
    console.log(`Updating ${series} series: ${existingEntry.version} → ${displayVersion(latestVer)}`);
    const { highlights, improvements } = buildCumulativeEntry(
      taggedVersions, series, mdContent
    );
    if (highlights.length === 0 && improvements.length === 0) {
      console.log(`  ⚠  No app-visible changes found — keeping previous entry.`);
      continue;
    }
    toUpdate.push({ series, latestVer: displayVersion(latestVer), highlights, improvements });
    changed++;
  } else {
    console.log(`✓  ${series} series is up to date (${existingEntry.version})`);
  }
}

if (changed === 0) {
  console.log('✅ changelog.json is up to date');
  process.exit(0);
}

// Apply updates to existing entries
let updated = existing.map((entry) => {
  const update = toUpdate.find((u) => minorSeries(entry.version) === u.series);
  if (!update) return entry;
  return {
    ...entry,
    version: update.latestVer,
    en: { highlights: update.highlights, improvements: update.improvements },
    // Preserve existing DE if it has been manually translated; otherwise use EN as placeholder
    de: entry.de?.highlights?.length > 0
      ? entry.de
      : { highlights: update.highlights, improvements: update.improvements },
  };
});

// Prepend new entries (newest first)
updated = [...toAdd, ...updated];

writeFileSync(changelogJson, JSON.stringify(updated, null, 2) + '\n');
console.log(`✅ changelog.json updated (${changed} series change(s))`);

