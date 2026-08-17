#!/usr/bin/env node
/**
 * Multi-utterance runner for the engine-benchmark data on `/engine-benchmarks/`
 * (website/.scratch/backlink-distribution/issues/05-engine-benchmark-page.md).
 *
 * Unlike `benchmark-engines-run.mjs` (single clip, sampleSize 1), this runs a
 * whisper.cpp `whisper-cli` transcription over every utterance in
 * `scripts/librispeech-sample/` and reports a corpus-level (micro-averaged)
 * WER plus an aggregate RTF — a more defensible accuracy number for a public
 * "linkable asset" than a single sentence.
 *
 * Test set: 20 utterances from one chapter of LibriSpeech `dev-clean`
 * (speaker 2277, chapter 149896), converted to 16kHz mono WAV. See
 * `scripts/librispeech-sample/ATTRIBUTION.md` for license + provenance.
 *
 * IMPORTANT: point `--model` at one of the three tiers WhisPaste actually
 * ships (`sttModels` in `lib/services/model_download_service.dart`:
 * `ggml-small-q5_1.bin` "Compact", `ggml-medium-q5_0.bin` "Balanced",
 * `ggml-large-v3-turbo-q5_0.bin` "Premium"), not an unquantized upstream
 * model like `ggml-base.en.bin` — that model isn't selectable in the app at
 * all and measures noticeably faster/lighter than anything a real user
 * runs, which understates whisper.cpp's actual cost against Parakeet.
 *
 * Usage (use the exact `hardwareClass` strings from the `matrix` in
 * `src/pages/engine-benchmarks.astro` so the row matches a page slot instead
 * of showing as "pending" next to an unmatched one):
 *   node scripts/benchmark-engines-testset.mjs \
 *     --binary /path/to/whisper-cli \
 *     --model /path/to/ggml-small-q5_1.bin \
 *     --hardware-class "Apple Silicon (Metal)" \
 *     --engine "whisper.cpp" \
 *     --model-name "small (Compact)"
 *
 * Pass `--no-gpu` to force whisper-cli's `-ng` flag (GPU explicitly
 * disabled), producing the CPU-only row that makes the Parakeet comparison
 * fair — Parakeet has no GPU backend at all, so comparing it against
 * GPU-accelerated whisper.cpp alone understates whisper.cpp's CPU cost:
 *   node scripts/benchmark-engines-testset.mjs \
 *     --binary /path/to/whisper-cli --model /path/to/ggml-small-q5_1.bin \
 *     --hardware-class "Apple Silicon (CPU)" --engine "whisper.cpp" \
 *     --model-name "small (Compact)" --no-gpu
 *
 * Writes/updates `src/data/engine-benchmarks.json` in place (adds or
 * replaces the row matching { engine, model, hardwareClass }), same schema
 * as `benchmark-engines-run.mjs` but with `sampleSize` set to the number of
 * utterances actually measured.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { computeCorpusWer, computeRtf } from "./benchmark-engines-wer.mjs";
import { loadTestset } from "./librispeech-testset.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RESULTS_PATH = join(__dirname, "..", "src", "data", "engine-benchmarks.json");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i].replace(/^--/, "");
    if (key === "no-gpu") {
      args[key] = true;
      continue;
    }
    args[key] = argv[i + 1];
    i += 1;
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
  const hardwareClass = requireArg(args, "hardware-class");
  const engine = args.engine ?? "whisper.cpp";
  const modelName = requireArg(args, "model-name");
  const gpuFlags = args["no-gpu"] ? ["-ng"] : [];

  const testset = loadTestset();
  const werPairs = [];
  let totalProcessingMs = 0;
  let totalAudioMs = 0;

  for (const { id, reference, audio } of testset) {
    const proc = spawnSync(binary, ["-m", model, "-f", audio, "-nt", ...gpuFlags], { encoding: "utf8" });
    if (proc.status !== 0) {
      throw new Error(`whisper-cli exited ${proc.status} on ${id}: ${proc.stderr}`);
    }
    const timings = parseWhisperStderr(proc.stderr);
    totalProcessingMs += timings.totalMs - timings.loadMs;
    totalAudioMs += timings.audioDurationMs;
    werPairs.push({ reference, hypothesis: proc.stdout.trim() });
    console.log(`  ${id}: OK (${timings.audioDurationMs.toFixed(0)}ms audio)`);
  }

  const rtf = computeRtf(totalProcessingMs, totalAudioMs);
  const werResult = computeCorpusWer(werPairs);

  const row = {
    engine,
    model: modelName,
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
    `\nRTF: ${row.rtf} | WER: ${(row.wer * 100).toFixed(1)}% over ${row.sampleSize} utterances (${werResult.totalEdits}/${werResult.totalRefWords} words)`,
  );
  console.log(`Written to ${RESULTS_PATH}`);
}

main();
