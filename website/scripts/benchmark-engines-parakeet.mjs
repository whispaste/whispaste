#!/usr/bin/env node
/**
 * Multi-utterance runner for Parakeet (sherpa-onnx) on the engine-benchmark
 * data (`/engine-benchmarks/`, website/.scratch/backlink-distribution/
 * issues/05-engine-benchmark-page.md). Same test set and aggregation as
 * `benchmark-engines-testset.mjs` (whisper.cpp), so the two engines' numbers
 * are directly comparable.
 *
 * sherpa-onnx has no standalone CLI on PyPI (only a Python API), so the
 * actual transcription runs in `parakeet-transcribe.py`, spawned once here;
 * this script owns the test-set manifest, WER/RTF aggregation, and the
 * `engine-benchmarks.json` upsert — the same split of responsibilities as
 * the whisper.cpp runner (external binary measures, this script aggregates).
 *
 * Setup (once):
 *   python3 -m venv .venv && source .venv/bin/activate
 *   pip install sherpa-onnx numpy
 *
 * Usage:
 *   node scripts/benchmark-engines-parakeet.mjs \
 *     --python /path/to/venv/bin/python3 \
 *     --model-dir /path/to/parakeet-tdt-0.6b-v3 \
 *     --hardware-class "Apple Silicon (CPU)" \
 *     --num-threads 8
 *
 * The model dir is the app's own on-disk bundle (same 4 files
 * `ParakeetModelFile` downloads — see `lib/services/stt_parakeet/
 * parakeet_model_registry.dart`), e.g. on macOS:
 *   ~/Library/Application Support/WhisPaste/models/stt/parakeet-tdt-0.6b-v3
 *
 * Writes/updates `src/data/engine-benchmarks.json` in place, same schema as
 * the whisper.cpp runners.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { computeCorpusWer, computeRtf } from "./benchmark-engines-wer.mjs";
import { loadTestset, TESTSET_DIR } from "./librispeech-testset.mjs";

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

function main() {
  const args = parseArgs(process.argv.slice(2));
  const python = args.python ?? "python3";
  const modelDir = requireArg(args, "model-dir");
  const hardwareClass = requireArg(args, "hardware-class");
  const numThreads = args["num-threads"] ?? "8";

  const proc = spawnSync(
    python,
    [
      join(__dirname, "parakeet-transcribe.py"),
      "--model-dir",
      modelDir,
      "--testset-dir",
      TESTSET_DIR,
      "--num-threads",
      numThreads,
    ],
    { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
  );
  if (proc.status !== 0) {
    throw new Error(`parakeet-transcribe.py exited ${proc.status}: ${proc.stderr}`);
  }

  const hypotheses = new Map();
  const timings = new Map();
  for (const line of proc.stdout.trim().split("\n")) {
    const row = JSON.parse(line);
    hypotheses.set(row.id, row.hypothesis);
    timings.set(row.id, { processingMs: row.processingMs, audioDurationMs: row.audioDurationMs });
  }

  const testset = loadTestset();
  const werPairs = [];
  let totalProcessingMs = 0;
  let totalAudioMs = 0;
  for (const { id, reference } of testset) {
    const hypothesis = hypotheses.get(id);
    const timing = timings.get(id);
    if (!hypothesis || !timing) {
      throw new Error(`parakeet-transcribe.py did not report utterance ${id}`);
    }
    werPairs.push({ reference, hypothesis });
    totalProcessingMs += timing.processingMs;
    totalAudioMs += timing.audioDurationMs;
  }

  const rtf = computeRtf(totalProcessingMs, totalAudioMs);
  const werResult = computeCorpusWer(werPairs);

  const row = {
    engine: "Parakeet (sherpa-onnx)",
    model: "parakeet-tdt-0.6b-v3",
    hardwareClass,
    rtf: Number(rtf.toFixed(4)),
    wer: Number(werResult.wer.toFixed(4)),
    sampleSize: werResult.sampleSize,
    measuredAt: new Date().toISOString().slice(0, 10),
    methodology: `corpus WER (micro-averaged) + aggregate RTF over ${werResult.sampleSize} LibriSpeech dev-clean utterances (${(totalAudioMs / 1000).toFixed(1)}s total audio), processing time excludes one-time model load`,
  };

  const existing = existsSync(RESULTS_PATH)
    ? JSON.parse(readFileSync(RESULTS_PATH, "utf8"))
    : { schemaVersion: 1, rows: [] };
  const rows = existing.rows.filter(
    (r) => !(r.engine === row.engine && r.model === row.model && r.hardwareClass === row.hardwareClass),
  );
  rows.push(row);
  writeFileSync(RESULTS_PATH, JSON.stringify({ schemaVersion: 1, rows }, null, 2) + "\n");

  console.log(
    `RTF: ${row.rtf} | WER: ${(row.wer * 100).toFixed(1)}% over ${row.sampleSize} utterances (${werResult.totalEdits}/${werResult.totalRefWords} words)`,
  );
  console.log(`Written to ${RESULTS_PATH}`);
}

main();
