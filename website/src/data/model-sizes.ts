/**
 * Download sizes of the speech models, in bytes. Mirrors the app's single
 * source, the bundled model catalog (lib/core/models/bundled_model_catalog.dart);
 * the drift test
 * `__tests__/model-sizes.test.ts` fails when a value differs (#1152).
 *
 * Unit: steps of 1000, like Finder and Linux file managers. Windows Explorer
 * counts in steps of 1024 and shows smaller numbers; the pages say so.
 */
export const MODEL_SIZE_BYTES = {
  whisperSmall: 190085487,
  whisperMedium: 539212467,
  whisperLargeV3Turbo: 574041195,
  /** Sum of the four sherpa-onnx bundle files. */
  parakeetBundle: 652184281 + 11845275 + 6355277 + 93939,
  /** The GGUF model that is added where the GPU engine is used. */
  parakeetGguf: 668757119,
} as const;

/** `"190 MB"` / `"1,3 GB"` with the decimal separator of [lang]. */
export function formatModelSize(bytes: number, lang: string): string {
  const mb = bytes / 1_000_000;
  const nf = (v: number, digits: number) =>
    new Intl.NumberFormat(lang, { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v);
  return bytes >= 1_000_000_000 ? `${nf(bytes / 1_000_000_000, 1)} GB` : `${nf(Math.round(mb), 0)} MB`;
}
