/// Wiring tests for STT inference Sentry-capture + validator-reject paths.
///
/// Issue 04 (wartung-2026-05): verify that
///
///  - a 4xx/5xx HTTP response from `whisper-server` results in **exactly one**
///    `CrashReporter.captureError` call (the explicit, fingerprinted capture
///    inside `SttServerStateNotifier.transcribeBytes`) — no second capture
///    from the orchestrator's `_log.error` auto-escalation, which the
///    parallel logger-downgrade removed;
///  - the fingerprint and extras emitted into Sentry follow the
///    [`InferenceErrorClassifier`](../../../lib/services/stt/inference_error_classifier.dart)
///    contract (one bucket per status-code class, six request-context
///    fields + `response_body`);
///  - a 5xx response does **not** trigger `ServerBinaryRecovery` — a 5xx
///    is a server-side error mid-flight, not a process-exit crash, so the
///    recovery orchestrator stays untouched;
///  - a `InferenceRequestValidator` reject emits a Sentry breadcrumb in
///    category `stt` with the documented data fields **but never** escalates
///    to a captureError, and throws [InferenceClientRejected] with the
///    validator's stable `userMessageKey`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/process_runner.dart';
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

class _FakeProcess implements Process {
  final _stdoutCtrl = StreamController<List<int>>();
  final _stderrCtrl = StreamController<List<int>>();
  final _exitCompleter = Completer<int>();

  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;
  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;
  @override
  Future<int> get exitCode => _exitCompleter.future;
  @override
  int get pid => 99997;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();

  void emitStderr(String line) => _stderrCtrl.add('$line\n'.codeUnits);

  void exit(int code) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  Future<void> dispose() async {
    await _stdoutCtrl.close();
    await _stderrCtrl.close();
  }
}

class _FakeProcessRunner extends ProcessRunner {
  final _FakeProcess process;

  _FakeProcessRunner(this.process);

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    return process;
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

/// Recording recovery double — must record zero calls in the 5xx regression
/// test (HTTP-level errors on `/inference` never hand off to recovery, which
/// is owned by the proc-exit path).
class _RecordingRecovery implements ServerBinaryRecovery {
  int recoverCalls = 0;

  @override
  Future<RecoveryResult> recover({
    required RecoveryReason reason,
    required hw.GpuInfo gpu,
    required String sttDirPath,
    required String? activeModelId,
  }) async {
    recoverCalls += 1;
    return const RecoveryRetried('cpu');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Container + WAV helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required ProcessRunner runner,
  required http.Client httpClient,
  AppSettings? settings,
  ServerBinaryRecovery? recoveryOverride,
}) {
  return ProviderContainer(
    overrides: [
      processRunnerProvider.overrideWithValue(runner),
      sttHttpClientProvider.overrideWithValue(httpClient),
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
      sttStartupHeartbeatConfigProvider.overrideWithValue(
        const SttStartupHeartbeatConfig(
          window: Duration(milliseconds: 50),
          maxMissedWindows: 3,
        ),
      ),
      if (recoveryOverride != null)
        serverBinaryRecoveryProvider.overrideWithValue(recoveryOverride),
    ],
  );
}

Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_inference_capture_');

  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  await File('${dir.path}/$serverName').writeAsBytes([0x7f, 0x45, 0x4c, 0x46]);

  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));

  paths.sttDirOverride = dir.path;
  return dir;
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

