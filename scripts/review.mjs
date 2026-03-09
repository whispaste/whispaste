#!/usr/bin/env node
/**
 * WhisPaste Quality Review Orchestrator
 *
 * Collects review-relevant files, groups them by concern area, generates
 * structured review prompts, and executes them via GitHub Copilot CLI.
 * Uses the quality-audit skill for evaluation criteria.
 *
 * Usage:
 *   node scripts/review.mjs                   # Full review, sequential execution
 *   node scripts/review.mjs --changed         # Review only changed files
 *   node scripts/review.mjs --fleet           # Generate fleet prompt + copy to clipboard
 *   node scripts/review.mjs --dry-run         # Preview prompts without executing
 *   node scripts/review.mjs --concern ui      # Review only a specific concern group
 */

import { execSync, execFileSync } from 'node:child_process';
import { readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const APP_ROOT = resolve(__dirname, '..');
const SKILL_REF = '.agents/skills/quality-audit/SKILL.md';

// ─── Configuration ──────────────────────────────────────────────────────────

const CONCERN_GROUPS = {
  text: {
    label: 'Text & Content',
    description: 'Translation files, content copy, localization',
    patterns: [
      'ui_main/scripts/01-translations.js',
      'l10n.go',
      'l10n_bridge.go',
      'postprocess.go',
      'README.md',
      'website/src/pages/*.astro',
      'website/src/scripts/i18n.ts',
    ],
    dimensions: [1, 5],
  },
  ui: {
    label: 'UI & Interaction',
    description: 'HTML templates, JavaScript interactions, CSS styling',
    patterns: [
      'ui_main/template.html',
      'ui_main/pages/*.html',
      'ui_main/scripts/0[2-9]*.js',
      'ui_main/scripts/1*.js',
      'ui_main/styles/*.css',
      'website/src/components/*.astro',
    ],
    dimensions: [2, 3, 6],
  },
  code: {
    label: 'Code Quality',
    description: 'Go source files — error handling, logging, architecture',
    patterns: ['*.go'],
    exclude: ['*_test.go'],
    dimensions: [2, 6],
  },
  design: {
    label: 'Design System',
    description: 'Design tokens, variables, theme consistency across surfaces',
    patterns: [
      'ui_main/styles/00-variables.css',
      'website/src/styles/*.css',
      'website/design-system/**/*.md',
    ],
    dimensions: [3, 4],
  },
};

const DIMENSION_NAMES = {
  1: 'Zielgruppen-Passung (Target Audience Alignment)',
  2: 'Benutzerfreundlichkeit (UX/UI Quality)',
  3: 'Hochwertigkeit (Premium Quality Score)',
  4: 'Oberflächen-Konsistenz (Cross-Surface Consistency)',
  5: 'Inhaltsqualität (Content Quality)',
  6: 'Wartbarkeit / SoC (Code Architecture & Maintainability)',
};

// ─── Helpers ────────────────────────────────────────────────────────────────

/** Simple glob matcher supporting *, **, and ? */
function matchGlob(filePath, pattern) {
  // Normalise separators
  const fp = filePath.replace(/\\/g, '/');
  const pat = pattern.replace(/\\/g, '/');

  // Build regex from glob
  let regex = '';
  let i = 0;
  while (i < pat.length) {
    const c = pat[i];
    if (c === '*') {
      if (pat[i + 1] === '*') {
        // ** matches any path segments
        if (pat[i + 2] === '/') {
          regex += '(?:.+/)?';
          i += 3;
        } else {
          regex += '.*';
          i += 2;
        }
      } else {
        // * matches anything except /
        regex += '[^/]*';
        i++;
      }
    } else if (c === '?') {
      regex += '[^/]';
      i++;
    } else if (c === '[') {
      // Character class — pass through (e.g., [2-9])
      const end = pat.indexOf(']', i);
      if (end === -1) {
        regex += '\\[';
        i++;
      } else {
        regex += pat.slice(i, end + 1);
        i = end + 1;
      }
    } else if ('.+^${}()|\\'.includes(c)) {
      regex += '\\' + c;
      i++;
    } else {
      regex += c;
      i++;
    }
  }

  return new RegExp('^' + regex + '$').test(fp);
}

/** Recursively list all files under dir, returning paths relative to base. */
function walkDir(dir, base = dir) {
  let results = [];
  try {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith('.')) continue;
      if (entry.name === 'node_modules' || entry.name === 'vendor') continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        results = results.concat(walkDir(full, base));
      } else {
        results.push(relative(base, full).replace(/\\/g, '/'));
      }
    }
  } catch { /* permission errors etc. */ }
  return results;
}

