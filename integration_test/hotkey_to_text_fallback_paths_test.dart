/// E2E fault-injection tests for the Recording Orchestrator's documented
/// resilience paths (Ticket 08): retry-after-transient-error, GPU→CPU
/// fallback, and CUDA-OOM recovery.
///
/// These build on the ticket-07 happy-path suite
/// (`hotkey_to_text_happy_path_test.dart`) and reuse its fixtures
/// ([FixtureAudioService], [FixedSettingsNotifier], [InMemorySecureKeyStore])
/// via a `show` import, but differ in one important way: ticket 07 overrides
/// `transcriberProvider` directly with a thin wrapper around the REAL
/// [WhisperFfiEngine] (`RealFixtureTranscriber`), which bypasses
/// [SttServerStateNotifier] entirely — the resilience logic under test here
/// lives *inside* that notifier (`_transcribeResilient` in
/// `stt_server_state_notifier.dart`), not in the FFI engine itself. So these
/// tests instead let `transcriberProvider` resolve normally to the real
/// [LocalSttTranscriber] → [SttServerStateNotifier] chain, and inject faults
/// one seam lower, at [whisperEngineProvider] — swapping in
/// [_FaultInjectingWhisperEngine] instead of the production
/// `WhisperIsolateEngine`/`WhisperFfiEngine`. Everything above that seam
/// (orchestrator, state machine, notifier's retry/CPU-fallback/OOM-handoff
/// logic, [OomRecoveryHandler], settings, clipboard) is the real, unmodified
/// production code path.
///
/// This mirrors the existing unit-level fixture `_FakeWhisperEngine` in
/// `test/services/stt/stt_resilience_test.dart` (which drives
/// [SttServerStateNotifier] directly, without the orchestrator/state-machine/
/// UI-facing layers this ticket asks for) — same fault-injection shape, one
/// layer higher.
///
/// Production logic exercised per scenario (see `stt_server_state_notifier
/// .dart`'s `_transcribeResilient` and `recording_orchestrator.dart`'s
/// `_handleOomRecovery`):
///   - **Retry**: [WhisperFailureKind.transient] is retried in-place, up to
///     `_maxTranscribeRetries` (3) times, fully transparent to the
///     orchestrator — the pipeline never leaves `transcribing` for `error`.
///   - **GPU→CPU fallback**: [WhisperFailureKind.gpuCrash] sets
///     `cpuFallbackActive` and retries once on CPU, also transparent to the
///     orchestrator.
///   - **OOM recovery**: [WhisperFailureKind.oom] is NOT retried by the
///     notifier — it rethrows immediately carrying the `stt_cuda_oom` token.
///     The orchestrator's [OomRecoveryHandler] catches this, resets the
///     pipeline to `idle` (not `error` — `RecordingIntent.reset` is allowed
///     from every phase, see `recording_state_machine.dart`), and publishes
///     a pending recovery decision via `oomRecoveryPendingProvider`
///     (a lighter local model here, since one is configured as already
///     downloaded). The test then drives the real user recovery action
///     (`RecordingOrchestrator.applyOomModelFallback`) and proves a
///     subsequent recording actually completes on the fallback model.
///
/// Unlike the ticket-07 happy path, none of this needs the real bundled
/// `libwhisper` — the fault is injected below the FFI boundary, so these
/// tests run for real on every platform (no skip).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart'
    show sttDirOverride, sttModelPath, retainedAudioDirOverride;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

import 'hotkey_to_text_happy_path_test.dart'
    show FixtureAudioService, FixedSettingsNotifier, InMemorySecureKeyStore;

// ---------------------------------------------------------------------------
// Repo-root / fixture discovery — duplicated in miniature from the
// ticket-07 file (that helper is private there) since it is only a few
// lines and this file has no other dependency on that test's internals.
// ---------------------------------------------------------------------------

String _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'integration_test')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate repo root from ${Directory.current.path}');
}

// ---------------------------------------------------------------------------
// Fault-injecting WhisperEngine — the seam this ticket's fault injection
// hooks into. See file doc comment.
// ---------------------------------------------------------------------------

