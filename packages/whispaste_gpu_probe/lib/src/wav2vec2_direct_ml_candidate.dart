/// ProbeCandidate for a German wav2vec2/Conformer ONNX model via DirectML.
///
/// This is a non-Whisper German STT alternative built on top of the reusable
/// [OnnxDirectMlCandidate] from Slice 14.  The subprocess pipeline, WER
/// computation, and outcome classification are all inherited from that class;
/// only the output format and model manifest differ.
///
/// ## Model choice
///
/// The candidate targets a German wav2vec2 CTC model exported to ONNX:
/// `facebook/wav2vec2-large-xlsr-53-german` on Hugging Face.  This is a
/// widely-used, openly-licensed German ASR model that can be run via ONNX
/// Runtime with the DirectML execution provider.
///
/// **Note on URL + SHA-256:** The download URL and SHA-256 below are
/// best-effort placeholders documented here for confirmation before any live
/// run.  The exact ONNX export path on Hugging Face must be verified by a
/// human before real deployment.
///
/// ## Output format assumption
///
/// The wav2vec2 runner is expected to emit one `text:` line containing the
/// full transcribed text:
///
///   `text: Guten Tag, das ist ein Test.`
///
/// Informational lines beginning with `[wav2vec2]` are silently ignored.
/// If the real runner emits a different format, only [parseWav2Vec2Transcript]
/// needs updating.
///
/// ## Skip behaviour (no GPU-accelerated path)
///
/// If the binary is not found or the launcher throws (DirectML EP not loadable
/// / binary incompatible), [OnnxDirectMlCandidate] maps the failure to
/// [Outcome.skipped] with a human-readable reason — the probe matrix continues
/// uninterrupted.
///
/// ## Reuse proof (AC2)
///
/// This file constructs an [OnnxDirectMlCandidate] with a custom
/// [parseWav2Vec2Transcript] parser.  No second runner is written.
library;

import 'onnx_direct_ml_candidate.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'model_manifest.dart';
import 'candidate_manifest.dart';

// ---------------------------------------------------------------------------
// Model manifest entry
// ---------------------------------------------------------------------------

/// Model size key for the German wav2vec2 ONNX model.
///
/// Uses a distinct key from Whisper models so the VRAM gate can differentiate.
const String wav2vec2ModelSizeKey = 'wav2vec2-de-xlsr53';

/// [ModelManifest] for the German wav2vec2/Conformer ONNX model.
///
/// **URL and SHA-256 are placeholders** — confirm before any live run.
/// The Hugging Face repository `jonatasgrosman/wav2vec2-large-xlsr-53-german`
/// provides quantized ONNX exports; the exact filename and checksum must be
/// pinned once the canonical export is confirmed.
ModelManifest wav2vec2ModelManifest() => ModelManifest(
  entries: [
    ModelEntry(
      name: wav2vec2ModelSizeKey,
      // PLACEHOLDER — confirm before live run.
      downloadUrl: Uri.parse(
        'https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-german'
        '/resolve/main/wav2vec2-large-xlsr-53-german.onnx',
      ),
      // PLACEHOLDER — compute SHA-256 of confirmed model file.
      sha256: '',
      targetFilename: 'wav2vec2-large-xlsr-53-german.onnx',
      // ~1.18 GB for large wav2vec2; placeholder until confirmed.
      sizeBytes: 1180000000,
    ),
  ],
);

// ---------------------------------------------------------------------------
// Output parser
// ---------------------------------------------------------------------------

/// Parses wav2vec2 runner stdout and returns the transcript text.
///
/// Scans [stdout] for lines matching `text: <text>`.  The first match wins.
/// Informational lines beginning with `[wav2vec2]` are silently ignored.
///
/// Returns an empty string when no transcript line is found.
String parseWav2Vec2Transcript(List<String> stdout) {
  for (final line in stdout) {
    final trimmed = line.trim();
    const prefix = 'text:';
    if (trimmed.toLowerCase().startsWith(prefix)) {
      final text = trimmed.substring(prefix.length).trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

// ---------------------------------------------------------------------------
// Factory function
// ---------------------------------------------------------------------------

/// Creates the German wav2vec2/Conformer DirectML candidate.
///
/// Reuses [OnnxDirectMlCandidate] from Slice 14 — only the binary name,
/// backend label, and [outputParser] differ from the Whisper-ONNX variant.
///
/// [runner] is the injectable [ProbeRunner]; override in tests with a fake
/// launcher.  [referenceTranscript] is the soll-transcript used for WER.
OnnxDirectMlCandidate wav2vec2DirectMlCandidate({
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
}) => OnnxDirectMlCandidate(
  id: 'wav2vec2-directml-de',
  binaryName: 'wav2vec2-onnx-directml.exe',
  backend: 'wav2vec2-directml',
  runner: runner,
  referenceTranscript: referenceTranscript,
  outputParser: parseWav2Vec2Transcript,
);

// ---------------------------------------------------------------------------
// CandidateManifest entry builder (consumed by candidate_manifest.dart)
// ---------------------------------------------------------------------------

/// Returns a [CandidateEntry] for the German wav2vec2 DirectML candidate.
///
/// Extracted as a standalone factory so [CandidateManifest.defaults] can
/// include it without duplicating the model manifest or model sizes.
CandidateEntry wav2vec2CandidateEntry({
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
}) => CandidateEntry(
  candidate: wav2vec2DirectMlCandidate(
    runner: runner,
    referenceTranscript: referenceTranscript,
  ),
  modelSizes: {wav2vec2ModelSizeKey},
  models: wav2vec2ModelManifest(),
);
