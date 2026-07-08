/// Riverpod notifier that composes all STT sub-modules.
///
/// Re-exports [SttStatus] and [SttServerState] so external consumers can
/// import from this single file instead of hunting through the subsystem.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart'
    show Breadcrumb, Sentry, SentryLevel;

import '../../core/config/settings_provider.dart';
import '../../core/config/whisper_languages.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';
import '../../core/recording/recording_state.dart' show SttServerState;
import '../hardware_info_service.dart' as hw;
import '../model_download_service.dart';
import '../path_service.dart';
import 'inference_client_rejected.dart';
import 'inference_request_validator.dart';
import 'stt_benchmark.dart' show SttBenchmark;
import 'wav_header_repair.dart';
import 'whisper/whisper_engine.dart';
import 'whisper/whisper_ffi_engine.dart';

// Re-export for external consumers.
export '../../core/recording/recording_state.dart' show SttServerState;
export 'server_binary_recovery.dart'
    show
        RecoveryExhausted,
        RecoveryExhaustedKind,
        RecoveryFellBackToCpu,
        RecoveryReason,
        RecoveryResult,
        RecoveryRetried,
        ServerBinaryRecovery,
        nextVariant;
export 'stt_exit_classifier.dart' show SttExitKind, classifySttExitCode;
export 'stt_gpu_fallback_policy.dart' show SttGpuFallbackPolicy;
export 'stt_providers.dart'
    show
        SttStartupHeartbeatConfig,
        processRunnerProvider,
        serverBinaryRecoveryProvider,
        sttHttpClientProvider,
        sttStartupHeartbeatConfigProvider;

// ---------------------------------------------------------------------------
// SttStatus (local copy so stt_bundle.dart can re-export without coupling
// to the legacy stt_service.dart)
// ---------------------------------------------------------------------------

/// Immutable snapshot of the STT service.
class SttStatus {
  const SttStatus({
    this.serverState = SttServerState.stopped,
    this.port = 0,
    this.modelId = '',
    this.errorMessage,
    this.startingSince,
    this.isBenchmarking = false,
    this.benchmarkingTier,
    this.cpuFallbackActive = false,
  });

  final SttServerState serverState;
  final int port;
  final String modelId;
  final String? errorMessage;

  /// When the server entered the [SttServerState.starting] state.
  final DateTime? startingSince;

  /// Whether a benchmark is currently running for this model.
  final bool isBenchmarking;

  /// Which tier is currently being benchmarked, if any.
  final QualityTier? benchmarkingTier;

  /// True when the GPU crashed and the server restarted on CPU automatically.
  final bool cpuFallbackActive;

  bool get isReady => serverState == SttServerState.ready;

  String get endpoint => 'http://127.0.0.1:$port';

  SttStatus copyWith({
    SttServerState? serverState,
    int? port,
    String? modelId,
    String? errorMessage,
    DateTime? startingSince,
    bool? isBenchmarking,
    QualityTier? benchmarkingTier,
    bool clearBenchmarkingTier = false,
    bool? cpuFallbackActive,
  }) {
    return SttStatus(
      serverState: serverState ?? this.serverState,
      port: port ?? this.port,
      modelId: modelId ?? this.modelId,
      errorMessage: errorMessage ?? this.errorMessage,
      startingSince: startingSince ?? this.startingSince,
      isBenchmarking: isBenchmarking ?? this.isBenchmarking,
      benchmarkingTier: clearBenchmarkingTier
          ? null
          : (benchmarkingTier ?? this.benchmarkingTier),
      cpuFallbackActive: cpuFallbackActive ?? this.cpuFallbackActive,
    );
  }

  @override
  String toString() =>
      'SttStatus($serverState, port=$port, model=$modelId, '
      'benchmarking=$isBenchmarking, cpuFallback=$cpuFallbackActive)';
}

// ---------------------------------------------------------------------------
// Pure helpers (top-level, testable)
// ---------------------------------------------------------------------------