/// A [WhisperEngine] fake that starts benign (so the notifier's initial
/// model load + warmup succeed) and can be armed to fail the next
/// [count] `transcribe()` calls with [kind] before reverting to success —
/// letting a test observe the notifier's real in-place retry/CPU-fallback
/// behavior, or its immediate OOM handoff, without ever touching real
/// libwhisper/GPU/memory.
class _FaultInjectingWhisperEngine implements WhisperEngine {
  String transcript = 'hello world';
  bool _loaded = false;

  WhisperFailureKind? _armedKind;
  int _remainingFailures = 0;

  /// Total `transcribe()` calls made while a fault was armed (including the
  /// failing ones) — lets a test assert exactly how many attempts the
  /// notifier made for one armed scenario.
  int armedCallCount = 0;

  /// Fails the next [count] `transcribe()` calls with [kind], then reverts
  /// to returning [transcript] successfully.
  void armFailures(WhisperFailureKind kind, int count) {
    armedCallCount = 0;
    _armedKind = kind;
    _remainingFailures = count;
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
    bool reducedThreads = false,
  }) async {
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
    // The OOM message must carry the `stt_cuda_oom` token — the
    // orchestrator's OomRecoveryHandler keys on it (see
    // `recording_orchestrator.dart`'s `_handleTranscribeResult`).
    WhisperFailureKind.oom => 'stt_cuda_oom: simulated GPU out-of-memory',
    WhisperFailureKind.gpuCrash => 'simulated GPU backend crash',
    WhisperFailureKind.transient => 'simulated transient inference failure',
    WhisperFailureKind.timeout => 'simulated timeout',
    WhisperFailureKind.other => 'simulated other failure',
  };
}

/// Fixed downloaded-models set — the OOM-recovery scenario needs a lighter
/// (compact-tier) model already "downloaded" for
/// `RecordingOrchestrator._nextAvailableFallbackModelId` to offer it.
class _FixedModelDownloadNotifier extends ModelDownloadNotifier {
  _FixedModelDownloadNotifier(this._downloaded);

  final Set<String> _downloaded;

  @override
  ModelDownloadState build() =>
      ModelDownloadState(downloadedModels: _downloaded);
}

// ---------------------------------------------------------------------------
// Shared setup
// ---------------------------------------------------------------------------

const _balancedModelId = 'whisper-medium';
const _compactModelId = 'whisper-small';

/// Writes a placeholder GGML file for [modelId] under [sttDir], large
/// enough (>10 MB) to pass `SttServerStateNotifier`'s corrupted-file-size
/// guard. Content is never read — the engine is fully faked — only
/// existence/size matters for preflight + `_start`.
void _writePlaceholderModel(String sttDir, String modelId) {
  final path = sttModelPath(modelId);
  if (path == null) fail('Unknown model id in catalog: $modelId');
  File(path).writeAsBytesSync(Uint8List(11 * 1024 * 1024));
}

