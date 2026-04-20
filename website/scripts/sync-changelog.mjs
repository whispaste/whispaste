#!/usr/bin/env node
/**
 * Sync changelog.json from CHANGELOG.md
 *
 * Usage: node website/scripts/sync-changelog.mjs
 *
 * Reads CHANGELOG.md (repo root) and ensures website/src/data/changelog.json
 * has up-to-date entries for every version found. New versions are prepended
 * with EN content from CHANGELOG.md. DE content is copied from EN as a
 * placeholder — update manually or via translation workflow.
 */

import { readFileSync, writeFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dir, '../../');
const changelogMd = resolve(repoRoot, 'CHANGELOG.md');
const changelogJson = resolve(__dir, '../src/data/changelog.json');

function parseChangelogMd(content) {
  const sections = [];
  const versionRegex = /^## (\d+\.\d+\.\d+)/gm;
  const matches = [...content.matchAll(versionRegex)];

  for (let i = 0; i < matches.length; i++) {
    const version = matches[i][1];
    const start = matches[i].index + matches[i][0].length;
    const end = matches[i + 1]?.index ?? content.length;
    const body = content.slice(start, end).trim();

    const highlights = [];
    const improvements = [];
    let currentSection = null;

    for (const line of body.split('\n')) {
      const trimmed = line.trim();
      if (/^###.*what.s new|^###.*highlights|^###.*features/i.test(trimmed)) {
        currentSection = 'highlights';
      } else if (/^###.*improvements|^###.*fixes|^###.*reliability|^###.*changes/i.test(trimmed)) {
        currentSection = 'improvements';
      } else if (/^###/.test(trimmed)) {
        currentSection = 'highlights';
      } else if (/^[-*]\s+\*\*(.+?)\*\*\s*[—–-]?\s*(.*)/.test(trimmed)) {
        const m = trimmed.match(/^[-*]\s+\*\*(.+?)\*\*\s*[—–-]?\s*(.*)/);
        const text = m[2] ? `${m[1]} — ${m[2]}` : m[1];
        (currentSection === 'improvements' ? improvements : highlights).push(text);
      } else if (/^[-*]\s+(.+)/.test(trimmed)) {
        const text = trimmed.replace(/^[-*]\s+/, '');
        (currentSection === 'improvements' ? improvements : highlights).push(text);
      }
    }

    // Fallback: if nothing was parsed, use the first few bullet points as highlights
    if (highlights.length === 0 && improvements.length === 0) {
      for (const line of body.split('\n')) {
        const trimmed = line.trim();
        if (/^[-*]\s+(.+)/.test(trimmed)) {
          highlights.push(trimmed.replace(/^[-*]\s+/, ''));
        }
      }
    }

    if (highlights.length > 0 || improvements.length > 0) {
      sections.push({ version, highlights, improvements });
    }
  }
  return sections;
}

const mdContent = readFileSync(changelogMd, 'utf8');
const parsed = parseChangelogMd(mdContent);
const existing = JSON.parse(readFileSync(changelogJson, 'utf8'));
const existingVersions = new Set(existing.map(e => e.version));

let added = 0;
const toAdd = [];

for (const { version, highlights, improvements } of parsed) {
  if (existingVersions.has(version)) continue;
  console.log(`Adding new version: ${version}`);
  toAdd.push({
    version,
    date: new Date().toISOString().slice(0, 10),
    en: { highlights, improvements },
    de: { highlights, improvements }, // placeholder — update DE manually
  });
  added++;
}

if (added > 0) {
  const updated = [...toAdd, ...existing];
  writeFileSync(changelogJson, JSON.stringify(updated, null, 2) + '\n');
  console.log(`✅ Added ${added} version(s) to changelog.json`);
} else {
  console.log('✅ changelog.json is already up to date');
}
