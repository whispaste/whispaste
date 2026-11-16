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

import '../tail_confidence.dart' show TailConfidenceSample;

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
/// - [gpuBackendLost] The GPU backend refused the compute graph because it is
///               in a sticky error state (ggml-metal: a command buffer failed
///               earlier, e.g. during a system-wide GPU restart). Every later
///               decode on the same context fails the same way; only
///               recreating the context (unload + load) recovers it, so the
///               notifier rebuilds the engine once and then degrades to CPU.
/// - [oom]       GPU out-of-memory. Soft-recoverable via the orchestrator's
///               `OomRecoveryHandler` (smaller model / cloud), not a CPU retry.
/// - [timeout]   The transcription hung past the stuck-guard budget.
/// - [transient] A one-off, retryable failure (generic `whisper_full` non-zero
///               return, transient allocation hiccup).
/// - [other]     Anything else — surfaced, not retried.
enum WhisperFailureKind {
  gpuCrash,
  gpuBackendLost,
  oom,
  timeout,
  transient,
  other,
}

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

/// Applies the guard rule to a requested backend (Befund 28, Maintainer
/// decision 10a, 2026-10-25).
///
/// Every GPU backend (CUDA, Vulkan, Metal) initialises vendor code inside
/// `whisper_init_from_file_with_params`. A C++ exception from there only
/// becomes a CPU fallback when `wp_ffi_guard` wraps the call, and that needs
/// a guard built against the bundled `whisper.h` struct layouts. Without one
/// ([guardUsable] false) only the CPU backend is allowed. Metal is included
/// on purpose: the same guard is bundled on macOS, so the rule costs nothing
/// there while the guard is intact, and it keeps one rule for all platforms.
/// CPU is never gated, so the CPU fallback chain stays available.
WhisperBackend backendAllowedByGuard(
  WhisperBackend requested, {
  required bool guardUsable,
}) {
  if (guardUsable || requested == WhisperBackend.cpu) return requested;
  return WhisperBackend.cpu;
}

/// Readiness/backend snapshot for a [WhisperEngine].
class WhisperEngineStatus {
  const WhisperEngineStatus({
    required this.isLoaded,
    this.backend = WhisperBackend.cpu,
    this.errorMessage,
    this.cpuFeatures,
    this.gpuDevice,
  });

  /// Whether a model is loaded and the engine can [WhisperEngine.transcribe].
  final bool isLoaded;

  /// The compute backend of this engine. `WhisperFfiEngine` confirms it
  /// against ggml's device registry on load (`_confirmBackend`). The app's
  /// `WhisperIsolateEngine` reports its configured backend here, before and
  /// after a load: the GPU probe and the crash marker key their records on
  /// it, and that key must not change between a load and its retry. On an
  /// NVIDIA card without the CUDA pack that is `cuda` while the model runs on
  /// `Vulkan0` (#1666). Reports and diagnostics use [deviceBackend].
  final WhisperBackend backend;

  /// The backend of the device the model actually runs on: derived from
  /// [gpuDevice] when there is one ([backendForDevice]), else [backend].
  WhisperBackend get deviceBackend => backendForDevice(gpuDevice, backend);

  /// The last load/transcribe failure, or `null` if none.
  final String? errorMessage;

  /// ISA features of the CPU backend ggml actually loaded (e.g.
  /// `AVX AVX2 F16C FMA BMI2`), which identifies the picked
  /// `ggml-cpu-<level>` variant — see [cpuBackendFeaturesFromSystemInfo].
  /// `null` before the first load or when the library does not report it.
  final String? cpuFeatures;

  /// Name of the ggml GPU device whisper.cpp runs on (e.g. `CUDA0`,
  /// `Vulkan0`, `MTL0`): the first GPU/iGPU device in ggml's registry, which
  /// is the one `whisper_backend_init_gpu` picks for `gpu_device = 0`.
  /// Backends register in `ggml_backend_load_all_from_path` order, so an
  /// optional `ggml-cuda` module next to libwhisper wins over Vulkan.
  /// `null` on CPU or before the first load.
  final String? gpuDevice;
}

/// Backend that actually runs on the registry device [deviceName] (as chosen
/// by `pickGpuDeviceIndex`). The requested backend is only a guess: with CUDA
/// requested but no CUDA device registered, whisper.cpp runs on a Vulkan
/// device, and the status, diagnostics and crash recovery must say so.
/// Falls back to [requested] for unknown or missing names.
WhisperBackend backendForDevice(String? deviceName, WhisperBackend requested) {
  final name = deviceName ?? '';
  if (name.startsWith('CUDA')) return WhisperBackend.cuda;
  if (name.startsWith('Vulkan')) return WhisperBackend.vulkan;
  if (name.startsWith('MTL')) return WhisperBackend.metal;
  return requested;
}