/// Returns `true` when [fileSizeBytes] is suspiciously small for a valid GGML
/// model, indicating a truncated or failed download.
bool isSttModelFileTooSmall(
  int fileSizeBytes, {
  int minModelBytes = 10 * 1024 * 1024,
}) => fileSizeBytes < minModelBytes;

// ---------------------------------------------------------------------------
// SttServerStateNotifier
// ---------------------------------------------------------------------------

/// Riverpod [Notifier] that drives the in-process [WhisperEngine] behind a
/// single [SttStatus] surface.
///
/// This is the public entry point for the STT subsystem. All callers use
/// [localSttBundleProvider] since issue 15.
///
/// The engine seam replaced the former `whisper-server` subprocess + HTTP
/// transport (Issue 03). The subprocess-era GPU-DLL-gate, CUDA-OOM/exit-code
/// classification and `ServerBinaryRecovery` machinery had no equivalent
/// against an in-process engine and were removed; their production files
/// stay in the repo for Issue 07/08 to retire. Real backend selection
/// (Metal/CUDA/Vulkan) is Issue 04; OOM/retry resilience against FFI error
/// codes is Issue 05.
class SttServerStateNotifier extends Notifier<SttStatus> {
  static final _log = AppLogger('SttServerState');

  /// Pre-flight whitelist: the full 99-language catalog of the bundled
  /// multilingual Whisper models ([whisperLanguages]). `'auto'` bypasses
  /// the whitelist inside the validator. Until June 2026 this was a
  /// hard-coded en/de/fr/es subset, which wrongly rejected every other
  /// language the models support (store review: Russian).
  static final Set<String> _whisperSupportedLanguages = whisperLanguageCodes;

  /// Upper bound on the combined `vocab + lastPrompt` string used for
  /// pre-flight validation. The engine seam ([WhisperEngine.transcribe])
  /// has no prompt/vocab parameter yet, so [_resolveEffectivePrompt]'s
  /// result is validated but not forwarded — see the `decisions:` note in
  /// this issue's Evidence block.
  static const int _promptCharLimit = 1024;

  String? _activeModel;
  Timer? _idleTimer;
  String? _lastPrompt;
  DateTime? _lastPromptTime;
  static const _promptExpiry = Duration(minutes: 10);
  bool _idleExtended = false;
  bool _isRecordingActive = false;
  Completer<void>? _startCompleter;
  final Set<String> _modelLoadFailedIds = {};
  Timer? _modelChangeDebounce;

  // Nullable rather than `late final`: [FakeSttService]-style test doubles
  // override [build] entirely (skipping the assignment below) while
  // inheriting [stop] unmodified — a `late final` throws
  // `LateInitializationError` from `stop()` in that shape. Real callers
  // always go through [build] first (Riverpod builds before any method is
  // reachable), so `_engine!` is safe at every other call site.
  WhisperEngine? _engine;

