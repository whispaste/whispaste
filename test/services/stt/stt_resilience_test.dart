/// Resilience tests for [SttServerStateNotifier] against distinguishable FFI
/// failure signals (CONTEXT.md §3.3): CPU-fallback on GPU crash, OOM-recovery
/// trigger, stuck-guard timeout, and transient retry.
///
/// The subprocess-era chain keyed on process exit codes; the in-process engine
/// signals a typed [WhisperEngineException] instead. These tests drive each
/// failure class through the public [SttServerStateNotifier.transcribeBytes]
/// surface via a fake engine, asserting only on public state
/// ([SttStatus]/[SttServerState]) and Sentry-capture behaviour.
///
/// The Sentry-capture assertions are the `stt_inference_capture_test.dart`
/// equivalent for FFI errors (AC6): surfaced failures capture exactly once,
/// recovered ones capture never.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

// ---------------------------------------------------------------------------
// Sentry spy
// ---------------------------------------------------------------------------

final _capturedEvents = <SentryEvent>[];

SentryEvent? _spyBeforeSend(SentryEvent event, Hint hint) {
  _capturedEvents.add(event);
  return null;
}

// ---------------------------------------------------------------------------
// Failure-simulating fake engine
// ---------------------------------------------------------------------------

/// A [WhisperEngine] fake that starts benign (so the notifier's startup warmup
/// + benchmark succeed) and can be *armed* after the notifier is ready to
/// simulate one failure class. [armedCallCount] counts only transcribe calls
/// made after the most recent `arm*` call — i.e. the real inference calls under
/// test, not warmup/benchmark.
class _FakeWhisperEngine implements WhisperEngine {
  String transcript = 'hallo welt';
  bool _loaded = false;

  WhisperFailureKind? _armedKind;
  int _remainingFailures = 0;
  bool _hang = false;
  int armedCallCount = 0;

  /// The `prompt` passed to the most recent [transcribe] call (Issue 22
  /// regression: custom-vocabulary/prompt biasing must reach the engine).
  String? lastPrompt;

  void _resetArm() {
    armedCallCount = 0;
    _armedKind = null;
    _remainingFailures = 0;
    _hang = false;
  }

  /// Fail the first [count] inference calls with [kind], then succeed.
  void armFailures(WhisperFailureKind kind, int count) {
    _resetArm();
    _armedKind = kind;
    _remainingFailures = count;
  }

  /// Fail every inference call with [kind] (used for OOM / exhausted-transient).
  void armAlways(WhisperFailureKind kind) {
    _resetArm();
    _armedKind = kind;
    _remainingFailures = 1 << 30;
  }

  /// Hang forever on the next inference call (stuck-guard).
  void armHang() {
    _resetArm();
    _hang = true;
  }

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
  }) async {
    lastPrompt = prompt;
    if (_hang) {
      armedCallCount++;
      return Completer<String>().future; // never completes
    }
    if (_armedKind != null && _remainingFailures > 0) {
      armedCallCount++;
      _remainingFailures--;
      throw WhisperEngineException(_armedKind!, _messageFor(_armedKind!));
    }
    if (_armedKind != null) armedCallCount++;
    return transcript;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }

  static String _messageFor(WhisperFailureKind kind) => switch (kind) {
    // The OOM message carries the token the orchestrator's OOM-recovery path
    // keys on — the whole point of "recovery greift, kein harter Abbruch".
    WhisperFailureKind.oom => 'stt_cuda_oom: simulated GPU out-of-memory',
    WhisperFailureKind.gpuCrash => 'simulated GPU backend crash',
    WhisperFailureKind.transient => 'simulated transient inference failure',
    WhisperFailureKind.timeout => 'simulated timeout',
    WhisperFailureKind.other => 'simulated other failure',
  };
}

/// A [WhisperEngine] fake with a fixed, non-swappable [backend] whose [load]
/// can be armed to fail — used to exercise the FLUTTER_WHISPASTE-80 load-time
/// CPU-fallback path (a GPU/driver cold-start that hangs past the engine's
/// internal load timeout), distinct from [_FakeWhisperEngine]'s
/// transcribe-time failure simulation.
class _LoadFailingEngine implements WhisperEngine {
  _LoadFailingEngine({required this.backend, this.failLoad = false});

  final WhisperBackend backend;
  bool failLoad;
  bool _loaded = false;
  String? lastLoadedModelPath;