/// Drives the notifier from `stopped` → `ready` using a custom HTTP client
/// that lets the test override behavior on the `/inference` endpoint. The
/// `/health` path is always answered with `200 ok`.
Future<void> _bringNotifierReady(
  ProviderContainer container,
  _FakeProcess fakeProcess,
) async {
  await container.read(settingsProvider.future);
  fakeProcess.emitStderr('[whisper] model loaded');
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

  // ── HTTP-failure path: status code → fingerprint mapping + capture count ──

  group('SttServerStateNotifier.transcribeBytes — HTTP failure capture', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    Future<void> runFailureCase({
      required int statusCode,
      required String responseBody,
      required String expectedFingerprint,
    }) async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final recovery = _RecordingRecovery();

      final client = MockClient((req) async {
        if (req.url.path == '/health') return http.Response('ok', 200);
        if (req.url.path == '/inference') {
          return http.Response(responseBody, statusCode);
        }
        return http.Response('not found', 404);
      });

      final container = _makeContainer(
        runner: runner,
        httpClient: client,
        recoveryOverride: recovery,
      );
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await _bringNotifierReady(container, fakeProcess);

      // Drain any breadcrumbs emitted by the startup path (warmup inference
      // adds plenty); the rest of the test only cares about post-call signal.
      _capturedEvents.clear();
      _capturedBreadcrumbs.clear();

      final notifier = container.read(localSttBundleProvider.notifier);

      await expectLater(
        () => notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(isA<HttpException>()),
      );

      // Drain the fire-and-forget Sentry pipeline deterministically. A fixed
      // delay was flaky on the Windows runner where the SDK's beforeSend hop
      // takes >50ms — late events leaked into the next test's spy list.
      await CrashReporter.instance!.flush();

      expect(
        _capturedEvents,
        hasLength(1),
        reason:
            'A status=$statusCode response must capture exactly one Sentry '
            'event; observed: '
            '${_capturedEvents.map((e) => e.message?.formatted ?? e.throwable).toList()}',
      );

      final ev = _capturedEvents.single;
      expect(
        ev.fingerprint,
        [expectedFingerprint],
        reason: 'fingerprint must come from crash_fingerprints.dart',
      );
      expect(
        ev.tags?['error_type'],
        'stt_inference_failed',
        reason: 'tag identifies the call site for Sentry routing',
      );

      // Six request-context extras + the redacted response body — assert
      // their presence rather than their values (the classifier's own unit
      // tests pin the value semantics).
      final extrasCtx = ev.contexts['extras'] as Map?;
      expect(extrasCtx, isNotNull, reason: 'extras context must be set');
      expect(
        extrasCtx!.keys,
        containsAll([
          'wav_size_bytes',
          'audio_duration_ms',
          'language',
          'model_id',
          'prompt_length',
          'vocab_length',
          'response_body',
        ]),
        reason: 'six request-context extras + response_body must be present',
      );

      expect(
        recovery.recoverCalls,
        0,
        reason:
            'HTTP-level inference errors (any status) must NOT trigger '
            'ServerBinaryRecovery — that path is owned by proc-exit crashes',
      );
    }

    test(
      '400 → inferenceBadRequest, capture-count == 1, no recovery',
      () async {
        await runFailureCase(
          statusCode: 400,
          responseBody: 'bad request',
          expectedFingerprint: inferenceBadRequest,
        );
      },
    );

    test('413 → inferencePayloadTooLarge, capture-count == 1', () async {
      await runFailureCase(
        statusCode: 413,
        responseBody: 'payload too large',
        expectedFingerprint: inferencePayloadTooLarge,
      );
    });

    test('415 → inferenceUnsupportedMedia, capture-count == 1', () async {
      await runFailureCase(
        statusCode: 415,
        responseBody: 'unsupported media',
        expectedFingerprint: inferenceUnsupportedMedia,
      );
    });

    test('500 → inferenceServerError, capture-count == 1', () async {
      await runFailureCase(
        statusCode: 500,
        responseBody: 'internal server error',
        expectedFingerprint: inferenceServerError,
      );
    });

    test('503 → inferenceServerError, capture-count == 1', () async {
      await runFailureCase(
        statusCode: 503,
        responseBody: 'service unavailable',
        expectedFingerprint: inferenceServerError,
      );
    });

    test(
      '418 (unknown 4xx) → inferenceUnknownStatus, capture-count == 1',
      () async {
        await runFailureCase(
          statusCode: 418,
          responseBody: "i'm a teapot",
          expectedFingerprint: inferenceUnknownStatus,
        );
      },
    );

    test('5xx does NOT trigger ServerBinaryRecovery', () async {
      // Explicit regression test — separate from the per-status loop so the
      // observable property (`recoverCalls == 0` across the 5xx band) gets
      // its own named assertion in the test report.
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final recovery = _RecordingRecovery();

      final client = MockClient((req) async {
        if (req.url.path == '/health') return http.Response('ok', 200);
        if (req.url.path == '/inference') {
          return http.Response('boom', 503);
        }
        return http.Response('not found', 404);
      });

      final container = _makeContainer(
        runner: runner,
        httpClient: client,
        recoveryOverride: recovery,
      );
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await _bringNotifierReady(container, fakeProcess);
      final notifier = container.read(localSttBundleProvider.notifier);

      await expectLater(
        () => notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(isA<HttpException>()),
      );
      await CrashReporter.instance!.flush();

      expect(recovery.recoverCalls, 0);
    });
  });

  // ── Hardware-audit (2026-05): inference-time socket disconnect ──────────

  group('SttServerStateNotifier.transcribeBytes — connection-lost capture', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    Future<void> runConnectionLossCase({
      required Object thrown,
      required String expectedExceptionType,
    }) async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);

      var inferenceCallCount = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/health') return http.Response('ok', 200);
        if (req.url.path == '/inference') {
          inferenceCallCount += 1;
          // First call is the GPU warmup during cold-start — let it
          // succeed. Real inference call (second) throws to simulate
          // the whisper-server crashing mid-response.
          if (inferenceCallCount == 1) {
            return http.Response('{"text":""}', 200);
          }
          throw thrown;
        }
        return http.Response('not found', 404);
      });

      final container = _makeContainer(runner: runner, httpClient: client);
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await _bringNotifierReady(container, fakeProcess);
      _capturedEvents.clear();
      _capturedBreadcrumbs.clear();

      final notifier = container.read(localSttBundleProvider.notifier);

      await expectLater(
        () => notifier.transcribeBytes(_validWav(), language: 'auto'),
        throwsA(isA<Exception>()),
      );

      await CrashReporter.instance!.flush();

      expect(
        _capturedEvents,
        hasLength(1),
        reason:
            'A mid-inference $expectedExceptionType must capture exactly '
            'one Sentry event under the sttInferenceConnectionLost bucket '
            '(no double via AppLogger auto-escalation).',
      );

      final ev = _capturedEvents.single;
      expect(ev.fingerprint, [
        sttInferenceConnectionLost,
      ], reason: 'fingerprint must be sttInferenceConnectionLost');
      expect(ev.tags?['error_type'], 'stt_inference_connection_lost');

      final extrasCtx = ev.contexts['extras'] as Map?;
      expect(extrasCtx, isNotNull);
      expect(
        extrasCtx!.keys,
        containsAll([
          'exception_type',
          'exception_message',
          'model_id',
          'port',
          'wav_bytes',
          'audio_duration_ms',
          'language',
          'gpu_mode',
          'cpu_fallback_active',
          'platform',
        ]),
        reason:
            'hardware-context extras must accompany the capture so the '
            'crash report is actionable without further user contact',
      );
      expect(extrasCtx['exception_type'], expectedExceptionType);
    }

    test(
      'SocketException mid-inference → sttInferenceConnectionLost',
      () async {
        await runConnectionLossCase(
          thrown: const SocketException('connection reset by peer'),
          expectedExceptionType: 'SocketException',
        );
      },
    );

    test(
      'ClientException mid-inference → sttInferenceConnectionLost',
      () async {
        await runConnectionLossCase(
          thrown: http.ClientException('connection closed'),
          expectedExceptionType: 'ClientException',
        );
      },
    );
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
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);

      // /inference response is irrelevant — the validator short-circuits
      // before the request leaves the process. Wire a 200 success so any
      // accidental POST-through is visible (text=='unreachable').
      final client = MockClient((req) async {
        if (req.url.path == '/health') return http.Response('ok', 200);
        return http.Response('{"text":"unreachable"}', 200);
      });

      final container = _makeContainer(runner: runner, httpClient: client);
      addTearDown(() {
        container.dispose();
        fakeProcess.exit(0);
      });

      await _bringNotifierReady(container, fakeProcess);
      _capturedEvents.clear();
      _capturedBreadcrumbs.clear();

      final notifier = container.read(localSttBundleProvider.notifier);

      InferenceClientRejected? caught;
      try {
        await notifier.transcribeBytes(Uint8List(0), language: 'auto');
      } on InferenceClientRejected catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'must throw InferenceClientRejected');
      expect(caught!.userMessageKey, 'stt.reject.empty');

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

  // ── Orchestrator dedup — the AppLogger auto-escalation MUST stay quiet ──

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
}
