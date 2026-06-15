/// CandidateManifest — declarative registry of all ProbeCandidate instances.
///
/// The orchestrator reads from here; no candidate is hardcoded elsewhere.
/// Each variant is configured with its injectable [ProbeRunner] seam so that
/// tests can substitute fake launchers without touching the manifest entries.
///
/// Every entry also declares the model-size set it should be probed across and
/// the [ModelManifest] those sizes resolve against, so the matrix dimension
/// (candidate × model size) is fully declarative here.
library;

import 'probe_types.dart';
import 'probe_runner.dart';
import 'model_manifest.dart';
import 'whisper_cpp_candidate.dart';

// ---------------------------------------------------------------------------
// Default model registry
// ---------------------------------------------------------------------------

/// The model sizes the whisper.cpp family is probed across.
///
/// Keys match `sttModelVramMB` in `package:whispaste_diagnostics` so the VRAM
/// gate (issue 04) and the manifest agree on identifiers.
const String modelSizeSmall = 'whisper-small';
const String modelSizeMedium = 'whisper-medium';
const String modelSizeLargeTurbo = 'whisper-large-v3-turbo';

/// Default [ModelManifest] every candidate entry references.
///
/// Acquisition (download + checksum) is handled by `acquireModel`; the manifest
/// only declares which models exist and how to fetch them.
ModelManifest defaultModelManifest() => ModelManifest(
  entries: [
    ModelEntry(
      name: modelSizeSmall,
      downloadUrl: Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      ),
      sha256: '',
      targetFilename: 'ggml-small.bin',
      sizeBytes: 488000000,
    ),
    ModelEntry(
      name: modelSizeMedium,
      downloadUrl: Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
      ),
      sha256: '',
      targetFilename: 'ggml-medium.bin',
      sizeBytes: 1530000000,
    ),
    ModelEntry(
      name: modelSizeLargeTurbo,
      downloadUrl: Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin',
      ),
      sha256: '',
      targetFilename: 'ggml-large-v3-turbo.bin',
      sizeBytes: 1620000000,
    ),
  ],
);

// ---------------------------------------------------------------------------
// CandidateEntry
// ---------------------------------------------------------------------------

/// One declarative manifest entry: a [ProbeCandidate] plus the model dimension
/// it is probed across.
///
/// [modelSizes] is the set of model-size keys (subset of [models]'s entry
/// names) this candidate runs against. [models] is the [ModelManifest] those
/// keys resolve against for acquisition.
class CandidateEntry {
  const CandidateEntry({
    required this.candidate,
    required this.modelSizes,
    required this.models,
  });

  /// The probe candidate implementation.
  final ProbeCandidate candidate;

  /// Model-size keys this candidate should be probed across.
  final Set<String> modelSizes;

  /// The model manifest the [modelSizes] resolve against.
  final ModelManifest models;
}

// ---------------------------------------------------------------------------
// CandidateManifest
// ---------------------------------------------------------------------------

/// Declarative list of all [CandidateEntry] instances for one probe run.
///
/// In production, build via [CandidateManifest.defaults].  In tests, inject a
/// minimal list or override individual runner seams.
class CandidateManifest {
  const CandidateManifest({required this.entries});

  /// All entries to run, in order.
  final List<CandidateEntry> entries;

  /// Convenience view of just the candidates, in order.
  ///
  /// The orchestrator consumes candidates directly; the model dimension lives
  /// on [entries].
  List<ProbeCandidate> get candidates =>
      entries.map((e) => e.candidate).toList();

  /// Default production manifest with the full whisper.cpp family.
  ///
  /// [runner] is applied to all subprocess-backed candidates; pass a
  /// custom [ProbeRunner] in tests to inject a fake launcher.
  /// [referenceTranscript] is forwarded to each candidate for WER computation.
  factory CandidateManifest.defaults({
    ProbeRunner runner = const ProbeRunner(),
    String? referenceTranscript,
  }) {
    final models = defaultModelManifest();

    // The GPU/CPU backends are probed across the full model-size set.
    final fullSizes = {modelSizeSmall, modelSizeMedium, modelSizeLargeTurbo};

    // The legacy OpenCL/CLBlast build only targets the smaller models.
    final legacySizes = {modelSizeSmall, modelSizeMedium};

    return CandidateManifest(
      entries: [
        CandidateEntry(
          candidate: whisperCppCpuCandidate(
            runner: runner,
            referenceTranscript: referenceTranscript,
          ),
          modelSizes: fullSizes,
          models: models,
        ),
        CandidateEntry(
          candidate: whisperCppCuda12Candidate(
            runner: runner,
            referenceTranscript: referenceTranscript,
          ),
          modelSizes: fullSizes,
          models: models,
        ),
        CandidateEntry(
          candidate: whisperCppVulkanCandidate(
            runner: runner,
            referenceTranscript: referenceTranscript,
          ),
          modelSizes: fullSizes,
          models: models,
        ),
        CandidateEntry(
          candidate: const WhisperCppOpenClCandidate(),
          modelSizes: legacySizes,
          models: models,
        ),
      ],
    );
  }
}
