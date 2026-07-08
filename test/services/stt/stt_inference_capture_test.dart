/// Wiring tests for STT inference validator-reject + transport-independent
/// post-processing paths.
///
/// Covers:
///  - a `InferenceRequestValidator` reject emits a Sentry breadcrumb in
///    category `stt` with the documented data fields **but never** escalates
///    to a captureError, and throws [InferenceClientRejected] with the
///    validator's stable `userMessageKey`;
///  - the `language` value reaches [WhisperEngine.transcribe] as-is;
///  - zeroed WAV header size fields are repaired before the engine call;
///  - the AppLogger `_log.warning`-does-not-auto-escalate contract;
///  - non-speech marker stripping on the returned transcript.
///
/// Scope note (Issue 03, Nachtrag 2): the pre-cutover version of this file
/// also had "HTTP failure capture" (413/415/500/503 status-code → Sentry
/// fingerprint mapping) and "connection-lost capture" (SocketException/
/// ClientException mid-inference) groups. Both asserted on HTTP-transport
/// specifics — [WhisperEngine.transcribe] throws Dart exceptions, not HTTP
/// responses, so there is no direct equivalent. Retired here (not adapted);
/// Issue 05's own AC text already plans a
/// "stt_inference_capture_test.dart-Äquivalent" for FFI-error capture, so
/// this gap is expected to close there, not in Issue 03.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

// ---------------------------------------------------------------------------
// Sentry spy — records every event and breadcrumb that survives the hooks.
// ---------------------------------------------------------------------------

final _capturedEvents = <SentryEvent>[];
final _capturedBreadcrumbs = <Breadcrumb>[];

SentryEvent? _spyBeforeSend(SentryEvent event, Hint hint) {
  _capturedEvents.add(event);
  // Returning null suppresses transmission. We only care that the SDK saw
  // the event at all (which is one captureError observation).
  return null;
}

Breadcrumb? _spyBeforeBreadcrumb(Breadcrumb? breadcrumb, Hint? hint) {
  if (breadcrumb != null) _capturedBreadcrumbs.add(breadcrumb);
  return breadcrumb;
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeWhisperEngine implements WhisperEngine {
  _FakeWhisperEngine({this.transcript = 'ok'});

  /// Text returned by [transcribe] on success.
  String transcript;

  bool _loaded = false;
  List<int>? lastWavBytes;
  String? lastLanguage;
  bool sawTranscribeCall = false;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    sawTranscribeCall = true;
    lastWavBytes = wavBytes;
    lastLanguage = language;
    return transcript;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
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

  @override
  Future<void> downloadModel(String modelId) async {
    state = ModelDownloadState(downloadedModels: {modelId});
  }
}

// ---------------------------------------------------------------------------
// Container + WAV helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required WhisperEngine engine,
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
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_inference_capture_');

  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));

  paths.sttDirOverride = dir.path;
  return dir;
}

