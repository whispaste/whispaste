/// The in-process whisper.cpp engine seam.
///
/// Analogous to the [ProcessRunner] seam (`process_runner.dart`): a narrow,
/// Riverpod-injectable interface so [SttServerStateNotifier] can — in a later
/// slice (Issue 03) — drive transcription through a bundled `libwhisper` via
/// `dart:ffi` instead of the whisper-server subprocess + HTTP. This slice only
/// introduces the seam; it is not yet wired into any production path.
///
/// The contract mirrors the existing `transcribeBytes(wavBytes)` shape: the
/// engine takes raw WAV bytes and decodes them to 16 kHz mono float32 PCM
/// internally (`pcm_wav_codec.dart`), so callers never touch PCM.
library;

/// Which compute backend the loaded library is using.
///
/// Selected from hardware detection (`gpuInfoProvider`) via
/// [whisperBackendFromName]. The actual acceleration is provided by the bundled
/// `libwhisper` variant (Issue 11); this enum records which backend was chosen.
enum WhisperBackend { cpu, metal, cuda, vulkan }

/// Maps a [GpuInfo.optimalBackend] value (`'cuda'`/`'metal'`/`'vulkan'`/`'cpu'`)
/// to the engine's [WhisperBackend].
///
/// Any unknown or absent value falls back to [WhisperBackend.cpu] — the safe
/// default when no compatible GPU is detected.
WhisperBackend whisperBackendFromName(String? optimalBackend) {
  switch (optimalBackend) {
    case 'cuda':
      return WhisperBackend.cuda;
    case 'metal':
      return WhisperBackend.metal;
    case 'vulkan':
      return WhisperBackend.vulkan;
    default:
      return WhisperBackend.cpu;
  }
}

/// Readiness/backend snapshot for a [WhisperEngine].
class WhisperEngineStatus {
  const WhisperEngineStatus({
    required this.isLoaded,
    this.backend = WhisperBackend.cpu,
    this.errorMessage,
  });

  /// Whether a model is loaded and the engine can [WhisperEngine.transcribe].
  final bool isLoaded;

  /// The compute backend in use (Default/CPU in this slice — see Issue 04).
  final WhisperBackend backend;

  /// The last load/transcribe failure, or `null` if none.
  final String? errorMessage;
}

/// In-process speech-to-text engine over a bundled `libwhisper`.
abstract class WhisperEngine {
  /// Current readiness/backend snapshot.
  WhisperEngineStatus get status;

  /// Loads the GGML model at [modelPath] (opening the native library on first
  /// use). Throws on failure.
  Future<void> load({required String modelPath});

  /// Transcribes WhisPaste's canonical 16 kHz mono 16-bit PCM WAV [wavBytes]
  /// and returns the joined transcript.
  ///
  /// [language] is a whisper language code (e.g. `'en'`, `'de'`); `null` lets
  /// whisper auto-detect. Throws a [StateError] if called before [load].
  Future<String> transcribe(List<int> wavBytes, {String? language});

  /// Frees the native context and model. Safe to call when not loaded.
  Future<void> unload();
}
