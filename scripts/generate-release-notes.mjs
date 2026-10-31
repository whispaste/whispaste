#!/usr/bin/env node
/**
 * Generates bilingual user-facing release notes from a two-part changelog input:
 *
 *   1. Patch-changelog  — changes introduced in this single patch (v1.2.15 only)
 *   2. Minor-changelog  — cumulative changes across the entire X.Y.* series
 *
 * The AI produces two sections per language:
 *   - "What's new in v<version>"   (patch-specific, 2-4 bullets, no repeats of older patches)
 *   - "1.<minor>.x Highlights"     (semi-stable across patches, 3-5 bullets)
 *
 * This replaces the older single-input cumulative approach which produced
 * near-identical release notes for every patch in a minor series.
 *
 * Usage:
 *   node scripts/generate-release-notes.mjs \
 *     --version 1.2.15 \
 *     --patch patch-changelog.md \
 *     --minor minor-changelog.md \
 *     [--output-dir .] \
 *     [--model gpt-4o-mini]
 *
 * Reads OPENAI_API_KEY from env or from a .env at repo root. On API failure
 * falls back to a raw concatenation of the two inputs so the release still
 * gets meaningful notes.
 *
 * Outputs (UTF-8, no trailing newline):
 *   - release-notes-en.md
 *   - release-notes-de.md
 *   - release-notes-raw.md   (combined raw input for audit trail)
 *
 * Requires Node 18+ (uses global fetch).
 */

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve, dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dir, '../');

function parseArgs(argv) {
  const out = {
    version: null,
    patch: null,
    minor: null,
    outputDir: '.',
    model: 'gpt-4o-mini',
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--version') out.version = argv[++i];
    else if (a === '--patch') out.patch = argv[++i];
    else if (a === '--minor') out.minor = argv[++i];
    else if (a === '--output-dir') out.outputDir = argv[++i];
    else if (a === '--model') out.model = argv[++i];
  }
  return out;
}