/// Extracts the CPU backend's feature list from whisper.cpp's
/// `whisper_print_system_info()` string, formatted as
/// `WHISPER : COREML = 0 | … | CPU : SSE3 = 1 | AVX2 = 1 | … |` (one
/// `<registry> : ` prefix per backend that reports features).
///
/// The CPU backend reports the instruction sets it was *compiled* for, so
/// with `-DGGML_CPU_ALL_VARIANTS=ON` this names the variant ggml picked for
/// this machine (`AVX2 … BMI2` = haswell, `… AVX512 …` = skylakex+, only
/// `SSE3 SSSE3` = the x64 baseline). Disabled (`= 0`) entries are dropped;
/// non-boolean values are kept as `NAME=value`. Returns `null` when the
/// string has no CPU section.
String? cpuBackendFeaturesFromSystemInfo(String systemInfo) {
  final features = <String>[];
  String? registry;
  for (final raw in systemInfo.split('|')) {
    var token = raw.trim();
    if (token.isEmpty) continue;
    final regSep = token.indexOf(' : ');
    if (regSep >= 0) {
      registry = token.substring(0, regSep).trim();
      token = token.substring(regSep + 3).trim();
    }
    if (registry != 'CPU') continue;
    final eq = token.indexOf('=');
    if (eq < 0) continue;
    final name = token.substring(0, eq).trim();
    final value = token.substring(eq + 1).trim();
    if (name.isEmpty || value == '0') continue;
    features.add(value == '1' ? name : '$name=$value');
  }
  return features.isEmpty ? null : features.join(' ');
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

/// Optional capability: an engine that can report the exact whisper.cpp
/// token count of an arbitrary string, using the loaded model's real
/// tokenizer (`whisper_tokenize`) rather than a char-length approximation.
///
/// Exists to fix a silent-data-loss bug: whisper.cpp truncates the
/// *tokenized* `initial_prompt` to a small internal budget (`n_max_text_ctx`
/// capped by half the context window — ~63 tokens for WhisPaste's
/// configuration) independently of, and far below, any char-length limit the
/// app validates against. [SttServerStateNotifier._resolveEffectivePrompt]
/// uses this to truncate the combined custom-vocabulary + rolling-context
/// prompt to the real token budget itself — front-anchored, preferring to
/// keep the user's custom vocabulary over older rolling context — instead of
/// letting whisper.cpp silently drop the front of the prompt with no signal
/// anywhere in the app.
///
/// A separate `implements`-only interface for the same reason as
/// [PartialTranscriptSource]: not every [WhisperEngine] test double needs a
/// real tokenizer, and this is genuinely optional — an engine without it
/// simply keeps relying on the (coarser, safety-margined) char-based
/// pre-flight limit in `InferenceRequestValidator`. Consumers probe with
/// `engine is PromptTokenCounter`.
abstract class PromptTokenCounter {
  /// Returns the exact number of whisper.cpp tokens [text] would tokenize
  /// to, using the currently loaded model. Throws [StateError] if no model
  /// is loaded yet.
  Future<int> countPromptTokens(String text);
}

/// Optional capability: an engine that reports the language its last
/// [WhisperEngine.transcribe] decoded in, as a whisper code such as `de`.
/// `null` means unknown (older library builds, a failed decode). Kept out of
/// [WhisperEngine] for the same reason as [PartialTranscriptSource].
abstract class DetectedLanguageSource {
  String? get lastDetectedLanguage;
}

/// Optional capability (#573): token confidence at the end of the last
/// transcription, for the shadow-mode protocol. Kept out of [WhisperEngine]
/// for the same reason as [DetectedLanguageSource].
abstract class TailConfidenceSource {
  /// `null` when the engine could not measure (older library build, no text).
  TailConfidenceSample? get lastTailConfidence;
}

/// Optional capability (IMP-PROG-2): an engine that reports decode progress
/// while [transcribeWithProgress] runs. [onProgress] receives fractions in
/// `0..1`, monotone within one call, and is never called after the returned
/// future completes. Engines without it stay indeterminate in the UI.
///
/// Kept out of [WhisperEngine] like [PartialTranscriptSource]: test doubles
/// implement [WhisperEngine] directly and must not all grow this method.
abstract class TranscriptionProgressSource {
  Future<String> transcribeWithProgress(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
    void Function(double fraction)? onProgress,
  });
}

/// Optional capability (#1665): an engine that reads the recording itself
/// from its WAV file, one decode window at a time, instead of taking all of
/// its bytes. The isolate engine then sends only the path to its worker; a
/// 60-minute recording (110 MB) is no longer copied into the worker. The
/// transcript is the one [WhisperEngine.transcribe] gives for the file's
/// bytes: both read the PCM after the 44-byte header and ignore the header's
/// size fields.
///
/// The file must stay in place until the call returns. A file that cannot be
/// read fails the call with [WhisperFailureKind.other]
/// (`wav_file_unreadable`). Kept out of [WhisperEngine] like
/// [TranscriptionProgressSource]: test doubles implement [WhisperEngine]
/// directly, and a caller without this capability sends the bytes.
abstract class WavFileDecode {
  Future<String> transcribeFile(
    String wavPath, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
    void Function(double fraction)? onProgress,
  });
}

/// Message prefix of the [WhisperEngineException] a [WavFileDecode] call ends
/// with when the WAV file cannot be read.
const String kWhisperWavFileUnreadable = 'wav_file_unreadable';

/// Optional capability (#1639): an engine whose running final decode can be
/// cancelled. [abortDecode] raises a native abort flag; whisper.cpp polls it
/// after the encoder and between decoder steps, and a pause-chunked decode
/// stops before its next chunk. The running call then fails with
/// [WhisperFailureKind.timeout] (or returns its text if it was already past
/// the last check). Safe to call from the isolate that owns the engine while
/// the decode runs on another thread or isolate; a call without a running
/// decode does nothing.
///
/// Kept out of [WhisperEngine] like [TranscriptionProgressSource]: test
/// doubles implement [WhisperEngine] directly. An engine without it cannot be
/// interrupted, and a budget overrun keeps it busy until it returns.
abstract class AbortableDecode {
  void abortDecode();
}

/// Message of the [WhisperEngineException] an aborted decode ends with.
const String kWhisperDecodeAborted = 'whisper_decode_aborted';