  /// Optional call-order trace, appended to by [load]/[transcribe] when set
  /// — used to prove the crash-loop guard clears strictly *after* the
  /// warmup inference, not right after `load()` returns (gpu_load_crash_guard
  /// coverage test).
  List<String>? trace;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: backend);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    if (failLoad) {
      throw StateError(
        'whisper_isolate_load_failed: TimeoutException after '
        '0:01:00.000000: Future not completed',
      );
    }
    trace?.add('load');
    lastLoadedModelPath = modelPath;
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
  }) async {
    trace?.add('transcribe');
    return 'ok';
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

// ---------------------------------------------------------------------------
// Provider fakes
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});

  @override
  Future<void> downloadModel(String modelId) async {
    state = ModelDownloadState(downloadedModels: {modelId});
  }
}

ProviderContainer _makeContainer(
  WhisperEngine engine, {
  AppSettings? settings,
}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
      ),
    ],
  );
}

Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('stt_resilience_');
  final modelFilename =
      findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));
  paths.sttDirOverride = dir.path;
  return dir;
}

Uint8List _validWav({int dataBytes = 16000}) {
  final buf = Uint8List(44 + dataBytes);
  buf[0] = 0x52; // R
  buf[1] = 0x49; // I
  buf[2] = 0x46; // F
  buf[3] = 0x46; // F
  buf[8] = 0x57; // W
  buf[9] = 0x41; // A
  buf[10] = 0x56; // V
  buf[11] = 0x45; // E
  return buf;
}

