/// Native-busy gate of [SttServerStateNotifier] (DEV-233, DEV-269, GS-078).
///
/// Every path that frees, replaces or re-enters the engine (stop, idle timer,
/// model switch, OOM and cloud fallback) must leave a still-running native
/// call alone: no unload under it, no second native call on the same instance,
/// and at the cap the engine is retired instead of unloaded. The fake below
/// keeps a native call open until the test completes its [Completer], so each
/// test controls native busy and idle explicitly. Waits are event-driven
/// (completers and status listeners), not fixed sleeps.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/stt_engine_lifecycle_provider.dart';

import '../../test_helpers/wav_bytes.dart';

/// Engine fake whose native calls stay open until their gate completes.
class _NativeFake implements WhisperEngine, LivePreviewEngine {
  bool _loaded = false;

  /// Ordered engine calls: `load`, `unload`, `transcribe`, `preview`.
  final List<String> calls = [];
  final List<String> loadedPaths = [];

  /// Native calls running right now, and the most that ever ran at once.
  int nativeRunning = 0;
  int maxConcurrent = 0;

  /// Unloads that happened while a native call was still running.
  int unloadWhileBusy = 0;
  int transcribeCount = 0;

  /// Final-decode calls wait for this; null returns at once (warmup).
  Completer<void>? gate;

  /// Preview decodes wait for this; null returns at once.
  Completer<void>? previewGate;

  /// Completed when a gated call starts; set by the test before the call.
  Completer<void>? entered;
  Completer<void>? previewEntered;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    calls.add('load');
    loadedPaths.add(modelPath);
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    calls.add('transcribe');
    final gated = gate;
    // Warmup and benchmark calls run before a test sets its gate.
    if (gated == null) return 'warmup';
    transcribeCount++;
    _enter();
    if (entered != null && !entered!.isCompleted) entered!.complete();
    try {
      await gated.future;
      return 'transcript';
    } finally {
      nativeRunning--;
    }
  }

  void _enter() {
    nativeRunning++;
    if (nativeRunning > maxConcurrent) maxConcurrent = nativeRunning;
  }

  @override
  Future<void> unload() async {
    calls.add('unload');
    if (nativeRunning > 0) unloadWhileBusy++;
    _loaded = false;
  }

  @override
  Future<void> startLivePreview() async {}

  @override
  Future<String> decodeLivePreview(
    Float32List samples, {
    String? language,
    String? prompt,
  }) async {
    calls.add('preview');
    _enter();
    if (previewEntered != null && !previewEntered!.isCompleted) {
      previewEntered!.complete();
    }
    try {
      await previewGate?.future;
      return 'preview';
    } finally {
      nativeRunning--;
    }
  }

  @override
  Future<void> stopLivePreview() async {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _settings;
  _FakeSettingsNotifier(this._settings);

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
}

ProviderContainer _makeContainer({
  required WhisperEngine engine,
  required RecordingPhase phase,
}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            overlayShowLiveTranscript: true,
          ),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      recordingPhaseProvider.overrideWithValue(phase),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

Future<void> _writeModel(String modelId, String fallbackFile) async {
  final dir = paths.sttDirOverride!;
  final filename = findSttModel(modelId)?.filename ?? fallbackFile;
  await File('$dir/$filename').writeAsBytes(Uint8List(11 * 1024 * 1024));
}

/// Completes once [done] holds for the STT status. Fails after 10 s instead
/// of hanging, so a regression shows up as a failed expectation.
Future<void> _waitForStatus(
  ProviderContainer container,
  bool Function(SttStatus status) done,
) async {
  if (done(container.read(localSttBundleProvider))) return;
  final reached = Completer<void>();
  final sub = container.listen<SttStatus>(localSttBundleProvider, (_, next) {
    if (!reached.isCompleted && done(next)) reached.complete();
  });
  try {
    await reached.future.timeout(const Duration(seconds: 10));
  } finally {
    sub.close();
  }
}