  @override
  SttStatus build() {
    _engine = ref.read(whisperEngineProvider);

    ref.onDispose(() {
      _idleTimer?.cancel();
      _idleTimer = null;
      _modelChangeDebounce?.cancel();
      _modelChangeDebounce = null;
      unawaited(_engine?.unload() ?? Future<void>.value());
      _activeModel = null;
      _lastPrompt = null;
      _lastPromptTime = null;
    });

    ref.listen(settingsProvider, (prev, next) {
      final prevSettings = prev?.value;
      final nextSettings = next.value;
      if (prevSettings == null || nextSettings == null) return;

      if (prevSettings.gpuAcceleration != nextSettings.gpuAcceleration ||
          prevSettings.effectiveModelId != nextSettings.effectiveModelId) {
        _modelLoadFailedIds.remove(prevSettings.effectiveModelId);
      }

      final prevModel = prevSettings.effectiveModelId;
      final nextModel = nextSettings.effectiveModelId;
      if (prevModel == nextModel) return;
      if (!nextSettings.sttProviderType.isLocal) return;

      _debouncedPrewarmOnModelChange(nextModel);
    });

    ref.listen(modelDownloadProvider, (prev, next) {
      if (prev == null) return;
      final newlyDownloaded = next.downloadedModels.difference(
        prev.downloadedModels,
      );
      for (final id in newlyDownloaded) {
        _modelLoadFailedIds.remove(id);
      }
    });

    return const SttStatus();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> ensureRunning() async {
    if (_startCompleter != null) {
      return _startCompleter!.future;
    }

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final modelId = settings.effectiveModelId;

    if (_activeModel != null && _activeModel != modelId) {
      _log.info('STT model changed ($_activeModel → $modelId), restarting');
      stop();
    }

    if (state.isReady && state.modelId == modelId) {
      _resetIdleTimer();
      _log.debug('STT engine already loaded (warm) for model $modelId');
      return;
    }

    if (_modelLoadFailedIds.contains(modelId)) {
      _fail(
        'STT model file is corrupted. '
        'Please re-download the model in Settings.',
      );
      return;
    }

    if (state.serverState != SttServerState.stopped) {
      stop();
    }

    _startCompleter = Completer<void>();
    try {
      await _start(modelId: modelId);
      _startCompleter?.complete();
    } on Exception catch (e) {
      _startCompleter?.completeError(e);
      rethrow;
    } finally {
      _startCompleter = null;
    }
  }

  Future<void> prewarm() async {
    try {
      await ensureRunning();
      _log.info('STT model pre-warmed (${state.modelId})');
    } on Exception catch (e) {
      _log.debug('Pre-warm skipped: $e');
    }
  }

  Future<void> runBenchmark() async {
    final currentModelId = state.modelId;
    if (currentModelId.isEmpty) {
      _log.debug('Cannot run benchmark: no model is currently active');
      return;
    }
    stop();
    try {
      await _start(modelId: currentModelId);
      _log.info('Re-benchmark completed for $currentModelId');
    } on Exception catch (e) {
      _log.debug('Re-benchmark failed: $e');
    }
  }

  void notifyRecordingStarted() {
    _isRecordingActive = true;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void notifyTranscriptionCompleted() {
    _isRecordingActive = false;
    _idleExtended = false;
    _resetIdleTimer(extendAfterTranscription: true);
  }

  void notifyRecordingStopped() {
    _isRecordingActive = false;
    _resetIdleTimer();
  }

  Future<String> transcribe(String wavFilePath, {String? language}) async {
    final file = File(wavFilePath);
    if (!file.existsSync()) {
      throw Exception('WAV file not found: $wavFilePath');
    }
    return transcribeBytes(await file.readAsBytes(), language: language);
  }

  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    if (!state.isReady) {
      throw StateError('STT server is not running');
    }

    _resetIdleTimer();
    final lang = language ?? 'auto';

    _log.info(
      'STT inference: model=${state.modelId} '
      'wavBytes=${wavBytes.length} lang=$lang',
    );
    final stopwatch = Stopwatch()..start();

    // Materialize the payload as a [Uint8List] once so both the pre-flight
    // validator and the engine call use the same byte view.
    final wavView = wavBytes is Uint8List
        ? wavBytes
        : Uint8List.fromList(wavBytes);

    // Derive audio duration (16 kHz mono 16-bit + 44-byte header). Used by
    // breadcrumb extras and the validator context. Clamped at zero so the
    // empty-WAV reject path does not produce a negative value.
    final audioDurationMs = wavBytes.length > 44
        ? ((wavBytes.length - 44) / 32000 * 1000).round()
        : 0;

    final settings = ref.read(settingsProvider).value;
    final vocab = settings?.customVocabulary.trim() ?? '';
    // Resolved for pre-flight validation only — [WhisperEngine.transcribe]
    // has no prompt/vocab parameter yet (Issue 02 seam), so the value is
    // validated but not forwarded to the engine. See this issue's
    // `decisions:` note.
    final effectivePrompt = _resolveEffectivePrompt(vocab);

    // ── Pre-flight validation ─────────────────────────────────────────────
    // Reject obvious-garbage requests before they reach the engine. Sentry
    // sees one breadcrumb in category `stt` but never a captureError — these
    // are user-input issues, not crashes.
    final validation = InferenceRequestValidator.validate(
      wavBytes: wavView,
      language: lang,
      prompt: effectivePrompt,
      supportedLanguages: _whisperSupportedLanguages,
      promptCharLimit: _promptCharLimit,
    );
    if (validation is ValidationReject) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'Inference request rejected pre-flight',
          category: 'stt',
          level: SentryLevel.warning,
          data: <String, dynamic>{
            'reject_reason': validation.reason.name,
            'wav_size_bytes': wavBytes.length,
            'audio_duration_ms': audioDurationMs,
            'language': lang,
          },
        ),
      );
      _log.warning(
        'STT inference rejected pre-flight: reason=${validation.reason.name} '
        'key=${validation.userMessageKey} wavBytes=${wavBytes.length}',
      );
      throw InferenceClientRejected(validation.userMessageKey);
    }

    // ── Pre-send WAV header repair (FLUTTER_WHISPASTE-7X) ─────────────────
    // A recording whose header patch never ran ships valid PCM data behind
    // zeroed RIFF/data size fields — the engine's WAV decoder rejects that
    // container. The sizes are derivable from the byte length, so repair
    // them instead of losing the user's dictation.
    final payload = _repairWavIfNeeded(
      wavView,
      audioDurationMs,
      wavBytes.length,
    );

    final String rawText;
    try {
      rawText = await _engine!.transcribe(payload, language: lang);
    } catch (e) {
      stopwatch.stop();
      // Issue 05 owns FFI-specific error classification + Sentry capture
      // (the "stt_inference_capture_test.dart-Äquivalent" its own AC text
      // names) — this slice just surfaces the failure to the caller.
      _log.warning('STT inference failed: $e');
      throw Exception('STT inference failed: $e');
    }

    stopwatch.stop();
    _log.info(
      'STT inference response: duration=${stopwatch.elapsedMilliseconds}ms '
      'textLen=${rawText.length}',
    );

    var text = rawText.trim();
    text = _stripNonSpeechMarkers(text);
    text = _collapseRepetitions(text);

    if (text.isNotEmpty) {
      _lastPrompt = text.length > 200
          ? text.substring(text.length - 200)
          : text;
      _lastPromptTime = DateTime.now();
    }

    return text;
  }

  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = null;
    unawaited(_engine?.unload() ?? Future<void>.value());
    _activeModel = null;
    _lastPrompt = null;
    _lastPromptTime = null;
    _idleExtended = false;
    _isRecordingActive = false;
    _transition(const SttStatus());
  }

  // ---------------------------------------------------------------------------
  // transcribeBytes helpers
  // ---------------------------------------------------------------------------

  /// Builds the effective prompt from the custom vocabulary setting and the
  /// rolling context window, updating [_lastPrompt]/[_lastPromptTime] on
  /// expiry.  Extracted from [transcribeBytes] to lower its cyclomatic count.
  String? _resolveEffectivePrompt(String vocab) {
    String? promptValue;
    if (_lastPrompt != null &&
        _lastPrompt!.isNotEmpty &&
        _lastPromptTime != null &&
        DateTime.now().difference(_lastPromptTime!) < _promptExpiry) {
      promptValue = _lastPrompt!;
    } else if (_lastPrompt != null) {
      _lastPrompt = null;
      _lastPromptTime = null;
    }
    final combined = <String>[
      if (vocab.isNotEmpty) vocab,
      if (promptValue != null && promptValue.isNotEmpty) promptValue,
    ].join(' ');
    return combined.isEmpty ? null : combined;
  }

  /// Repairs zeroed WAV size fields in-memory (FLUTTER_WHISPASTE-7X) and
  /// emits a Sentry breadcrumb + warning log when a repair was needed.
  /// Returns [wavView] unmodified when no repair is required.
  Uint8List _repairWavIfNeeded(
    Uint8List wavView,
    int audioDurationMs,
    int wavBytesLength,
  ) {
    final repairedWav = repairZeroedWavSizeFields(wavView);
    if (repairedWav == null) return wavView;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'WAV size fields were zero — repaired before inference',
        category: 'stt',
        level: SentryLevel.warning,
        data: <String, dynamic>{
          'wav_size_bytes': wavBytesLength,
          'audio_duration_ms': audioDurationMs,
        },
      ),
    );
    _log.warning(
      'WAV header size fields were zero (unpatched header) — repaired '
      'in-memory before inference ($wavBytesLength bytes).',
    );
    return repairedWav;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _transition(SttStatus next) {
    // Every state mutation flows through here, so a single mounted-guard
    // covers async resumes that race the provider container shutdown
    // (test teardown, app quit, hot-reload). Without it, a completion that
    // lands after the scope is torn down throws a "Cannot use the Ref …
    // after it has been disposed" deep in async continuations and surfaces
    // as a "failed after test completion" flake on CI.
    if (!ref.mounted) return;

    final prev = state.serverState;

    if (next.serverState == SttServerState.starting &&
        next.startingSince == null) {
      next = SttStatus(
        serverState: next.serverState,
        port: next.port,
        modelId: next.modelId,
        errorMessage: next.errorMessage,
        startingSince: DateTime.now(),
      );
    }

    state = next;
    if (prev == next.serverState) return;

    final extra = StringBuffer();
    if (next.modelId.isNotEmpty) extra.write(' model=${next.modelId}');
    if (next.errorMessage != null) extra.write(' error="${next.errorMessage}"');

    _log.info('STT lifecycle: $prev → ${next.serverState}$extra');
  }

  void _resetIdleTimer({bool extendAfterTranscription = false}) {
    if (_isRecordingActive) return;

    _idleTimer?.cancel();
    _idleTimer = null;

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final baseMinutes = settings.sttIdleTimeoutMinutes;

    if (baseMinutes <= 0) return;

    var timeoutMinutes = baseMinutes;

    if (extendAfterTranscription && !_idleExtended) {
      timeoutMinutes = math.min(baseMinutes + 5, baseMinutes * 2);
      _idleExtended = true;
      _log.debug(
        'Idle timer extended: ${timeoutMinutes}min '
        '(base=${baseMinutes}min, burst=+5min)',
      );
    }

    final timeout = Duration(minutes: timeoutMinutes);
    _idleTimer = Timer(timeout, () {
      _log.info(
        'STT engine idle for ${timeout.inMinutes} min, '
        'unloading to free memory',
      );
      stop();
    });
  }

  void _debouncedPrewarmOnModelChange(String newModelId) {
    _modelChangeDebounce?.cancel();
    _modelChangeDebounce = Timer(const Duration(milliseconds: 500), () async {
      _log.info('Model changed to $newModelId, starting debounced pre-warm');

      final modelPath = sttModelPath(newModelId);
      if (modelPath == null || !await File(modelPath).exists()) {
        _log.debug('Model file not downloaded yet, skipping pre-warm');
        return;
      }

      if (state.serverState != SttServerState.stopped) stop();
      try {
        await ensureRunning();
        _log.info('Pre-warm after model change complete');
      } on Exception catch (e) {
        _log.debug('Pre-warm after model change skipped: $e');
      }
    });
  }

  /// Best-effort GPU/engine warmup so the first real dictation after a cold
  /// load doesn't pay the one-time kernel-compile/cache-fill penalty.
  /// Failures are non-fatal — mirrors the pre-cutover HTTP warmup's contract.
  Future<void> _warmupInference() async {
    final sw = Stopwatch()..start();
    try {
      final silentWav = _generateSilentWav();
      await _engine!.transcribe(silentWav);
      sw.stop();
      _log.info(
        'Engine warmup inference completed in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e) {
      sw.stop();
      _log.debug('Engine warmup skipped: $e');
    }
  }

  /// Measures the real-time factor for [modelId] against a 3 s benchmark WAV
  /// via the engine seam (previously timed over HTTP against the whisper-server
  /// subprocess). Drives the onboarding quality-tier auto-selection.
  Future<void> _runBenchmark(String modelId) async {
    final tier = tierForModel(modelId);

    if (!ref.mounted) return;

    state = state.copyWith(isBenchmarking: true, benchmarkingTier: tier);

    final sw = Stopwatch()..start();
    try {
      final benchmarkWav = SttBenchmark.generateBenchmarkWav();
      await _engine!.transcribe(benchmarkWav);
      sw.stop();

      const audioDurationMs = 3000;
      final rtf = sw.elapsedMilliseconds / audioDurationMs;

      _log.info(
        'Benchmark completed for $modelId: ${sw.elapsedMilliseconds}ms '
        '(RTF=$rtf)',
      );

      if (ref.mounted) await _storeBenchmarkResult(modelId, rtf);
    } catch (e) {
      sw.stop();
      _log.debug('Benchmark failed: $e');
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          isBenchmarking: false,
          clearBenchmarkingTier: true,
        );
      }
    }
  }

  Future<void> _storeBenchmarkResult(String modelId, double rtf) async {
    try {
      final tier = tierForModel(modelId);
      if (tier == null) return;
      if (!ref.mounted) return;

      final currentSettings = ref.read(settingsProvider).value;
      final currentRtfMap = Map<QualityTier, double>.from(
        currentSettings?.tierBenchmarkRtf ?? {},
      );
      currentRtfMap[tier] = rtf;

      final gpuInfo = await ref.read(hw.gpuInfoProvider.future);
      if (!ref.mounted) return;
      final hwId = gpuInfo.vendor == hw.GpuVendor.none
          ? 'cpu'
          : '${gpuInfo.vendor.name}_${gpuInfo.vramMB ?? 0}';

      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              tierBenchmarkRtf: currentRtfMap,
              benchmarkHardwareId: hwId,
              benchmarkTimestamp: DateTime.now(),
            ),
          );

      _log.info('Benchmark stored: $modelId → tier=$tier, RTF=$rtf');
    } catch (e) {
      _log.debug('Failed to store benchmark: $e');
    }
  }

  static Uint8List _generateSilentWav() {
    const sampleRate = 16000;
    const durationSamples = sampleRate ~/ 4;
    const bitsPerSample = 16;
    const numChannels = 1;
    const bytesPerSample = bitsPerSample ~/ 8;
    const dataSize = durationSamples * numChannels * bytesPerSample;
    const headerSize = 44;

    final buffer = Uint8List(headerSize + dataSize);
    final data = ByteData.sublistView(buffer);

    buffer[0] = 0x52;
    buffer[1] = 0x49;
    buffer[2] = 0x46;
    buffer[3] = 0x46;
    data.setUint32(4, headerSize + dataSize - 8, Endian.little);
    buffer[8] = 0x57;
    buffer[9] = 0x41;
    buffer[10] = 0x56;
    buffer[11] = 0x45;
    buffer[12] = 0x66;
    buffer[13] = 0x6D;
    buffer[14] = 0x74;
    buffer[15] = 0x20;
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, numChannels * bytesPerSample, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    buffer[36] = 0x64;
    buffer[37] = 0x61;
    buffer[38] = 0x74;
    buffer[39] = 0x61;
    data.setUint32(40, dataSize, Endian.little);

    return buffer;
  }

  Future<void> _start({required String modelId}) async {
    _transition(const SttStatus(serverState: SttServerState.starting));

    final modelPath = sttModelPath(modelId);
    if (modelPath == null) {
      _fail('Unknown STT model: $modelId');
      return;
    }

    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      _fail(
        'STT model file not found at $modelPath. '
        'Download the model first.',
      );
      return;
    }

    const minModelBytes = 10 * 1024 * 1024;
    final modelFileSize = await modelFile.length();
    if (isSttModelFileTooSmall(modelFileSize, minModelBytes: minModelBytes)) {
      // Explicit capture under the canonical `sttModelCorrupted` bucket so
      // disk-truncated / interrupted-download model files surface as their
      // own Sentry issue instead of merging into the generic auto-escalate
      // catch-all via `_log.error`. Log is downgraded to warning to avoid
      // a second event from the AppLogger pipeline.
      CrashReporter.instance?.captureError(
        message:
            'STT model file corrupted on disk '
            '($modelFileSize bytes, expected >$minModelBytes)',
        severity: 'error',
        type: 'stt_model_corrupted',
        fingerprint: const [sttModelCorrupted],
        extras: {
          'model_id': modelId,
          'model_path': modelPath,
          'file_size_bytes': modelFileSize,
          'min_required_bytes': minModelBytes,
          'platform': Platform.operatingSystem,
        },
      );
      _log.warning(
        'STT model file appears corrupted: $modelPath '
        '($modelFileSize bytes, expected >$minModelBytes). '
        'Triggering silent re-download.',
      );
      unawaited(
        modelFile.delete().catchError((Object e) {
          _log.warning('Failed to delete corrupt model file: $e');
          return modelFile;
        }),
      );
      // Mirror the pre-cutover self-heal: park in stopped, then trigger a
      // silent re-download via modelDownloadProvider.
      _transition(const SttStatus(serverState: SttServerState.stopped));
      unawaited(
        ref
            .read(modelDownloadProvider.notifier)
            .downloadModel(modelId)
            .catchError((Object e) {
              _log.warning(
                'Silent re-download of corrupt model $modelId failed: $e',
              );
            }),
      );
      return;
    }

    _log.info('Loading STT model: $modelId ($modelPath)');

    try {
      await _engine!.load(modelPath: modelPath);
    } catch (e) {
      _fail('Failed to load STT model: $e');
      return;
    }
    if (!ref.mounted) return;

    _activeModel = modelId;
    _resetIdleTimer();

    await _warmupInference();
    unawaited(_runBenchmark(modelId));

    _transition(SttStatus(serverState: SttServerState.ready, modelId: modelId));
  }

  /// Strips whisper.cpp non-speech annotations from the transcript.
  ///
  /// On silence or background noise, whisper emits bracketed sound tags
  /// instead of words — `[Musik]`, `[Music]`, `[BLANK_AUDIO]`, `[Applause]`,
  /// `[ Pause ]` and the like. These are never something the user dictated,
  /// yet they were being pasted into the active text field and saved to the
  /// history. whisper.cpp wraps these markers in square brackets, so we drop
  /// any token wholly enclosed in `[...]`. Round brackets are deliberately
  /// left untouched — a user may legitimately dictate parenthesised text,
  /// whereas square brackets effectively never occur in spoken input.
  ///
  /// If the whole transcript was nothing but such markers the result is the
  /// empty string, which the orchestrator already surfaces as
  /// `transcription_empty` instead of inserting noise.
  String _stripNonSpeechMarkers(String text) {
    if (text.isEmpty) return text;
    final stripped = text
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stripped != text) {
      _log.info('Stripped non-speech markers from transcript');
    }
    return stripped;
  }

  String _collapseRepetitions(String text) {
    if (text.length < 20) return text;

    final sentences = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      buf.writeCharCode(text.codeUnitAt(i));
      final c = text[i];
      if (c == '.' || c == '?' || c == '!') {
        sentences.add(buf.toString().trim());
        buf.clear();
      }
    }
    final trailing = buf.toString().trim();
    if (trailing.isNotEmpty) sentences.add(trailing);

    if (sentences.length < 3) return text;

    final result = <String>[];
    var prevSentence = '';
    var runCount = 0;
    var hadRepetition = false;

    for (final s in sentences) {
      if (s == prevSentence) {
        runCount++;
        if (runCount < 3) {
          result.add(s);
        } else {
          hadRepetition = true;
        }
      } else {
        prevSentence = s;
        runCount = 1;
        result.add(s);
      }
    }

    if (hadRepetition) {
      _log.warning(
        'Whisper hallucination detected: collapsed ${sentences.length} '
        'sentences to ${result.length}',
      );
      _lastPrompt = null;
      _lastPromptTime = null;
    }

    return result.join(' ');
  }

  void _fail(String message) {
    _log.error('STT error: $message');
    _transition(
      SttStatus(serverState: SttServerState.error, errorMessage: message),
    );
  }
}

// Providers are defined in stt_providers.dart and re-exported via stt_bundle.dart.