Future<SttServerStateNotifier> _bringReady(ProviderContainer container) async {
  await container.read(settingsProvider.future);
  final notifier = container.read(localSttBundleProvider.notifier);
  await notifier.ensureRunning();
  expect(
    container.read(localSttBundleProvider).serverState,
    SttServerState.ready,
  );
  return notifier;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Duration savedTimeout;

  setUpAll(() async {
    await SentryFlutter.init((options) {
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.beforeSend = _spyBeforeSend;
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;
  });

  tearDownAll(() async {
    await CrashReporter.instance?.dispose();
  });

  setUp(() async {
    tempDir = await _createFakeSttDir();
    savedTimeout = SttServerStateNotifier.stuckGuardTimeout;
    // Shrink the stuck-guard so the hang test finishes in milliseconds.
    SttServerStateNotifier.stuckGuardTimeout = const Duration(
      milliseconds: 200,
    );
    _capturedEvents.clear();
  });

  tearDown(() async {
    SttServerStateNotifier.stuckGuardTimeout = savedTimeout;
    paths.sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  // ── AC2: GPU crash → CPU fallback ────────────────────────────────────────
  group('CPU-fallback on GPU crash', () {
    test('a GPU crash degrades to CPU, sets cpuFallbackActive, and the '
        'retry succeeds', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armFailures(WhisperFailureKind.gpuCrash, 1);
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(text, 'hallo welt', reason: 'the CPU retry must succeed');
      expect(
        container.read(localSttBundleProvider).cpuFallbackActive,
        isTrue,
        reason: 'cpuFallbackActive must be set after a GPU crash',
      );
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      expect(
        engine.armedCallCount,
        2,
        reason: 'one crashing attempt + one successful CPU retry',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        isEmpty,
        reason: 'a successfully recovered GPU crash is not a surfaced error',
      );
    });
  });

  // ── AC3: GPU OOM → recovery trigger, no hard abort ───────────────────────
  group('OOM-recovery trigger', () {
    test('a GPU OOM surfaces the stt_cuda_oom recovery token without a CPU '
        'fallback or wasteful retry', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armAlways(WhisperFailureKind.oom);
      _capturedEvents.clear();

      Object? caught;
      try {
        await notifier.transcribeBytes(_validWav(), language: 'auto');
      } catch (e) {
        caught = e;
      }

      expect(caught, isNotNull, reason: 'OOM must surface, not be swallowed');
      expect(
        '$caught',
        contains('stt_cuda_oom'),
        reason: "the orchestrator's OomRecoveryHandler keys on this token",
      );
      expect(
        container.read(localSttBundleProvider).cpuFallbackActive,
        isFalse,
        reason: 'OOM recovers via smaller-model/cloud, not a CPU retry',
      );
      expect(
        engine.armedCallCount,
        1,
        reason: 'OOM is not retried in the notifier — it hands off immediately',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        hasLength(1),
        reason: 'the OOM is captured once under its own fingerprint',
      );
    });
  });

  // ── AC4: hanging transcription → stuck-guard, no deadlock ────────────────
  group('Stuck-guard timeout', () {
    test('a transcription that never returns ends in a clean bounded error, '
        'not a deadlock', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armHang();
      _capturedEvents.clear();

      final sw = Stopwatch()..start();
      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(anything),
      );
      sw.stop();

      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'the stuck-guard must bound the hang — no deadlock',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        hasLength(1),
        reason: 'the stuck transcription is captured once',
      );
    });
  });

  // ── AC5: transient failure → retry ───────────────────────────────────────
  group('Transient retry', () {
    test('a transient failure that clears within the retry budget maps to '
        'a successful transcription (state stays ready)', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armFailures(WhisperFailureKind.transient, 2);
      _capturedEvents.clear();

      final text = await notifier.transcribeBytes(
        _validWav(),
        language: 'auto',
      );

      expect(text, 'hallo welt');
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
        reason: 'success after retry maps to ready',
      );
      expect(
        engine.armedCallCount,
        3,
        reason: 'two transient failures + one success',
      );

      await CrashReporter.instance!.flush();
      expect(_capturedEvents, isEmpty);
    });

    test('a transient failure that never clears aborts after 3 retries and '
        'is captured once', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      engine.armAlways(WhisperFailureKind.transient);
      _capturedEvents.clear();

      await expectLater(
        notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(anything),
      );

      expect(
        engine.armedCallCount,
        4,
        reason: 'one initial attempt + three retries, then abort',
      );

      await CrashReporter.instance!.flush();
      expect(
        _capturedEvents,
        hasLength(1),
        reason: 'the exhausted-retry failure is captured once',
      );
    });
  });

  // ── Issue 22: custom-vocabulary/prompt biasing must reach the engine ────
  group('Custom-vocabulary prompt forwarding', () {
    test('the resolved custom-vocabulary prompt is forwarded to '
        'WhisperEngine.transcribe, not just validated', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(
        engine,
        settings: AppSettings.defaults.copyWith(
          sttModel: 'whisper-small',
          customVocabulary: 'Fachbegriff, Eigenname',
        ),
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'auto');

      expect(
        engine.lastPrompt,
        contains('Fachbegriff, Eigenname'),
        reason:
            'the notifier resolves the custom-vocabulary prompt but must '
            'also hand it to the engine, not just the pre-flight validator',
      );
    });

    test('no custom vocabulary configured and language is auto-detect → the '
        'engine receives no prompt (no language to prime with yet)', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine);
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'auto');

      expect(engine.lastPrompt, isNull);
    });

    test(
      'no custom vocabulary, known language, punctuation priming on '
      '(default) → the engine receives the default punctuation prompt',
      () async {
        final engine = _FakeWhisperEngine();
        final container = _makeContainer(engine);
        addTearDown(container.dispose);

        final notifier = await _bringReady(container);
        _capturedEvents.clear();

        await notifier.transcribeBytes(_validWav(), language: 'en');

        expect(engine.lastPrompt, isNotNull);
        expect(engine.lastPrompt, isNot(isEmpty));
      },
    );

    test('no custom vocabulary, known language, punctuation priming disabled '
        'via settings → the engine receives no prompt', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(
        engine,
        settings: AppSettings.defaults.copyWithSections(
          stt: AppSettings.defaults.stt.copyWith(
            model: 'whisper-small',
            punctuationPriming: false,
          ),
        ),
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'en');

      expect(engine.lastPrompt, isNull);
    });

    test('custom vocabulary set → punctuation priming never overrides it, even '
        'for a known language', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(
        engine,
        settings: AppSettings.defaults.copyWith(
          sttModel: 'whisper-small',
          customVocabulary: 'Fachbegriff, Eigenname',
        ),
      );
      addTearDown(container.dispose);

      final notifier = await _bringReady(container);
      _capturedEvents.clear();

      await notifier.transcribeBytes(_validWav(), language: 'en');

      expect(engine.lastPrompt, equals('Fachbegriff, Eigenname'));
    });
  });

  // ── FLUTTER_WHISPASTE-80: CPU-fallback on model-load failure/hang ────────
  group('CPU-fallback on model-load failure (FLUTTER_WHISPASTE-80)', () {
    test(
      'a hung/failed GPU-backend load degrades once to CPU and reaches ready',
      () async {
        final gpuEngine = _LoadFailingEngine(
          backend: WhisperBackend.vulkan,
          failLoad: true,
        );
        final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
        final container = ProviderContainer(
          overrides: [
            whisperEngineProvider.overrideWithValue(gpuEngine),
            whisperCpuFallbackEngineProvider.overrideWithValue(cpuEngine),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
              ),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(),
            ),
            hw.gpuInfoProvider.overrideWith(
              (_) async =>
                  const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
        expect(
          container.read(localSttBundleProvider).cpuFallbackActive,
          isTrue,
          reason: 'cpuFallbackActive must be set after the load-time fallback',
        );
        expect(cpuEngine.lastLoadedModelPath, isNotNull);
      },
    );

    test('a load failure on an already-CPU engine fails immediately — no '
        'fallback loop, no fallback engine touched', () async {
      final cpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.cpu,
        failLoad: true,
      );
      final unusedFallback = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(cpuEngine),
          whisperCpuFallbackEngineProvider.overrideWithValue(unusedFallback),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.error,
      );
      expect(container.read(localSttBundleProvider).cpuFallbackActive, isFalse);
      expect(unusedFallback.lastLoadedModelPath, isNull);
    });
  });

  group('GPU-load crash-loop breaker (gpu_load_crash_guard.dart)', () {
    late Directory guardDir;

    setUp(() async {
      guardDir = await Directory.systemTemp.createTemp('gpu_crash_guard_');
    });

    tearDown(() async {
      await guardDir.delete(recursive: true);
    });

    test('a successful GPU-backend load marks the guard before the native '
        'call and clears it right after — proving _start() is actually '
        'wired to the guard, not just coincidentally leaving no marker '
        'behind', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      expect(guard.markCalls, 1);
      expect(guard.clearCalls, 1);
      expect(guard.crashedLastAttempt, isFalse);
    });

    test('a caught GPU load failure that recovers onto CPU still marks then '
        'clears the guard — the process survived, so this must not look '
        'like a crash on the next launch', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final gpuEngine = _LoadFailingEngine(
        backend: WhisperBackend.vulkan,
        failLoad: true,
      );
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          whisperCpuFallbackEngineProvider.overrideWithValue(cpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );
      expect(guard.markCalls, 1);
      expect(guard.clearCalls, 1);
      expect(guard.crashedLastAttempt, isFalse);
    });

    test('a CPU-only engine never touches the guard at all — the marker is '
        'reserved for GPU-backed attempts', () async {
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path);
      final cpuEngine = _LoadFailingEngine(backend: WhisperBackend.cpu);
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(cpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      expect(guard.markCalls, 0);
      expect(guard.clearCalls, 0);
    });

    test('the marker clears strictly AFTER the warmup inference, not right '
        'after load() — on old/weak GPUs the first compute dispatch, not '
        'the weight load, is the more likely native crash point, so '
        'clearing too early would let that exact crash repeat the loop '
        'undetected', () async {
      final trace = <String>[];
      final guard = _SpyGpuLoadCrashGuard(dataDir: guardDir.path, trace: trace);
      final gpuEngine = _LoadFailingEngine(backend: WhisperBackend.vulkan)
        ..trace = trace;
      final container = ProviderContainer(
        overrides: [
          whisperEngineProvider.overrideWithValue(gpuEngine),
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(),
          ),
          hw.gpuInfoProvider.overrideWith(
            (_) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      // Only the first 4 entries are asserted: _runBenchmark's own transcribe
      // call is unawaited (fire-and-forget) and may append a trailing
      // 'transcribe' after 'clear' depending on scheduling — that's expected
      // and irrelevant to what this test checks.
      expect(
        trace.take(4),
        ['mark', 'load', 'transcribe', 'clear'],
        reason:
            '"clear" must come after "transcribe" (the warmup inference) — '
            'if it moved back to right after "load", a crash during warmup '
            'on real hardware would go undetected by the next launch',
      );
    });
  });
}

/// Counts real [GpuLoadCrashGuard] calls so tests can assert `_start()` is
/// actually wired to the guard (mark-before-load, clear-after-return),
/// rather than only asserting on the marker file's final state — which
/// would pass even if the wiring were deleted entirely.
class _SpyGpuLoadCrashGuard extends GpuLoadCrashGuard {
  _SpyGpuLoadCrashGuard({required super.dataDir, this.trace});

  int markCalls = 0;
  int clearCalls = 0;

  /// Optional shared call-order trace — see [_LoadFailingEngine.trace].
  final List<String>? trace;

  @override
  void markAttempt() {
    markCalls++;
    trace?.add('mark');
    super.markAttempt();
  }

  @override
  void clearAttempt() {
    clearCalls++;
    trace?.add('clear');
    super.clearAttempt();
  }
}
