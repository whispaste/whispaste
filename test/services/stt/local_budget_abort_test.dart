/// A local decode that runs out of its time budget is aborted natively and
/// leaves a free engine behind (#1639, #1619).
///
/// The fake engine below never finishes a decode on its own; only
/// [AbortableDecode.abortDecode] ends it, the way whisper.cpp stops at its
/// abort flag. The budget is shrunk through the notifier's test override.
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
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart'
    show isRepeatableTranscriptionError;
import 'package:whispaste/services/recording_orchestrator.dart'
    show unclassifiedTranscribeErrorCode;
import 'package:whispaste/services/stt/stt_bundle.dart';

import '../../test_helpers/wav_bytes.dart';

/// How the fake answers a final decode.
enum _Mode {
  /// Returns at once.
  finish,

  /// Runs until aborted, then fails like whisper.cpp at its abort flag.
  hangUntilAborted,

  /// Ignores the abort flag (a hung driver): never returns on its own.
  ignoreAbort,

  /// Sees the abort flag only after it finished: returns its text.
  finishDespiteAbort,
}

class _AbortableFake implements WhisperEngine, AbortableDecode {
  bool _loaded = false;
  _Mode mode = _Mode.finish;
  int abortCalls = 0;
  int decodes = 0;
  Completer<String>? _running;

  /// Completed when a non-finishing decode has started.
  Completer<void>? entered;

  /// Ends an [_Mode.ignoreAbort] decode from the test.
  void release() {
    final running = _running;
    _running = null;
    if (running != null && !running.isCompleted) running.complete('late');
  }

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    _loaded = true;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) {
    decodes++;
    if (mode == _Mode.finish) return Future.value('transcript');
    final running = _running = Completer<String>();
    final e = entered;
    if (e != null && !e.isCompleted) e.complete();
    return running.future;
  }

  @override
  void abortDecode() {
    abortCalls++;
    final running = _running;
    if (running == null || running.isCompleted) return;
    switch (mode) {
      case _Mode.hangUntilAborted:
        _running = null;
        running.completeError(
          const WhisperEngineException(
            WhisperFailureKind.timeout,
            kWhisperDecodeAborted,
          ),
        );
      case _Mode.finishDespiteAbort:
        _running = null;
        running.complete('finished anyway');
      case _Mode.ignoreAbort:
      case _Mode.finish:
        break;
    }
  }
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

