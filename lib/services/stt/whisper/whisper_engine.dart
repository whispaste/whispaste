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

import 'dart:typed_data' show Float32List;

/// Distinguishable failure class an in-process [WhisperEngine] can signal to
/// the notifier at transcription time.
///
/// Replaces the subprocess-era exit-code taxonomy ([`SttExitKind`]) for the
/// FFI engine: with no child process there is no exit code, so the engine
/// raises a typed [WhisperEngineException] carrying one of these kinds instead.
/// The notifier's resilience wrapper reacts differently per kind (CPU-fallback,
/// OOM-recovery trigger, stuck-guard, retry).
///
/// - [gpuCrash]  A GPU backend (Metal/CUDA/Vulkan) fault the app can recover
///               from by degrading to CPU. NB: only a *catchable* fault — a
///               genuine native segfault has no subprocess isolation and is
///               validated on real hardware later (Issues 12–14), not here.
/// - [oom]       GPU out-of-memory. Soft-recoverable via the orchestrator's
///               `OomRecoveryHandler` (smaller model / cloud), not a CPU retry.
/// - [timeout]   The transcription hung past the stuck-guard budget.
/// - [transient] A one-off, retryable failure (generic `whisper_full` non-zero
///               return, transient allocation hiccup).
/// - [other]     Anything else — surfaced, not retried.
enum WhisperFailureKind { gpuCrash, oom, timeout, transient, other }

/// A distinguishable, catchable failure raised by a [WhisperEngine] during
/// [WhisperEngine.transcribe].
///
/// Carries a [kind] so the notifier can pick the right resilience path without
/// parsing message strings. Implements [Exception] (not [Error]) so it flows
/// through the transcription error path rather than being treated as a
/// programming fault.
class WhisperEngineException implements Exception {
  const WhisperEngineException(this.kind, this.message);

  /// The distinguishable failure class.
  final WhisperFailureKind kind;

  /// Human-readable detail. For [WhisperFailureKind.oom] the message contains
  /// the `stt_cuda_oom` token the orchestrator's OOM-recovery path keys on.
  final String message;

  @override
  String toString() => 'WhisperEngineException(${kind.name}): $message';
}

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

  /// The compute backend actually in use, confirmed against ggml's device
  /// registry post-load where the bundled library exports it (see
  /// `WhisperFfiEngine._confirmBackend`) — not merely the pre-load request.
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
  ///
  /// [vadModelPath], if given and it exists on disk, resolves the bundled
  /// Silero-VAD ggml model — see [transcribe]'s `vadEnabled`. A missing or
  /// omitted path is not an error: VAD simply stays unavailable this
  /// session (`vadEnabled` becomes a no-op) rather than failing [load].
  Future<void> load({required String modelPath, String? vadModelPath});

  /// Transcribes WhisPaste's canonical 16 kHz mono 16-bit PCM WAV [wavBytes]
  /// and returns the joined transcript.
  ///
  /// [language] is a whisper language code (e.g. `'en'`, `'de'`); `null` lets
  /// whisper auto-detect. [prompt] biases decoding towards custom vocabulary
  /// / rolling context (whisper's `initial_prompt`); `null` or empty means no
  /// bias. [vadEnabled] (`SttSettings.vadEnabled`, user-toggleable) runs
  /// whisper.cpp's built-in VAD pre-pass so long silence/noise tails never
  /// reach the decoder — the mitigation for Whisper's documented
  /// trailing-silence hallucination class (e.g. fabricated "Vielen Dank."
  /// closings). No-op if [load] did not resolve a VAD model. Throws a
  /// [StateError] if called before [load].
  ///
  /// [reducedThreads] shrinks this call's own CPU footprint (see
  /// `WhisperFfiEngine._decodeOnce`'s "Audio-capture protection" comment) —
  /// set by `SttServerStateNotifier` when a new recording is actively
  /// capturing while this call decodes a previous one, so this inference
  /// never competes at full core count against a live recording for the
  /// same CPU.
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  });

  /// Frees the native context and model. Safe to call when not loaded.
  Future<void> unload();
}

/// Optional capability: an engine that can report the transcript-so-far while
/// [WhisperEngine.transcribe] is still decoding (ticket 11, live-transcript
/// overlay option).
///
/// A separate, `implements`-only interface rather than a new member on
/// [WhisperEngine] itself on purpose: several unrelated test doubles
/// implement [WhisperEngine] directly (`implements WhisperEngine` copies
/// only the interface, not [WhisperFfiEngine]'s bodies), and this feature is
/// genuinely optional per the PRD ("for engines without partial results, the
/// waveform display stays unchanged — do NOT fake a live feeling
/// artificially"). Consumers probe for it with `engine is
/// PartialTranscriptSource` instead of every [WhisperEngine] having to grow a
/// no-op implementation.
abstract class PartialTranscriptSource {
  /// Broadcast stream of the transcript accumulated so far for the
  /// in-flight [WhisperEngine.transcribe] call.
  ///
  /// Emits the full text-so-far (not a delta) once per newly completed
  /// whisper.cpp segment — mirrors how [WhisperEngine.transcribe] itself
  /// joins segments into the final result. Never emits outside an in-flight
  /// [WhisperEngine.transcribe] call.
  Stream<String> get partialTranscript;
}

/// Optional capability: an engine that can decode short PCM windows taken
/// from an ACTIVE recording — i.e. before it has even stopped — via a
/// separate, state-based decode path (live-transcript-streaming ticket).
///
/// Distinct from [PartialTranscriptSource], which only surfaces segments of
/// the POST-recording batch [WhisperEngine.transcribe] call and therefore
/// never emits anything while a recording is still in progress. This
/// interface is what actually powers "real" streaming: the caller feeds it
/// a sliding window of raw PCM while the user is still speaking, and gets
/// back a preview transcript for that window.
///
/// A separate `implements`-only interface for the same reason as
/// [PartialTranscriptSource]: several test doubles implement [WhisperEngine]
/// directly and this capability is genuinely optional per the feature's
/// architecture — a caller probes with `engine is LivePreviewEngine` instead
/// of every [WhisperEngine] needing a no-op implementation.
abstract class LivePreviewEngine {
  /// Allocates a decode state dedicated to live-preview decodes, separate
  /// from the context's own default state (used by
  /// [WhisperEngine.transcribe]) — so a preview decode never interferes
  /// with, or is interfered with by, the final batch decode. Safe to call
  /// repeatedly; a second call while a preview state is already open is a
  /// no-op. Throws [StateError] if no model is loaded yet.
  Future<void> startLivePreview();

  /// Decodes [samples] (16 kHz mono float32) against the dedicated preview
  /// state and returns the resulting text — never touches [WhisperEngine.
  /// transcribe]'s own state/results. Throws [StateError] if
  /// [startLivePreview] was not called first (or has since been stopped).
  Future<String> decodeLivePreview(
    Float32List samples, {
    String? language,
    String? prompt,
  });

  /// Frees the dedicated preview decode state. Safe to call when none is
  /// open (including after [startLivePreview] was never called).
  Future<void> stopLivePreview();
}
