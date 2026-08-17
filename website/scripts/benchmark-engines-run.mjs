#!/usr/bin/env node
/**
 * Turnkey runner for the engine-benchmark data on `/engine-benchmarks/`
 * (website/.scratch/backlink-distribution/issues/05-engine-benchmark-page.md).
 *
 * Times a whisper.cpp `whisper-cli` transcription of a fixed reference clip
 * and reports RTF + WER for that run. Meant to be re-run on every hardware
 * class the maintainer has access to. Use the exact `hardwareClass` strings
 * from the `matrix` in `src/pages/engine-benchmarks.astro` (Vulkan covers
 * NVIDIA/AMD/Intel — there is no separate CUDA backend, CONTEXT.md §4.4) so
 * the row actually matches a page slot instead of showing as "pending" next
 * to an unmatched one — each run appends one row to
 * `src/data/engine-benchmarks.json`.
 *
 * Usage:
 *   node scripts/benchmark-engines-run.mjs \
 *     --binary /path/to/whisper-cli \
 *     --model /path/to/ggml-base.en.bin \
 *     --audio /path/to/jfk.wav \
 *     --reference "And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country." \
 *     --hardware-class "Vulkan (Windows/Linux, NVIDIA/AMD/Intel)" \
 *     --engine "whisper.cpp" \
 *     --model-name "base.en" \
 *     --runs 3
 *
 * The reference clip is whisper.cpp's own canonical demo sample
 * (`<whisper.cpp checkout>/samples/jfk.wav`): an 11s public-domain excerpt of
 * JFK's inaugural address with a well-known ground-truth transcript. Any WAV
 * + matching reference transcript works; using the same clip across hardware
 * classes keeps the numbers comparable.
 *
 * Writes/updates `src/data/engine-benchmarks.json` in place (adds or
 * replaces the row matching { engine, model, hardwareClass }).
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { computeRtf, computeWordErrorRate } from "./benchmark-engines-wer.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RESULTS_PATH = join(__dirname, "..", "src", "data", "engine-benchmarks.json");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    args[argv[i].replace(/^--/, "")] = argv[i + 1];
  }
  return args;
}

function requireArg(args, name) {
  const value = args[name];
  if (!value) throw new Error(`missing required --${name}`);
  return value;
}

/** Parses whisper-cli's stderr diagnostic lines (timings + audio duration). */
function parseWhisperStderr(stderr) {
  const total = stderr.match(/total time\s*=\s*([\d.]+)\s*ms/);
  const load = stderr.match(/load time\s*=\s*([\d.]+)\s*ms/);
  const duration = stderr.match(/([\d.]+)\s*sec\)/);
  if (!total || !load || !duration) {
    throw new Error("could not parse whisper-cli output — CLI output format may have changed");
  }
  return {
    totalMs: Number(total[1]),
    loadMs: Number(load[1]),
    audioDurationMs: Number(duration[1]) * 1000,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const binary = requireArg(args, "binary");
  const model = requireArg(args, "model");
  const audio = requireArg(args, "audio");
  const reference = requireArg(args, "reference");
  const hardwareClass = requireArg(args, "hardware-class");
  const engine = args.engine ?? "whisper.cpp";
  const modelName = requireArg(args, "model-name");
  const runs = Number(args.runs ?? "3");

  const processingTimesMs = [];
  let transcript = "";
  let audioDurationMs = 0;

  for (let i = 0; i < runs; i++) {
    const proc = spawnSync(binary, ["-m", model, "-f", audio, "-nt"], { encoding: "utf8" });
    if (proc.status !== 0) {
      throw new Error(`whisper-cli exited ${proc.status}: ${proc.stderr}`);
    }
    const timings = parseWhisperStderr(proc.stderr);
    audioDurationMs = timings.audioDurationMs;
    processingTimesMs.push(timings.totalMs - timings.loadMs);
    transcript = proc.stdout.trim();
  }

  const avgProcessingMs = processingTimesMs.reduce((a, b) => a + b, 0) / processingTimesMs.length;
  const rtf = computeRtf(avgProcessingMs, audioDurationMs);
  const werResult = computeWordErrorRate(reference, transcript);

  const row = {
    engine,
    model: modelName,
    hardwareClass,
    rtf: Number(rtf.toFixed(4)),
    wer: Number(werResult.wer.toFixed(4)),
    sampleSize: 1,
    measuredAt: new Date().toISOString().slice(0, 10),
    methodology: `avg of ${runs} runs, JFK sample (11.0s), processing time excludes one-time model load`,
  };

  const existing = existsSync(RESULTS_PATH)
    ? JSON.parse(readFileSync(RESULTS_PATH, "utf8"))
    : { schemaVersion: 1, rows: [] };
  const rows = existing.rows.filter(
    (r) => !(r.engine === row.engine && r.model === row.model && r.hardwareClass === row.hardwareClass),
  );
  rows.push(row);
  writeFileSync(RESULTS_PATH, JSON.stringify({ schemaVersion: 1, rows }, null, 2) + "\n");

  console.log(`RTF: ${row.rtf} | WER: ${(row.wer * 100).toFixed(1)}% | transcript: "${transcript}"`);
  console.log(`Written to ${RESULTS_PATH}`);
}

main();
