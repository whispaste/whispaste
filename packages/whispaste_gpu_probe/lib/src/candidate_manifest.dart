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

import 'const_me_candidate.dart';
import 'onnx_direct_ml_candidate.dart';
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
// ONNX model registry
// ---------------------------------------------------------------------------

/// The model sizes the ONNX DirectML family is probed across.
///
/// ONNX Whisper model identifiers follow the same naming convention as the
/// GGML models so the VRAM gate keys are compatible.
const String onnxModelSizeSmall = 'whisper-small';
const String onnxModelSizeMedium = 'whisper-medium';

/// [ModelManifest] for Whisper-ONNX models.
///
/// Points to the Microsoft-hosted ONNX model files on Hugging Face.
/// The medium model carries the known `887A0006` crash risk on Kepler with
/// DirectML in maintenance mode — include it deliberately so the probe can
/// observe the crash empirically.
ModelManifest onnxModelManifest() => ModelManifest(
  entries: [
    ModelEntry(
      name: onnxModelSizeSmall,
      downloadUrl: Uri.parse(
        'https://huggingface.co/microsoft/whisper-small-directml/resolve/main/whisper_small_int8.onnx',
      ),
      sha256: '',
      targetFilename: 'whisper_small_int8.onnx',
      sizeBytes: 242000000,
    ),
    ModelEntry(
      name: onnxModelSizeMedium,
      downloadUrl: Uri.parse(
        'https://huggingface.co/microsoft/whisper-medium-directml/resolve/main/whisper_medium_int8.onnx',
      ),
      sha256: '',
      targetFilename: 'whisper_medium_int8.onnx',
      sizeBytes: 769000000,
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

  /// Default production manifest with the full whisper.cpp family plus
  /// Const-me/Whisper (DirectCompute) and ONNX Runtime + DirectML.
  ///
  /// [runner] is applied to all subprocess-backed candidates; pass a
  /// custom [ProbeRunner] in tests to inject a fake launcher.
  /// [referenceTranscript] is forwarded to each candidate for WER computation.
  /// [cpuFeatures] is forwarded to the Const-me candidate for its CPU
  /// pre-flight check. In production, populate from a platform-specific
  /// detection call. Defaults to an empty set (all CPU checks will skip).
  factory CandidateManifest.defaults({
    ProbeRunner runner = const ProbeRunner(),
    String? referenceTranscript,
    CpuFeatureSet cpuFeatures = const {},
  }) {
    final models = defaultModelManifest();
    final onnxModels = onnxModelManifest();

    // The GPU/CPU backends are probed across the full model-size set.
    final fullSizes = {modelSizeSmall, modelSizeMedium, modelSizeLargeTurbo};

    // The legacy OpenCL/CLBlast build only targets the smaller models.
    final legacySizes = {modelSizeSmall, modelSizeMedium};

    // Const-me is probed across small + medium (medium = hybrid model with
    // stricter CPU requirements; large is not supported by Const-me/Whisper).
    final constMeSizes = {modelSizeSmall, modelSizeMedium};

    // ONNX DirectML is probed across small + medium.
    // The medium model intentionally includes the known 887A0006 crash risk
    // so the probe can observe it empirically.
    final onnxSizes = {onnxModelSizeSmall, onnxModelSizeMedium};

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
        // Const-me/Whisper — DirectCompute (Direct3D 11).
        // Each size needs its own candidate instance because the CPU
        // pre-flight check is per-model-size (medium = hybrid requirements).
        ...constMeSizes.map(
          (size) => CandidateEntry(
            candidate: constMeDirectComputeCandidate(
              modelSizeKey: size,
              cpuFeatures: cpuFeatures,
              runner: runner,
              referenceTranscript: referenceTranscript,
            ),
            modelSizes: {size},
            models: models,
          ),
        ),
        // ONNX Runtime + DirectML — Whisper-ONNX models.
        // Probed across small + medium; medium intentionally included to
        // surface the 887A0006 crash empirically.
        CandidateEntry(
          candidate: onnxDirectMlCandidate(
            runner: runner,
            referenceTranscript: referenceTranscript,
          ),
          modelSizes: onnxSizes,
          models: onnxModels,
        ),
      ],
    );
  }
}
