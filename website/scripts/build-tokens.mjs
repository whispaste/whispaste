#!/usr/bin/env node
/**
 * Design-token build: reads the platform-neutral token files in
 * ../design-tokens (DTCG shape) and writes src/styles/tokens.css.
 *
 *   node scripts/build-tokens.mjs           write the CSS
 *   node scripts/build-tokens.mjs --check   exit 1 if the CSS is stale
 *
 * Layers:
 *   primitives  → --wp-<group>-<name> on :root (raw values)
 *   semantic    → --wp-<group>-<name>, one block per mode; the light block
 *                 is scoped to [data-surface="light"] so any section can
 *                 switch mode and every nested component follows
 *   components  → --wp-<component>-<part>, re-declared on every
 *                 [data-surface] scope so their var() references resolve
 *                 against the mode of that scope
 *
 * No dependencies on purpose; a Dart emitter for the app can reuse
 * loadTokens()/resolve() later.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const TOKEN_DIR = join(here, '..', '..', 'design-tokens');
export const OUT_FILE = join(here, '..', 'src', 'styles', 'tokens.css');

const FLUID_MIN_VW = 390;
const FLUID_MAX_VW = 1920;

function readJson(name) {
  return JSON.parse(readFileSync(join(TOKEN_DIR, name), 'utf8'));
}

/** Flattens a DTCG tree into Map<path, {type, value, description, extensions}>. */
export function flatten(tree, prefix = [], inheritedType = undefined, out = new Map()) {
  const type = tree.$type ?? inheritedType;
  for (const [key, node] of Object.entries(tree)) {
    if (key.startsWith('$') || node === null || typeof node !== 'object' || Array.isArray(node)) continue;
    const path = [...prefix, key];
    if ('$value' in node) {
      out.set(path.join('.'), {
        type: node.$type ?? type,
        value: node.$value,
        description: node.$description,
        extensions: node.$extensions,
      });
    } else {
      flatten(node, path, type, out);
    }
  }
  return out;
}

export function loadTokens() {
  return {
    primitives: flatten(readJson('primitives.tokens.json')),
    dark: flatten(readJson('semantic.dark.tokens.json')),
    light: flatten(readJson('semantic.light.tokens.json')),
    components: flatten(readJson('components.tokens.json')),
  };
}

const ALIAS = /^\{([^}]+)\}$/;
const toVar = (path) => `--wp-${path.replaceAll('.', '-')}`;

const px = (v) => Number.parseFloat(v);
function fluid({ min, max, minVw = FLUID_MIN_VW, maxVw = FLUID_MAX_VW }) {
  const slope = (px(max) - px(min)) / (px(maxVw) - px(minVw));
  const base = px(min) - slope * px(minVw);
  const r = (n) => Number(n.toFixed(4));
  return `clamp(${r(px(min) / 16)}rem, ${r(base / 16)}rem + ${r(slope * 100)}vw, ${r(px(max) / 16)}rem)`;
}

/**
 * Formats one token value as CSS. Aliases become var() references so the
 * cascade (not the generator) decides which mode a value comes from.
 */
function css(token, scopes) {
  const { type, value, extensions } = token;
  const ref = (v) => {
    const m = typeof v === 'string' ? v.match(ALIAS) : null;
    if (!m) return null;
    if (!scopes.some((s) => s.has(m[1]))) throw new Error(`Unresolved alias {${m[1]}}`);
    return `var(${toVar(m[1])})`;
  };
  const direct = ref(value);
  if (direct) return direct;
  switch (type) {
    case 'dimension':
      return extensions?.fluid ? fluid(extensions.fluid) : value;
    case 'fontFamily':
      return value.map((f) => (/[\s-]/.test(f) && !f.startsWith('ui-') && f !== 'sans-serif' && f !== 'system-ui' && f !== 'monospace' ? `"${f}"` : f)).join(', ');
    case 'cubicBezier':
      return `cubic-bezier(${value.join(', ')})`;
    case 'shadow':
      return value
        .map((s) => `${s.offsetX} ${s.offsetY} ${s.blur} ${s.spread} ${ref(s.color) ?? s.color}`)
        .join(', ');
    case 'gradient': {
      const stops = value.map((s) => `${ref(s.color) ?? s.color} ${Math.round(s.position * 100)}%`);
      return `linear-gradient(${extensions?.angle ?? '180deg'}, ${stops.join(', ')})`;
    }
    default:
      if (typeof value === 'string') {
        // Aliases embedded in composite strings, e.g. "1px solid {border.default}".
        return value.replace(/\{([^}]+)\}/g, (_m, p) => {
          if (!scopes.some((s) => s.has(p))) throw new Error(`Unresolved alias {${p}}`);
          return `var(${toVar(p)})`;
        });
      }
      return String(value);
  }
}

function block(selector, tokens, scopes, indent = '  ') {
  const lines = [];
  for (const [path, token] of tokens) {
    lines.push(`${indent}${toVar(path)}: ${css(token, scopes)};`);
  }
  return `${selector} {\n${lines.join('\n')}\n}`;
}

export function buildCss() {
  const { primitives, dark, light, components } = loadTokens();

  const missing = [...dark.keys()].filter((k) => !light.has(k));
  const extra = [...light.keys()].filter((k) => !dark.has(k));
  if (missing.length || extra.length) {
    throw new Error(`Semantic modes differ. Only dark: ${missing.join(', ') || '-'}; only light: ${extra.join(', ') || '-'}`);
  }
  for (const key of [...dark.keys(), ...components.keys()]) {
    if (primitives.has(key)) throw new Error(`Token ${key} shadows a primitive`);
  }

  const header = `/* Generated by scripts/build-tokens.mjs from design-tokens/*.tokens.json.
   Do not edit by hand: change the JSON and run \`npm run tokens\`. */`;

  return [
    header,
    block(':root', primitives, [primitives]),
    block(':root,\n[data-surface="dark"]', dark, [primitives]),
    block('[data-surface="light"]', light, [primitives]),
    block(':root,\n[data-surface]', components, [primitives, dark]),
    '',
  ].join('\n\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const next = buildCss();
  if (process.argv.includes('--check')) {
    const current = readFileSync(OUT_FILE, 'utf8');
    if (current !== next) {
      console.error('src/styles/tokens.css is stale: run `npm run tokens`.');
      process.exit(1);
    }
    console.log('tokens.css is up to date.');
  } else {
    writeFileSync(OUT_FILE, next);
    console.log(`Wrote ${OUT_FILE}`);
  }
}