AppSettings _baseSettings({required String modelId}) =>
    AppSettings.defaults.copyWith(
      sttProvider: 'On Device',
      sttEngine: 'whisper',
      sttModel: modelId,
      sttLanguage: 'en',
      afterTranscription: 'clipboard',
      onboardingCompleted: true,
      hotkeyEnabled: true,
      hotkeyKey: 'D',
      hotkeyModifiers: 'ctrl+shift',
      checkUpdates: false,
      errorReporting: false,
      retainRecentAudio: false,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory sttScratchDir;
  late Duration savedBenchmarkIdleDelay;

  setUp(() {
    // Freeze the deferred post-load benchmark far outside every test's
    // lifetime. `SttServerStateNotifier._start` schedules it right after a
    // (re)load; left at its production 2 s default it would eventually fire
    // its own unrelated `WhisperEngine.transcribe()` call against the very
    // same fake engine these tests arm, racing the assertions below.
    savedBenchmarkIdleDelay = SttServerStateNotifier.benchmarkIdleDelay;
    SttServerStateNotifier.benchmarkIdleDelay = const Duration(hours: 1);
  });

  tearDown(() {
    SttServerStateNotifier.benchmarkIdleDelay = savedBenchmarkIdleDelay;
  });

  /// Builds a fresh container + orchestrator wired exactly like ticket 07's
  /// happy path, except: (1) the fault-injecting engine sits behind
  /// [whisperEngineProvider] instead of ticket 07's real-engine override of
  /// `transcriberProvider`, and (2) `onDeviceEngineLifecycleProvider` is
  /// left un-overridden so the REAL [WhisperEngineLifecycleAdapter] runs —
  /// necessary for `SttServerStateNotifier._isRecordingActive` bookkeeping
  /// (and hence the benchmark-deferral guard above) to reflect reality.
  Future<
    (
      ProviderContainer container,
      RecordingOrchestrator orchestrator,
      _FaultInjectingWhisperEngine engine,
      List<RecordingPhase> observedPhases,
    )
  >
  buildHarness({required AppSettings settings}) async {
    sttScratchDir = await Directory.systemTemp.createTemp('wp_itest_fault_');
    addTearDown(() async {
      if (await sttScratchDir.exists()) {
        await sttScratchDir.delete(recursive: true);
      }
    });
    sttDirOverride = sttScratchDir.path;
    retainedAudioDirOverride = p.join(sttScratchDir.path, 'retained-audio');
    _writePlaceholderModel(sttScratchDir.path, _balancedModelId);
    _writePlaceholderModel(sttScratchDir.path, _compactModelId);

    final repoRoot = _repoRoot();
    final fixtureWav = p.join(
      repoRoot,
      'test',
      'fixtures',
      'hotkey_happy_path_hello.wav',
    );
    if (!File(fixtureWav).existsSync()) {
      fail('Missing fixture: $fixtureWav');
    }

    final engine = _FaultInjectingWhisperEngine();
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWith(() => FixedSettingsNotifier(settings)),
        secureKeyStoreProvider.overrideWith((ref) => InMemorySecureKeyStore()),
        audioServiceProvider.overrideWith(
          () => FixtureAudioService(fixtureWav),
        ),
        whisperEngineProvider.overrideWithValue(engine),
        modelDownloadProvider.overrideWith(
          () =>
              _FixedModelDownloadNotifier({_balancedModelId, _compactModelId}),
        ),
      ],
    );
    addTearDown(container.dispose);

    // See the ticket-07 happy-path test for why this await is required:
    // settingsProvider is a FutureProvider, and driving the orchestrator
    // before it resolves silently falls back to `AppSettings.defaults`
    // (onboardingCompleted: false), failing preflight.
    await container.read(settingsProvider.future);

    final observedPhases = <RecordingPhase>[];
    container.listen<RecordingState>(recordingProvider, (previous, next) {
      if (observedPhases.isEmpty || observedPhases.last != next.phase) {
        observedPhases.add(next.phase);
      }
    }, fireImmediately: true);

    final orchestrator = container.read(recordingOrchestratorProvider.notifier);
    return (container, orchestrator, engine, observedPhases);
  }

  /// Runs one full hotkey-press → release cycle through the real
  /// orchestrator, exactly as the production hotkey handler does.
  Future<void> runRecordingCycle(RecordingOrchestrator orchestrator) async {
    await orchestrator.toggleRecording();
    await orchestrator.stopRecording();
  }

  testWidgets(
    'retry path: a transient transcription error is retried in-place and '
    'the pipeline completes without ever surfacing an error phase',
    (tester) async {
      final (
        container,
        orchestrator,
        engine,
        observedPhases,
      ) = await buildHarness(
        settings: _baseSettings(modelId: _balancedModelId),
      );

      // Prime the engine to "ready" with one benign cycle first — the
      // model-load/warmup inference (also a `transcribe()` call) must not
      // consume the fault armed below for the real scenario.
      await runRecordingCycle(orchestrator);
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      engine.armFailures(WhisperFailureKind.transient, 1);
      await runRecordingCycle(orchestrator);

      final finalState = container.read(recordingProvider);
      expect(
        finalState.phase,
        RecordingPhase.done,
        reason:
            'a transient failure must be retried transparently, not surfaced. '
            'errorMessage=${finalState.errorMessage}',
      );
      expect((finalState.transcript ?? '').toLowerCase(), contains('hello'));
      expect(
        engine.armedCallCount,
        2,
        reason: 'one failing attempt + one successful in-place retry',
      );
      expect(
        observedPhases,
        isNot(contains(RecordingPhase.error)),
        reason: 'the retry is transparent to the orchestrator/state machine',
      );
    },
  );

  testWidgets(
    'GPU→CPU fallback path: a simulated GPU crash degrades the backend to '
    'CPU and the pipeline completes on the CPU retry',
    (tester) async {
      final (
        container,
        orchestrator,
        engine,
        observedPhases,
      ) = await buildHarness(
        settings: _baseSettings(modelId: _balancedModelId),
      );

      await runRecordingCycle(orchestrator);
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      engine.armFailures(WhisperFailureKind.gpuCrash, 1);
      await runRecordingCycle(orchestrator);

      final finalState = container.read(recordingProvider);
      expect(
        finalState.phase,
        RecordingPhase.done,
        reason:
            'a GPU crash must degrade to CPU and retry, not surface. '
            'errorMessage=${finalState.errorMessage}',
      );
      expect((finalState.transcript ?? '').toLowerCase(), contains('hello'));
      expect(
        engine.armedCallCount,
        2,
        reason: 'one crashing GPU attempt + one successful CPU retry',
      );
      expect(
        container.read(localSttBundleProvider).cpuFallbackActive,
        isTrue,
        reason: 'cpuFallbackActive must be set after a GPU crash',
      );
      expect(
        observedPhases,
        isNot(contains(RecordingPhase.error)),
        reason: 'the CPU fallback is transparent to the orchestrator',
      );
    },
  );

  testWidgets(
    'OOM-recovery path: a simulated CUDA OOM resets to idle, offers a '
    'lighter local model, and a subsequent recording on that model completes',
    (tester) async {
      final (
        container,
        orchestrator,
        engine,
        observedPhases,
      ) = await buildHarness(
        settings: _baseSettings(modelId: _balancedModelId),
      );

      await runRecordingCycle(orchestrator);
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      engine.armFailures(WhisperFailureKind.oom, 1);
      await runRecordingCycle(orchestrator);

      // OOM must reset to idle, not error — RecordingIntent.reset is
      // allowed from every phase specifically for this recovery.
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.idle,
        reason: 'OOM recovery resets the pipeline to idle, not error',
      );
      expect(
        observedPhases,
        isNot(contains(RecordingPhase.error)),
        reason: 'OOM recovery never bounces through the error phase',
      );

      final pending = container.read(oomRecoveryPendingProvider);
      expect(pending.pending, isTrue);
      expect(
        pending.nextModelId,
        _compactModelId,
        reason:
            'the compact-tier model is configured as already downloaded, '
            'so OomRecoveryHandler must offer it before cloud/give-up',
      );
      expect(pending.isPermanentFail, isFalse);

      final applied = await orchestrator.applyOomModelFallback(
        pending.nextModelId!,
      );
      expect(applied, isTrue);
      expect(container.read(settingsProvider).value?.sttModel, _compactModelId);
      expect(container.read(oomRecoveryPendingProvider).pending, isFalse);

      // The user re-triggers the hotkey — same real orchestrator entry
      // point production code uses. The armed OOM failure was already
      // consumed above, so the fake engine now succeeds unconditionally,
      // proving the fallback model actually completes a recording.
      await runRecordingCycle(orchestrator);

      final finalState = container.read(recordingProvider);
      expect(
        finalState.phase,
        RecordingPhase.done,
        reason:
            'the retried recording on the fallback model must complete. '
            'errorMessage=${finalState.errorMessage}',
      );
      expect((finalState.transcript ?? '').toLowerCase(), contains('hello'));
    },
  );
}