function loadDotEnv() {
  const envPath = join(repoRoot, '.env');
  if (!existsSync(envPath)) return;
  const text = readFileSync(envPath, 'utf8');
  for (const line of text.split('\n')) {
    const m = line.match(/^\s*([^#=][^=]*?)\s*=\s*(.*)\s*$/);
    if (!m) continue;
    const key = m[1].trim();
    const val = m[2].trim().replace(/^['"]|['"]$/g, '');
    if (val && !process.env[key]) process.env[key] = val;
  }
}

function readOrFallback(path, fallback) {
  if (!path || !existsSync(path)) return fallback;
  const content = readFileSync(path, 'utf8').trim();
  return content || fallback;
}

function buildSystemPrompt(version, minorKey) {
  return `You write release notes for WhisPaste, a premium cross-platform dictation app (Windows + macOS).
Audience: non-technical users (founders, freelancers, writers, consultants).

INPUT FORMAT — you receive two clearly separated changelog inputs:

  <PATCH_CHANGELOG>  — changes introduced in THIS single patch (v${version}) only.
  <MINOR_CHANGELOG>  — cumulative changes across ALL patches in the ${minorKey} series.

Website, landing-page, CI/CD and infrastructure bullets have already been filtered out.

OUTPUT FORMAT — produce exactly two sections per language, in this order:

  ### What's new in v${version}            ← English title; in DE use "### Neu in v${version}"
    - 2 to 4 bullets describing ONLY what changed in this patch.
    - If PATCH_CHANGELOG is empty or only contains internal-only changes,
      output a single bullet: "Stability and minor improvements under the hood."
      (DE: "Stabilität und kleinere Verbesserungen unter der Haube.")

  ### ${minorKey} Highlights                ← English title; in DE use "### ${minorKey} im Überblick"
    - 3 to 5 bullets summarising the headline features of the entire ${minorKey} series.
    - These bullets stay stable across patches; only update them when a new
      patch genuinely adds a new headline feature.
    - NEVER repeat bullets from the "What's new" section — the highlights
      section is the rolling summary of the whole minor line, not a duplicate
      of the patch-specific delta.

RULES:
- Past tense or "now" phrasing, declarative, warm professional tone.
- No imperative mood. No jargon, no file paths, no class/function names.
- Never mention: API keys, webhook URLs, internal architecture, whisper-server,
  llama-server, MSIX, Discord, subprocess, token limits, GPU detection,
  database internals, CI pipeline details, onboarding wizard internals.
- Each bullet: one sentence, scannable in 1-2 seconds.
- German uses du-Form and reads naturally (not a machine translation).
- "Windows taskbar" not just "taskbar"; "Microsoft Store" not "Store".

OUTPUT (exactly this delimiter format, no extra prose around it):
===EN===
[English notes — both sections]
===DE===
[German notes — both sections, du-Form]
===END===`;
}

function buildUserPrompt(version, patchText, minorText) {
  return `Generate release notes for WhisPaste v${version}.

<PATCH_CHANGELOG>
${patchText}
</PATCH_CHANGELOG>

<MINOR_CHANGELOG>
${minorText}
</MINOR_CHANGELOG>`;
}

const SECRET_PATTERNS = [
  /sk-[a-zA-Z0-9]{10,}/gi,
  /gsk_[a-zA-Z0-9]+/gi,
  /Bearer\s+[a-zA-Z0-9._-]+/gi,
  /https?:\/\/[^\s]*supabase[^\s]*/gi,
  /https?:\/\/[^\s]*discord[^\s]*webhook[^\s]*/gi,
  /C:\\[^\s]+\.(dart|ps1|yml|json|db|exe)/gi,
  /whisper-server/gi,
  /llama-server/gi,
  /crashreporter/gi,
  /127\.0\.0\.1:\d+/gi,
];

function redactSecrets(text) {
  let out = text;
  for (const p of SECRET_PATTERNS) out = out.replace(p, '[REDACTED]');
  return out;
}

async function callOpenAI({ apiKey, model, systemPrompt, userPrompt }) {
  const body = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    temperature: 0.4,
    max_tokens: 1500,
  };
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey.trim()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new Error(`OpenAI HTTP ${res.status}: ${await res.text()}`);
  }
  const json = await res.json();
  const content = json?.choices?.[0]?.message?.content;
  if (!content) throw new Error('OpenAI returned no content');
  return content;
}

function parseEnDe(content) {
  const enMatch = content.match(/===EN===([\s\S]*?)===DE===/);
  const deMatch = content.match(/===DE===([\s\S]*?)===END===/);
  return {
    en: enMatch?.[1].trim() ?? '',
    de: deMatch?.[1].trim() ?? '',
  };
}

function rawFallback(version, minorKey, patchText, minorText) {
  const en = `### What's new in v${version}\n\n${patchText}\n\n### ${minorKey} Highlights\n\n${minorText}`;
  const de = `### Neu in v${version}\n\n${patchText}\n\n### ${minorKey} im Überblick\n\n${minorText}`;
  return { en, de };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.version) {
    process.stderr.write('Usage: generate-release-notes.mjs --version <X.Y.Z> --patch <file> --minor <file>\n');
    process.exit(1);
  }
  const [major, minor] = args.version.replace(/^v/, '').split('.');
  const minorKey = `${major}.${minor}.x`;

  loadDotEnv();
  const apiKey = process.env.OPENAI_API_KEY;

  const patchText = readOrFallback(args.patch, 'Stability and minor improvements.');
  const minorText = readOrFallback(args.minor, 'No prior patches in this minor series.');

  const rawCombined = `<PATCH_CHANGELOG>\n${patchText}\n</PATCH_CHANGELOG>\n\n<MINOR_CHANGELOG>\n${minorText}\n</MINOR_CHANGELOG>\n`;

  let en, de;
  if (!apiKey) {
    process.stderr.write('No OPENAI_API_KEY — falling back to raw concatenation.\n');
    ({ en, de } = rawFallback(args.version, minorKey, patchText, minorText));
  } else {
    try {
      const systemPrompt = buildSystemPrompt(args.version, minorKey);
      const userPrompt = buildUserPrompt(args.version, patchText, minorText);
      process.stderr.write(`Calling OpenAI ${args.model}…\n`);
      const content = await callOpenAI({ apiKey, model: args.model, systemPrompt, userPrompt });
      ({ en, de } = parseEnDe(content));
      if (!en) {
        process.stderr.write('Failed to parse EN section; using raw fallback.\n');
        ({ en, de } = rawFallback(args.version, minorKey, patchText, minorText));
      }
      if (!de) {
        process.stderr.write('Failed to parse DE section; reusing EN.\n');
        de = en;
      }
    } catch (e) {
      process.stderr.write(`OpenAI call failed: ${e.message}\nFalling back to raw concatenation.\n`);
      ({ en, de } = rawFallback(args.version, minorKey, patchText, minorText));
    }
  }

  en = redactSecrets(en);
  de = redactSecrets(de);

  writeFileSync(join(args.outputDir, 'release-notes-en.md'), en, 'utf8');
  writeFileSync(join(args.outputDir, 'release-notes-de.md'), de, 'utf8');
  writeFileSync(join(args.outputDir, 'release-notes-raw.md'), rawCombined, 'utf8');

  process.stderr.write(`Wrote release-notes-en.md (${en.length} chars), release-notes-de.md (${de.length} chars), release-notes-raw.md (${rawCombined.length} chars)\n`);
}

main().catch((e) => {
  process.stderr.write(`Fatal: ${e.stack || e.message}\n`);
  process.exit(1);
});
