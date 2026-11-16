/**
 * Drift guard (#1152): the model sizes on the website come from
 * `model-sizes.ts` and must equal the pinned sizes in the app's Dart sources.
 * The prose in every language must name the same rounded values.
 */
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { MODEL_SIZE_BYTES, formatModelSize } from "../model-sizes.ts";
import { i18n } from "../../scripts/i18n.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..");
const dart = (p: string) => readFileSync(resolve(root, p), "utf8");

function sizesIn(source: string): number[] {
  return [...source.matchAll(/sizeBytes:\s*(\d+)/g)].map((m) => Number(m[1]));
}

describe("model sizes: website vs app", () => {
  const whisper = sizesIn(dart("lib/services/model_download_service.dart"));
  const bundle = sizesIn(dart("lib/services/stt_parakeet/parakeet_model_registry.dart"));
  const gguf = sizesIn(dart("lib/services/stt_parakeet/parakeet_gguf_model.dart"));

  it("whisper sizes equal sttModels", () => {
    expect(whisper.slice(0, 3)).toEqual([
      MODEL_SIZE_BYTES.whisperSmall,
      MODEL_SIZE_BYTES.whisperMedium,
      MODEL_SIZE_BYTES.whisperLargeV3Turbo,
    ]);
  });

  it("parakeet bundle equals the sum of its files", () => {
    expect(bundle.reduce((a, b) => a + b, 0)).toBe(MODEL_SIZE_BYTES.parakeetBundle);
  });

  it("parakeet GGUF equals the active GGUF model", () => {
    expect(gguf).toContain(MODEL_SIZE_BYTES.parakeetGguf);
  });

  it.each(Object.keys(i18n))("prose in %s names the same values", (lang) => {
    const dict = i18n[lang as keyof typeof i18n];
    const prose = Object.entries(dict)
      .filter(([k]) => k.startsWith("modelSize.result.") || k.startsWith("explainer.engines.section.parakeet"))
      .map(([, v]) => v)
      .join("\n");
    const mb = (b: number) => String(Math.round(b / 1_000_000));
    for (const b of [
      MODEL_SIZE_BYTES.whisperSmall,
      MODEL_SIZE_BYTES.whisperMedium,
      MODEL_SIZE_BYTES.whisperLargeV3Turbo,
      MODEL_SIZE_BYTES.parakeetBundle,
      MODEL_SIZE_BYTES.parakeetGguf,
    ]) {
      expect(prose, `${lang}: ${mb(b)}`).toMatch(new RegExp(`(^|[^0-9])${mb(b)}[ \\u00a0-]?(MB|Mo|МБ)`));
    }
    // No stale 1024-based numbers.
    expect(prose).not.toMatch(/\b(181|514|547|638|639)[  -]?(MB|Mo|МБ)/);
  });

  it("formats with the locale's decimal separator", () => {
    expect(formatModelSize(MODEL_SIZE_BYTES.parakeetBundle + MODEL_SIZE_BYTES.parakeetGguf, "de")).toBe("1,3 GB");
    expect(formatModelSize(MODEL_SIZE_BYTES.whisperSmall, "en")).toBe("190 MB");
  });
});