ProviderContainer _makeContainer(WhisperEngine engine) => ProviderContainer(
  overrides: [
    whisperEngineProvider.overrideWithValue(engine),
    settingsProvider.overrideWith(
      () => _FakeSettingsNotifier(
        AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
      ),
    ),
    modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
    recordingPhaseProvider.overrideWithValue(RecordingPhase.transcribing),
    hw.gpuInfoProvider.overrideWith(
      (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
    ),
  ],
);

Future<SttServerStateNotifier> _ready(
  ProviderContainer container,
  _AbortableFake fake,
) async {
  await container.read(settingsProvider.future);
  final notifier = container.read(localSttBundleProvider.notifier);
  await notifier.ensureRunning();
  notifier.notifyRecordingStarted();
  notifier.notifyRecordingStopped();
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Duration? savedBudget;
  late Duration savedGrace;
  late Duration savedIdleCap;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_budget_abort_');
    final modelFilename =
        findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
    await File(
      '${tempDir.path}/$modelFilename',
    ).writeAsBytes(Uint8List(11 * 1024 * 1024));
    paths.sttDirOverride = tempDir.path;
    savedBudget = SttServerStateNotifier.stuckGuardTimeout;
    savedGrace = SttServerStateNotifier.abortGrace;
    savedIdleCap = SttServerStateNotifier.nativeIdleCap;
    SttServerStateNotifier.stuckGuardTimeout = const Duration(
      milliseconds: 100,
    );
    SttServerStateNotifier.abortGrace = const Duration(milliseconds: 200);
    // A next dictation behind a busy engine would wait this long; the
    // freed engine must not need it.
    SttServerStateNotifier.nativeIdleCap = const Duration(seconds: 30);
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(hours: 1);
  });

  tearDown(() async {
    SttServerStateNotifier.stuckGuardTimeout = savedBudget;
    SttServerStateNotifier.abortGrace = savedGrace;
    SttServerStateNotifier.nativeIdleCap = savedIdleCap;
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(seconds: 2);
    paths.sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  test('a decode over budget is aborted, the failure keeps the audio, and '
      'the next dictation runs at once on the same engine', () async {
    final fake = _AbortableFake();
    final container = _makeContainer(fake);
    addTearDown(container.dispose);
    final notifier = await _ready(container, fake);

    fake.mode = _Mode.hangUntilAborted;
    Object? failure;
    try {
      await notifier.transcribeBytes(buildWavBytes());
    } catch (e) {
      failure = e;
    }

    expect(fake.abortCalls, 1, reason: 'the native decode was aborted');
    expect(
      failure,
      isA<WhisperEngineException>()
          .having((e) => e.kind, 'kind', WhisperFailureKind.timeout)
          .having(
            (e) => e.message,
            'message',
            contains('transcription_budget_exceeded'),
          ),
    );
    // The orchestrator turns it into a code the retry queue keeps.
    final code = unclassifiedTranscribeErrorCode(failure!);
    expect(code, 'transcription_timeout');
    expect(isRepeatableTranscriptionError(code), isTrue);

    expect(notifier.hasNativeCallRunning, isFalse);
    expect(notifier.state.restartNeeded, isFalse);
    expect(notifier.state.isReady, isTrue);
    expect(notifier.debugBudgetBoost, 2, reason: 'the retry gets more time');

    // Next dictation: no wait for nativeIdleCap, no "engine still busy".
    fake.mode = _Mode.finish;
    final decodesBefore = fake.decodes;
    final watch = Stopwatch()..start();
    final text = await notifier.transcribeBytes(buildWavBytes());
    watch.stop();
    expect(text, isNotEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(fake.decodes, decodesBefore + 1);
    expect(notifier.debugBudgetBoost, 1, reason: 'a finished decode resets');
  });

  test(
    'a decode that finishes when the abort arrives keeps its text',
    () async {
      final fake = _AbortableFake();
      final container = _makeContainer(fake);
      addTearDown(container.dispose);
      final notifier = await _ready(container, fake);

      fake.mode = _Mode.finishDespiteAbort;
      final text = await notifier.transcribeBytes(buildWavBytes());

      expect(fake.abortCalls, 1);
      expect(text, contains('finished anyway'));
      expect(notifier.debugBudgetBoost, 1);
    },
  );

  test('a decode that ignores the abort counts as hung: the next decode '
      'fails fast and Settings asks for a restart', () async {
    final fake = _AbortableFake();
    final container = _makeContainer(fake);
    addTearDown(container.dispose);
    final notifier = await _ready(container, fake);
    SttServerStateNotifier.previewDrainCap = const Duration(milliseconds: 50);
    addTearDown(
      () => SttServerStateNotifier.previewDrainCap = const Duration(seconds: 2),
    );

    fake
      ..mode = _Mode.ignoreAbort
      ..entered = Completer<void>();
    await expectLater(
      notifier.transcribeBytes(buildWavBytes()),
      throwsA(
        isA<WhisperEngineException>().having(
          (e) => e.kind,
          'kind',
          WhisperFailureKind.timeout,
        ),
      ),
    );
    expect(fake.abortCalls, 1);
    expect(notifier.hasNativeCallRunning, isTrue);
    expect(notifier.state.restartNeeded, isTrue);

    fake.release();
    await Future<void>.delayed(Duration.zero);
    expect(notifier.hasNativeCallRunning, isFalse);
    expect(notifier.state.restartNeeded, isFalse);
  });
}