/** Run a shell command and return stdout (empty string on failure). */
function run(cmd) {
  try {
    return execSync(cmd, { cwd: APP_ROOT, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch {
    return '';
  }
}

// ─── Core Logic ─────────────────────────────────────────────────────────────

function getReviewFiles(patterns, exclude = [], changedOnly = false) {
  const files = new Set();

  if (changedOnly) {
    let changed = run('git diff --name-only HEAD');
    if (!changed) changed = run('git diff --name-only --staged');
    if (!changed) return [];

    const changedList = changed.split('\n').filter(Boolean);
    for (const pattern of patterns) {
      for (const f of changedList) {
        if (!matchGlob(f, pattern)) continue;
        if (exclude.some(ex => matchGlob(f, ex))) continue;
        if (existsSync(join(APP_ROOT, f))) files.add(f);
      }
    }
  } else {
    const allFiles = walkDir(APP_ROOT);
    for (const pattern of patterns) {
      for (const f of allFiles) {
        if (!matchGlob(f, pattern)) continue;
        if (exclude.some(ex => matchGlob(f, ex))) continue;
        files.add(f);
      }
    }
  }

  return [...files].sort();
}

function buildReviewPrompt(group, files) {
  const dimList = group.dimensions
    .map(d => `  - Dimension ${d}: ${DIMENSION_NAMES[d]}`)
    .join('\n');
  const fileList = files.map(f => `  - ${f}`).join('\n');

  return `Invoke the quality-audit skill (see ${SKILL_REF}) and perform an INCREMENTAL quality audit.

**Concern Group:** ${group.label} — ${group.description}

**Focus Dimensions:**
${dimList}

**Files to audit:**
${fileList}

Review each file against the checklist items for the focus dimensions defined in the quality-audit skill.
For each issue found, report: severity (BLOCKER/MAJOR/POLISH), dimension number, file and line,
affected persona(s), problem description, and concrete fix suggestion.

End with the dimension scores table and a prioritized refactoring list.`;
}

// ─── Output Helpers ─────────────────────────────────────────────────────────

const CYAN = '\x1b[36m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const RED = '\x1b[31m';
const DIM = '\x1b[2m';
const WHITE = '\x1b[97m';
const RESET = '\x1b[0m';

function banner() {
  console.log('');
  console.log(`${CYAN}  ╔══════════════════════════════════════════════╗${RESET}`);
  console.log(`${CYAN}  ║   WhisPaste Quality Review Orchestrator      ║${RESET}`);
  console.log(`${CYAN}  ╚══════════════════════════════════════════════╝${RESET}`);
  console.log('');
}

function summary(reviewPlan) {
  console.log('');
  console.log(`${DIM}  ┌──────────────────────────────────────────────┐${RESET}`);
  console.log(`${DIM}  │  Review Summary                              │${RESET}`);
  console.log(`${DIM}  └──────────────────────────────────────────────┘${RESET}`);
  for (const key of Object.keys(reviewPlan).sort()) {
    const r = reviewPlan[key];
    const icon = r.files.length > 0 ? '✓' : '○';
    const color = r.files.length > 0 ? GREEN : DIM;
    console.log(`${color}    ${icon} ${r.label}: ${r.files.length} files${RESET}`);
  }
  console.log('');
}

// ─── CLI Argument Parsing ───────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { changed: false, fleet: false, dryRun: false, concern: 'all' };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--changed': case '-c': opts.changed = true; break;
      case '--fleet': case '-f': opts.fleet = true; break;
      case '--dry-run': case '-d': opts.dryRun = true; break;
      case '--concern':
        opts.concern = args[++i] || 'all';
        if (!['all', 'text', 'ui', 'code', 'design'].includes(opts.concern)) {
          console.error(`${RED}  Invalid concern: ${opts.concern}. Must be one of: all, text, ui, code, design${RESET}`);
          process.exit(1);
        }
        break;
      case '--help': case '-h':
        console.log(`Usage: node scripts/review.mjs [options]

Options:
  --changed, -c      Only review files changed since last commit
  --fleet, -f        Generate fleet prompt + copy to clipboard
  --dry-run, -d      Preview prompts without executing
  --concern <name>   Filter to: all, text, ui, code, design
  --help, -h         Show this help`);
        process.exit(0);
        break;
      default:
        console.error(`${RED}  Unknown option: ${args[i]}${RESET}`);
        process.exit(1);
    }
  }
  return opts;
}

// ─── Main ───────────────────────────────────────────────────────────────────

function main() {
  const opts = parseArgs();
  banner();

  const modeLabel = opts.changed ? 'Changed files only' : 'Full codebase';
  const execLabel = opts.dryRun ? 'Dry run (no execution)' : opts.fleet ? 'Fleet mode' : 'Sequential execution';
  console.log(`${DIM}  Mode: ${modeLabel} | Execution: ${execLabel}${RESET}`);
  console.log('');

  // Determine groups
  const groupKeys = opts.concern === 'all' ? Object.keys(CONCERN_GROUPS) : [opts.concern];

  // Collect files
  const reviewPlan = {};
  let totalFiles = 0;

  for (const key of groupKeys) {
    const group = CONCERN_GROUPS[key];
    const files = getReviewFiles(group.patterns, group.exclude || [], opts.changed);
    reviewPlan[key] = { label: group.label, files, group };
    totalFiles += files.length;

    if (files.length > 0) {
      console.log(`${WHITE}  [${key}] ${group.label}: ${files.length} files found${RESET}`);
      for (const f of files) {
        console.log(`${DIM}      ${f}${RESET}`);
      }
    } else {
      console.log(`${DIM}  [${key}] ${group.label}: no files${RESET}`);
    }
  }

  console.log('');
  console.log(`${CYAN}  Total: ${totalFiles} files across ${groupKeys.length} concern groups${RESET}`);
  console.log('');

  if (totalFiles === 0) {
    console.log(`${YELLOW}  No files to review.${RESET}`);
    process.exit(0);
  }

  // Generate prompts
  const prompts = {};
  for (const key of groupKeys) {
    const plan = reviewPlan[key];
    if (plan.files.length === 0) continue;
    prompts[key] = buildReviewPrompt(plan.group, plan.files);
  }

  // ─── Execution ──────────────────────────────────────────────────────────

  if (opts.dryRun) {
    console.log(`${YELLOW}  === DRY RUN — Generated Prompts ===${RESET}`);
    console.log('');

    for (const key of Object.keys(prompts).sort()) {
      console.log(`${CYAN}  ── [${key}] ${reviewPlan[key].label} ──${RESET}`);
      console.log('');
      console.log(prompts[key]);
      console.log('');
      console.log(`${DIM}  ────────────────────────────────────${RESET}`);
      console.log('');
    }
  } else if (opts.fleet) {
    console.log(`${YELLOW}  Generating fleet-optimized prompt...${RESET}`);

    let combined = `I need a comprehensive quality audit of WhisPaste. Use the quality-audit skill (see ${SKILL_REF}).

Please dispatch parallel sub-agents for each concern group below. Each agent should perform
an independent quality audit of its assigned files and dimensions, then return a structured
report following the quality-audit skill output format.

`;

    let agentNum = 1;
    for (const key of Object.keys(prompts).sort()) {
      combined += `\n--- Agent ${agentNum}: ${reviewPlan[key].label} ---\n${prompts[key]}\n`;
      agentNum++;
    }

    combined += `
After all agents complete, synthesize their reports into a single Quality Audit Report with:
1. Overall dimension scores (aggregate across all agents)
2. Combined prioritized refactoring list (sorted by severity then audience impact)
3. Total issue counts by severity`;

    // Write to temp file
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const tempFile = join(tmpdir(), `whispaste-fleet-review-${ts}.md`);
    writeFileSync(tempFile, combined, 'utf8');
    console.log(`${DIM}  Prompt saved to: ${tempFile}${RESET}`);

    // Copy to clipboard via clip.exe (Windows)
    try {
      execSync('clip.exe', { input: combined, cwd: APP_ROOT, stdio: ['pipe', 'pipe', 'pipe'] });
      console.log(`${GREEN}  Prompt copied to clipboard!${RESET}`);
    } catch {
      console.log(`${YELLOW}  Could not copy to clipboard — use the temp file above.${RESET}`);
    }

    console.log('');
    console.log(`${WHITE}  Next steps:${RESET}`);
    console.log(`${DIM}    1. Open Copilot CLI: copilot${RESET}`);
    console.log(`${DIM}    2. Paste the prompt (Ctrl+V)${RESET}`);
    console.log(`${DIM}    3. The agent will dispatch fleet sub-agents automatically${RESET}`);
    console.log('');
  } else {
    // Sequential execution via copilot -p
    console.log(`${YELLOW}  Executing review prompts sequentially...${RESET}`);
    console.log('');

    const results = {};
    for (const key of Object.keys(prompts).sort()) {
      const plan = reviewPlan[key];
      console.log(`${CYAN}  ── Reviewing: ${plan.label} (${plan.files.length} files) ──${RESET}`);

      try {
        const output = execFileSync('copilot', ['-p', prompts[key]], {
          cwd: APP_ROOT,
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
          timeout: 300_000, // 5 min per concern group
        });
        console.log(output);
        results[key] = { success: true, output };
      } catch (err) {
        const exitCode = err.status ?? 'unknown';
        const output = (err.stdout || '') + (err.stderr || '');
        console.log(`${YELLOW}  ⚠ Copilot returned exit code ${exitCode}${RESET}`);
        if (output) console.log(`${YELLOW}${output}${RESET}`);
        if (!output && !err.status) {
          console.log(`${RED}  ✗ Failed to execute. Ensure 'copilot' is installed and in PATH.${RESET}`);
          console.log(`${DIM}  Install: npm install -g @githubnext/github-copilot-cli${RESET}`);
        }
        results[key] = { success: false, output };
      }

      console.log(`${DIM}  ────────────────────────────────────${RESET}`);
      console.log('');
    }

    // Summary
    const succeeded = Object.values(results).filter(r => r.success).length;
    const failed = Object.values(results).filter(r => !r.success).length;
    const color = failed > 0 ? YELLOW : GREEN;
    console.log(`${color}  Review complete: ${succeeded} succeeded, ${failed} failed${RESET}`);
  }

  summary(reviewPlan);
}

main();