/// A canonical 44-byte-header WAV (16 kHz mono 16-bit) with [dataBytes] of
/// payload. [patchSizes] mirrors whether `WavFileWriter.close()` got to
/// patch the RIFF/data size fields — `false` produces the unpatched-header
/// shape behind FLUTTER_WHISPASTE-7X.
Uint8List _canonicalWav({required int dataBytes, required bool patchSizes}) {
  final buf = Uint8List(44 + dataBytes);
  final bd = ByteData.view(buf.buffer);
  void tag(int offset, String t) {
    for (var i = 0; i < t.length; i++) {
      buf[offset + i] = t.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  bd.setUint32(4, patchSizes ? 36 + dataBytes : 0, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, 16000, Endian.little);
  bd.setUint32(28, 32000, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bd.setUint32(40, patchSizes ? dataBytes : 0, Endian.little);
  for (var i = 44; i < buf.length; i++) {
    buf[i] = 0xAB;
  }
  return buf;
}

/// Reads the little-endian u32 at [offset] in [wav] — used to assert the
/// RIFF/data size fields the engine actually received.
int _wavField(Uint8List wav, int offset) {
  return wav[offset] |
      (wav[offset + 1] << 8) |
      (wav[offset + 2] << 16) |
      (wav[offset + 3] << 24);
}

/// A minimal valid WAV header (RIFF/WAVE magic + 16 kHz mono 16-bit) so the
/// validator's RIFF/WAVE check passes. Anything larger than 44 bytes; the
/// content is irrelevant for the routing tests.
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

/// Drives the notifier from `stopped` → `ready` against [engine].
Future<void> _bringNotifierReady(ProviderContainer container) async {
  await container.read(settingsProvider.future);
  await container.read(localSttBundleProvider.notifier).ensureRunning();
  expect(
    container.read(localSttBundleProvider).serverState,
    SttServerState.ready,
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await SentryFlutter.init((options) {
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.beforeSend = _spyBeforeSend;
      options.beforeBreadcrumb = _spyBeforeBreadcrumb;
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;
  });

  setUp(() {
    _capturedEvents.clear();
    _capturedBreadcrumbs.clear();
  });

  tearDownAll(() async {
    await CrashReporter.instance?.dispose();
  });

  // ── Pre-flight reject path ──────────────────────────────────────────────

  group('SttServerStateNotifier.transcribeBytes — validator reject', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('empty WAV → 0 captures, 1 breadcrumb in category `stt`, '
        'throws InferenceClientRejected with stt.reject.empty', () async {
      final engine = _FakeWhisperEngine(transcript: 'unreachable');
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await _bringNotifierReady(container);
      _capturedEvents.clear();
      _capturedBreadcrumbs.clear();
      // The startup warmup already called transcribe() once (on a silent
      // WAV) — reset the flag so it only reflects this test's own call.
      engine.sawTranscribeCall = false;

      final notifier = container.read(localSttBundleProvider.notifier);

      InferenceClientRejected? caught;
      try {
        await notifier.transcribeBytes(Uint8List(0), language: 'auto');
      } on InferenceClientRejected catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'must throw InferenceClientRejected');
      expect(caught!.userMessageKey, 'stt.reject.empty');
      expect(
        engine.sawTranscribeCall,
        isFalse,
        reason: 'the validator must short-circuit before the engine call',
      );

      await CrashReporter.instance!.flush();

      expect(
        _capturedEvents,
        isEmpty,
        reason:
            'A pre-flight reject is an expected user-input issue and must '
            'never escalate to Sentry; observed events: '
            '${_capturedEvents.map((e) => e.message?.formatted ?? e.throwable).toList()}',
      );

      final sttBreadcrumbs = _capturedBreadcrumbs
          .where((b) => b.category == 'stt')
          .toList();
      expect(
        sttBreadcrumbs,
        hasLength(1),
        reason: 'exactly one `stt`-category breadcrumb expected',
      );
      final data = sttBreadcrumbs.single.data!;
      expect(data['reject_reason'], 'empty');
      expect(data['wav_size_bytes'], 0);
      expect(data['audio_duration_ms'], 0);
      expect(data['language'], 'auto');
    });
  });

  // ── Language field reaches the engine (store-review regression, June 2026) ──

  group('SttServerStateNotifier.transcribeBytes — language field', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    /// Runs one inference with [language] and returns the value the engine
    /// actually received (null = never reached the engine).
    Future<String?> capturedLanguageField(String language) async {
      final engine = _FakeWhisperEngine(transcript: 'ok');
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await _bringNotifierReady(container);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.transcribeBytes(_validWav(), language: language);

      expect(
        engine.sawTranscribeCall,
        isTrue,
        reason: 'request must reach the engine',
      );
      return engine.lastLanguage;
    }

    test('auto is sent explicitly — an omitted value would fall back to '
        "the engine's own default instead of auto-detection", () async {
      expect(await capturedLanguageField('auto'), 'auto');
    });

    test('an explicit language code is sent as-is', () async {
      expect(await capturedLanguageField('de'), 'de');
    });

    test('catalog languages beyond the legacy four pass pre-flight '
        '(store review: Russian was rejected)', () async {
      expect(await capturedLanguageField('ru'), 'ru');
      expect(await capturedLanguageField('he'), 'he');
      expect(await capturedLanguageField('uk'), 'uk');
    });

    test('codes outside the Whisper catalog still reject pre-flight', () async {
      await expectLater(
        capturedLanguageField('xx'),
        throwsA(isA<InferenceClientRejected>()),
      );
    });
  });

  // ── WAV-header repair: unpatched recordings still transcribe ─────────────

  group('SttServerStateNotifier.transcribeBytes — WAV header repair', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    Future<(String text, Uint8List sentWav)> runWithWav(Uint8List wav) async {
      final engine = _FakeWhisperEngine(transcript: 'hallo welt');
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await _bringNotifierReady(container);
      _capturedEvents.clear();
      _capturedBreadcrumbs.clear();

      final text = await container
          .read(localSttBundleProvider.notifier)
          .transcribeBytes(wav, language: 'auto');
      return (text, Uint8List.fromList(engine.lastWavBytes!));
    }

    test('recording with zeroed RIFF/data size fields is repaired before the '
        'engine call and still transcribes (FLUTTER_WHISPASTE-7X)', () async {
      // The unpatched-header shape: WavFileWriter.close() never patched the
      // size fields. The engine's WAV decoder rejects exactly this
      // container — the dictation must not be lost.
      const dataBytes = 1000;
      final broken = _canonicalWav(dataBytes: dataBytes, patchSizes: false);

      final (text, sentWav) = await runWithWav(broken);

      expect(text, 'hallo welt');
      expect(
        _wavField(sentWav, 4),
        36 + dataBytes,
        reason: 'RIFF size field must be repaired in the shipped payload',
      );
      expect(
        _wavField(sentWav, 40),
        dataBytes,
        reason: 'data size field must be repaired in the shipped payload',
      );
      expect(
        _capturedBreadcrumbs.where(
          (b) =>
              b.category == 'stt' && (b.message?.contains('repaired') ?? false),
        ),
        hasLength(1),
        reason: 'the repair must leave a field signal as an stt breadcrumb',
      );
      expect(
        _capturedEvents,
        isEmpty,
        reason: 'a successfully repaired request is not an error',
      );
    });

    test('correctly patched recording ships byte-identical (no over-eager '
        'repair)', () async {
      const dataBytes = 1000;
      final ok = _canonicalWav(dataBytes: dataBytes, patchSizes: true);

      final (text, sentWav) = await runWithWav(ok);

      expect(text, 'hallo welt');
      expect(
        sentWav,
        ok,
        reason: 'a well-formed WAV must pass through unmodified',
      );
    });
  });

  group('AppLogger dedup — _log.warning does not auto-escalate', () {
    test('a warning-level log line in the orchestrator transcription failure '
        'path does NOT add a second Sentry capture', () async {
      // The orchestrator hands the inference exception off via
      // `_log.warning(...)` after this issue's downgrade. We do not need
      // to spin up the whole pipeline — pinning the contract of the
      // AppLogger plumbing (Level.WARNING never reaches captureError) is
      // enough to guarantee the no-double-capture property.
      //
      // This mirrors the prior dedup contract from CHANGELOG v1.2.25
      // ("Doppelte Crash-Reports … beseitigt") and runs in <50ms.
      final logger = Logger('OrchestratorDedupSmokeTest');

      // Wire the same listener-shape configureLogging uses, minus the
      // file sink (irrelevant here).
      final sub = Logger.root.onRecord.listen((record) {
        if (record.level >= Level.SEVERE) {
          CrashReporter.instance?.captureError(
            message: record.message,
            error: record.error,
            stackTrace: record.stackTrace,
            severity: 'error',
            type: 'error',
            fingerprint: const [appLoggerAutoEscalated],
          );
        }
      });
      addTearDown(sub.cancel);

      _capturedEvents.clear();
      logger.warning('[$Object] Transcription failed: boom');
      await CrashReporter.instance!.flush();

      expect(
        _capturedEvents,
        isEmpty,
        reason:
            '`_log.warning(...)` must not feed the AppLogger auto-escalation '
            'pipeline — only SEVERE+ does. This contract is what makes the '
            'orchestrator downgrade safe (no second capture).',
      );

      // Sanity check: a SEVERE-level call does still escalate, so the
      // downgrade actually matters (negative control).
      _capturedEvents.clear();
      logger.severe('[$Object] severe-level escalates by design');
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, hasLength(1));
    });
  });

  // ── Non-speech marker stripping on the success path ──
  //
  // whisper emits bracketed sound tags ([Musik], [BLANK_AUDIO], …) on
  // silence/noise. These must never reach the transcript that gets pasted
  // into the active app or saved to history.
  group('SttServerStateNotifier.transcribeBytes — non-speech markers', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    Future<String> transcribeWithText(String engineText) async {
      final engine = _FakeWhisperEngine(transcript: engineText);
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await _bringNotifierReady(container);
      final notifier = container.read(localSttBundleProvider.notifier);
      return notifier.transcribeBytes(_validWav(), language: 'auto');
    }

    test(
      'strips a leading/trailing [Musik] marker, keeps the speech',
      () async {
        final text = await transcribeWithText('[Musik] Hallo Welt. [Musik]');
        expect(text, 'Hallo Welt.');
      },
    );

    test('strips [BLANK_AUDIO] and collapses the surrounding space', () async {
      final text = await transcribeWithText('Guten [BLANK_AUDIO] Morgen');
      expect(text, 'Guten Morgen');
    });

    test('a marker-only transcript collapses to empty', () async {
      final text = await transcribeWithText('[BLANK_AUDIO]');
      expect(text, isEmpty);
    });

    test('leaves parenthesised dictated text untouched', () async {
      final text = await transcribeWithText(
        'Berlin (die Hauptstadt) ist schön',
      );
      expect(text, 'Berlin (die Hauptstadt) ist schön');
    });
  });
}