/// Loads the engine, then starts one final decode that stays in native.
Future<({SttServerStateNotifier notifier, Future<String> decode})>
_startBusyDecode(ProviderContainer container, _NativeFake fake) async {
  await container.read(settingsProvider.future);
  final notifier = container.read(localSttBundleProvider.notifier);
  await notifier.ensureRunning();
  notifier.notifyRecordingStarted();
  notifier.notifyRecordingStopped();
  fake
    ..gate = Completer<void>()
    ..entered = Completer<void>();
  final decode = notifier.transcribeBytes(buildWavBytes());
  await fake.entered!.future.timeout(const Duration(seconds: 10));
  return (notifier: notifier, decode: decode);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Duration previousNativeIdleCap;
  late Duration previousPreviewDrainCap;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('native_busy_gate_test_');
    final modelFilename =
        findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
    await File(
      '${tempDir.path}/$modelFilename',
    ).writeAsBytes(Uint8List(11 * 1024 * 1024));
    paths.sttDirOverride = tempDir.path;
    previousNativeIdleCap = SttServerStateNotifier.nativeIdleCap;
    previousPreviewDrainCap = SttServerStateNotifier.previewDrainCap;
    // Keep the post-load self-benchmark out of these tests.
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(hours: 1);
  });

  tearDown(() async {
    SttServerStateNotifier.nativeIdleCap = previousNativeIdleCap;
    SttServerStateNotifier.previewDrainCap = previousPreviewDrainCap;
    SttServerStateNotifier.debugIdleUnloadDelay = null;
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(seconds: 2);
    paths.sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  group('stop while a native call runs', () {
    test('the stop ack completes after the call returns; a second stop shares '
        'it; one unload', () async {
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      final first = notifier.stop();
      final second = notifier.stop();
      expect(notifier.state.isReady, isFalse, reason: 'state not synced');
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls, isNot(contains('unload')));

      fake.gate!.complete();
      await Future.wait([first, second, decode]);
      expect(fake.calls.where((c) => c == 'unload'), hasLength(1));
      expect(fake.unloadWhileBusy, 0);
    });

    test(
      'at the cap the engine is retired: stop completes without an unload, '
      'a restart fails while busy, and the release happens on return',
      () async {
        SttServerStateNotifier.nativeIdleCap = const Duration(
          milliseconds: 100,
        );
        final fake = _NativeFake();
        final container = _makeContainer(
          engine: fake,
          phase: RecordingPhase.transcribing,
        );
        addTearDown(container.dispose);
        final (:notifier, :decode) = await _startBusyDecode(container, fake);

        await notifier.stop();
        expect(
          fake.calls,
          isNot(contains('unload')),
          reason: 'cap hit unloaded',
        );
        expect(notifier.state.isReady, isFalse);

        // The retired instance must not be loaded again while its call runs.
        await notifier.ensureRunning();
        expect(notifier.state.serverState, SttServerState.error);
        expect(fake.calls.where((c) => c == 'load'), hasLength(1));

        fake.gate!.complete();
        await decode;
        await Future<void>.delayed(Duration.zero);
        expect(
          fake.calls.last,
          'unload',
          reason: 'retired engine not released',
        );
        expect(fake.unloadWhileBusy, 0);

        await notifier.ensureRunning();
        expect(notifier.state.isReady, isTrue);
        expect(
          fake.calls.lastIndexOf('load'),
          greaterThan(fake.calls.lastIndexOf('unload')),
          reason: 'the restart must follow the release',
        );
      },
    );
  });

  group('fallback stop while a native call runs (OOM / cloud)', () {
    // applyOomModelFallback and switchToConfiguredCloudStt both end in the
    // lifecycle stop, so that is the entry point under test.
    for (final path in ['OOM model fallback', 'cloud fallback']) {
      test(
        '$path: retired at the cap, released when the call returns',
        () async {
          SttServerStateNotifier.nativeIdleCap = const Duration(
            milliseconds: 100,
          );
          final fake = _NativeFake();
          final container = _makeContainer(
            engine: fake,
            phase: RecordingPhase.transcribing,
          );
          addTearDown(container.dispose);
          final (:notifier, :decode) = await _startBusyDecode(container, fake);

          await container.read(onDeviceEngineLifecycleProvider).stop();
          expect(fake.calls, isNot(contains('unload')));
          expect(notifier.state.isReady, isFalse);

          fake.gate!.complete();
          await decode;
          await Future<void>.delayed(Duration.zero);
          expect(fake.calls.where((c) => c == 'unload'), hasLength(1));
          expect(fake.unloadWhileBusy, 0);
        },
      );
    }
  });

  group('idle timer while a native call runs', () {
    test('the idle unload is deferred while the call runs and fires after it '
        'returns', () async {
      SttServerStateNotifier.debugIdleUnloadDelay = const Duration(
        milliseconds: 50,
      );
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      // Several idle periods pass while the call stays open. The timer fires
      // at least once in that window, which is what this test relies on.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(notifier.state.isReady, isTrue, reason: 'idle unload under call');
      expect(fake.calls, isNot(contains('unload')));

      fake.gate!.complete();
      await decode;
      await _waitForStatus(container, (s) => !s.isReady);
      // The status flips before the unload, which runs one microtask later.
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((c) => c == 'unload'), hasLength(1));
      expect(fake.unloadWhileBusy, 0);
    });
  });

  group('no second native call on the same instance (DEV-233)', () {
    test(
      'a second decode waits for the first; never two native calls at once',
      () async {
        final fake = _NativeFake();
        final container = _makeContainer(
          engine: fake,
          phase: RecordingPhase.transcribing,
        );
        addTearDown(container.dispose);
        final (:notifier, :decode) = await _startBusyDecode(container, fake);

        final second = notifier.transcribeBytes(buildWavBytes());
        await Future<void>.delayed(Duration.zero);
        expect(fake.transcribeCount, 1, reason: 'second call started early');

        fake.gate!.complete();
        await Future.wait([decode, second]);
        expect(fake.maxConcurrent, 1);
        expect(fake.transcribeCount, 2);
      },
    );

    test('a second decode that finds the engine busy at the cap fails clearly '
        'and starts no native call', () async {
      SttServerStateNotifier.nativeIdleCap = const Duration(milliseconds: 100);
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      await expectLater(
        notifier.transcribeBytes(buildWavBytes()),
        throwsA(anything),
      );
      expect(fake.transcribeCount, 1);

      fake.gate!.complete();
      await decode;
      expect(fake.maxConcurrent, 1);
    });
  });

  group('model switch while a native call runs', () {
    test('the switch unloads only after the call returned', () async {
      await _writeModel('whisper-medium', 'ggml-medium-q5_0.bin');
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: 'whisper-medium'));
      // One-sided check: the debounce and file check have run by now, if they
      // are going to. Nothing may unload while the call is open.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(fake.calls, isNot(contains('unload')));

      fake.gate!.complete();
      await decode;
      await _waitForStatus(
        container,
        (s) => s.isReady && s.modelId == 'whisper-medium',
      );
      expect(fake.unloadWhileBusy, 0);
      expect(fake.loadedPaths.last, endsWith('medium-q5_0.bin'));
    });

    test('at the cap the switch is shown as pending and not forced; the retry '
        'switches once native is idle', () async {
      SttServerStateNotifier.nativeIdleCap = const Duration(milliseconds: 100);
      await _writeModel('whisper-medium', 'ggml-medium-q5_0.bin');
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      await container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: 'whisper-medium'));
      await _waitForStatus(
        container,
        (s) => s.pendingModelId == 'whisper-medium',
      );
      expect(fake.calls, isNot(contains('unload')), reason: 'forced at cap');
      expect(notifier.state.isReady, isTrue);

      fake.gate!.complete();
      await decode;
      await _waitForStatus(
        container,
        (s) =>
            s.isReady &&
            s.modelId == 'whisper-medium' &&
            s.pendingModelId == null,
      );
      expect(fake.calls.where((c) => c == 'unload'), hasLength(1));
      expect(fake.unloadWhileBusy, 0);
    });

    test(
      'a superseded switch does not continue: only the latest model loads',
      () async {
        await _writeModel('whisper-medium', 'ggml-medium-q5_0.bin');
        await _writeModel(
          'whisper-large-v3-turbo',
          'ggml-large-v3-turbo-q5_0.bin',
        );
        final fake = _NativeFake();
        final container = _makeContainer(
          engine: fake,
          phase: RecordingPhase.transcribing,
        );
        addTearDown(container.dispose);
        final (:notifier, :decode) = await _startBusyDecode(container, fake);

        final settings = container.read(settingsProvider.notifier);
        await settings.updateSettings(
          (s) => s.copyWith(sttModel: 'whisper-medium'),
        );
        // Lets the first switch reach its wait. If it has not, the second
        // request cancels its debounce, and the outcome below still holds.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await settings.updateSettings(
          (s) => s.copyWith(sttModel: 'whisper-large-v3-turbo'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));

        fake.gate!.complete();
        await decode;
        await _waitForStatus(
          container,
          (s) => s.isReady && s.modelId == 'whisper-large-v3-turbo',
        );
        expect(
          fake.loadedPaths.where((p) => p.endsWith('medium-q5_0.bin')),
          isEmpty,
          reason: 'superseded switch continued',
        );
        expect(fake.calls.where((c) => c == 'unload'), hasLength(1));
        expect(fake.unloadWhileBusy, 0);
      },
    );
  });

  group('live-preview drain cap (DEV-269)', () {
    test('a hanging preview decode does not hold the final decode past the '
        'cap, and no final native call starts', () async {
      SttServerStateNotifier.previewDrainCap = const Duration(
        milliseconds: 100,
      );
      SttServerStateNotifier.nativeIdleCap = const Duration(milliseconds: 200);
      final fake = _NativeFake()
        ..previewGate = Completer<void>()
        ..previewEntered = Completer<void>();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.recording,
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();

      notifier.notifyRecordingStarted();
      // 2 s of 16 kHz mono 16-bit PCM: the preview timer fires at 2 s.
      notifier.feedLivePreviewPcm(Uint8List(32000 * 2));
      await fake.previewEntered!.future.timeout(const Duration(seconds: 10));
      notifier.notifyRecordingStopped();

      await expectLater(
        notifier.transcribeBytes(buildWavBytes()),
        throwsA(anything),
      );
      expect(fake.transcribeCount, 0);

      fake.previewGate!.complete();
    });
  });

  group('quit and restart notice', () {
    test('quit with a never-returning native call returns at once; the '
        'engine is released when the call returns', () async {
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      await notifier.stopForQuit().timeout(const Duration(seconds: 2));
      expect(notifier.hasNativeCallRunning, isTrue);
      expect(fake.calls, isNot(contains('unload')));

      fake.gate!.complete();
      await decode;
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((c) => c == 'unload'), hasLength(1));
      expect(fake.unloadWhileBusy, 0);
    });

    test('an engine retired at the cap shows the restart notice, and the '
        'notice clears once the call returns', () async {
      SttServerStateNotifier.nativeIdleCap = const Duration(milliseconds: 100);
      final fake = _NativeFake();
      final container = _makeContainer(
        engine: fake,
        phase: RecordingPhase.transcribing,
      );
      addTearDown(container.dispose);
      final (:notifier, :decode) = await _startBusyDecode(container, fake);

      await notifier.stop();
      expect(notifier.state.errorMessage, 'stt_engine_restart_needed');

      fake.gate!.complete();
      await decode;
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.errorMessage, isNull);
    });
  });
}
