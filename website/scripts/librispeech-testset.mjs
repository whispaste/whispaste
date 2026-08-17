/**
 * Shared loader for the LibriSpeech sample test set used by both
 * `benchmark-engines-testset.mjs` (whisper.cpp) and
 * `benchmark-engines-parakeet.mjs` (Parakeet/sherpa-onnx) — one manifest,
 * measured identically by both engines so their numbers are comparable.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
export const TESTSET_DIR = join(__dirname, "librispeech-sample");
const TRANS_FILE = join(TESTSET_DIR, "2277-149896.trans.txt");

/** Parses `<id> <TRANSCRIPT>` lines from the LibriSpeech .trans.txt format. */
export function loadTestset() {
  const lines = readFileSync(TRANS_FILE, "utf8").trim().split("\n");
  return lines.map((line) => {
    const spaceIdx = line.indexOf(" ");
    const id = line.slice(0, spaceIdx);
    const reference = line.slice(spaceIdx + 1);
    return { id, reference, audio: join(TESTSET_DIR, `${id}.wav`) };
  });
}
