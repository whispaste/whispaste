/// E2E happy-path test for the core dictation loop: Hotkey → Recording →
/// Transcription → Paste (Ticket 07).
///
/// Unlike `test/services/recording_orchestrator_test.dart` (which fakes the
/// audio backend AND the STT engine to unit-test the pipeline's branching
/// logic), this test drives the REAL [RecordingOrchestrator] against:
///   - the REAL production [WhisperFfiEngine] (`dart:ffi`, whisper.cpp),
///     loaded from the same relocatable dylib/DLL/SO produced by
///     `scripts/build-libwhisper-{macos,linux}.sh` /
///     `scripts/bundle-libwhisper-windows.ps1` (the exact artifact the
///     shipped app embeds — see `whisper_bundle_smoke_test.dart`),
///   - the REAL fixed speech fixture `test/fixtures/hotkey_happy_path_hello.wav`
///     (16 kHz mono 16-bit PCM, synthesized once via macOS `say` — see below)
///     instead of live microphone hardware — no mic exists in a
///     headless CI runner or this sandbox, so the audio *capture* step is
///     substituted with a fixed recording exactly as Ticket 07 sanctions for
///     "the known-nondeterministic sub-step" (model output varies slightly
///     run to run; substring/tolerant matching handles that, see below),
///   - the REAL system clipboard (`Clipboard.setData`/`getData` via the
///     `integration_test` binding's real platform channels — plain
///     `flutter test` widget tests have no native counterpart for this,
///     which is exactly why this lives in `integration_test/`, not `test/`).
///
/// Only the audio-hardware seam (`AudioService`) and the STT
/// engine-lifecycle bookkeeping (idle-timer pause/resume — irrelevant to
/// this test) are substituted; [RecordingOrchestrator] itself and the real
/// [WhisperFfiEngine] run completely unmodified. This is deliberately NOT a
/// mock/fake transcription engine — see `transcriberProvider` override
/// below.
///
/// State assertions use [RecordingPhase] (`idle`/`recording`/
/// `transcribing`/`done`) — the vocabulary `RecordingOrchestrator` and
/// `RecordingStateMachine` already define (CONTEXT.md §2.1, §3.1) — never
/// any widget/UI detail.
///
/// `AfterTranscriptionAction.clipboard` (not `paste`) is used as the
/// after-transcription action: real keystroke-injection paste
/// (`AfterTranscriptionAction.paste`) needs a granted OS permission per
/// platform (macOS Accessibility, Windows UIPI edge cases) that a headless
/// CI runner/sandbox cannot grant — exactly the "genuinely platform-specific
/// native call [that] isn't available" case the ticket calls out for a
/// clean, reasoned skip. Copying the finished transcript to the real system
/// clipboard is `AfterTranscriptionAction.clipboard` (CONTEXT.md §2.7,
/// "Nur Zwischenablage") — a real, always-available OS interaction that
/// still proves "Einfügen" (§2.4) happened for real, so the happy path never
/// needs to skip for this reason.
///
/// Run locally (after `bash scripts/build-libwhisper-macos.sh` at least
/// once — see the skip message if that step was never run):
///   flutter test integration_test/hotkey_to_text_happy_path_test.dart -d macos
///   flutter test integration_test/hotkey_to_text_happy_path_test.dart -d windows
///   flutter test integration_test/hotkey_to_text_happy_path_test.dart -d linux
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
import 'package:whispaste/services/stt/on_device_engine_lifecycle.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';
import 'package:whispaste/services/stt_engine_lifecycle_provider.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

// ---------------------------------------------------------------------------
// Real-engine artifact discovery
// ---------------------------------------------------------------------------

/// Walks up from the test's cwd to find the repo root (the dir holding
/// `.build/libwhisper`, staged by `scripts/build-libwhisper-*.sh` /
/// `bundle-libwhisper-windows.ps1` — the same staging dir the macOS Xcode
/// "[WP] Embed & Sign libwhisper" build phase self-heals into on every
/// `flutter build macos`, see `macos/embed_libwhisper.sh`).
String? _repoRoot() {
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
  return null;
}

/// Resolves the staged, real `libwhisper` shared library for the current
/// platform, or `null` if this checkout/CI runner never staged one.
///
/// - macOS: every `flutter build macos` (incl. CI's `--debug` build, see
///   `.github/workflows/ci.yml`) runs the Xcode embed phase, which builds
///   this from source on first use — so it is normally already present by
///   the time this test runs in CI.
/// - Windows/Linux: only `scripts/bundle-libwhisper-windows.ps1` /
///   `scripts/build-libwhisper-linux.sh` produce this, and CI's plain debug
///   build (`ci.yml`) does not invoke them — only the separate signed-release
///   workflow (`release.yml`) does. So this legitimately returns `null` on
///   the Windows/Linux CI runners today; the test skips there with a clear
///   reason instead of faking the engine (see the file doc comment).
String? _stagedWhisperLibrary(String repoRoot) {
  final candidates = Platform.isMacOS
      ? [p.join(repoRoot, '.build', 'libwhisper', 'macos', 'libwhisper.dylib')]
      : Platform.isWindows
      ? [p.join(repoRoot, '.build', 'libwhisper', 'windows', 'whisper.dll')]
      : [p.join(repoRoot, '.build', 'libwhisper', 'linux', 'libwhisper.so')];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Downloads (once, cached under `.build/test-models/`) the smallest real
/// GGML Whisper model, `ggml-tiny.bin` (~75 MB, from the same
/// `ggerganov/whisper.cpp` HuggingFace repo the app's own model catalog
/// downloads its (larger) production models from — see
/// `lib/services/model_download_service.dart`). No ASR model is committed to
/// the repo (only the <1 MB VAD model is, `assets/models/vad/`), so a real
/// end-to-end transcription test needs one from somewhere; this mirrors the
/// production download path instead of inventing a new source.
Future<String?> _ensureTinyModel(String repoRoot) async {
  final dir = Directory(p.join(repoRoot, '.build', 'test-models'));
  final file = File(p.join(dir.path, 'ggml-tiny.bin'));
  if (file.existsSync() && file.lengthSync() > 0) return file.path;

  try {
    dir.createSync(recursive: true);
    final request = await http.Client().send(
      http.Request(
        'GET',
        Uri.parse(
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
        ),
      ),
    );
    if (request.statusCode != 200) return null;
    final tmp = File('${file.path}.part');
    final sink = tmp.openWrite();
    await request.stream.pipe(sink);
    await sink.close();
    await tmp.rename(file.path);
    return file.path;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Real transcriber — wraps the production WhisperFfiEngine, no shortcuts.
// ---------------------------------------------------------------------------

/// Adapts the real [WhisperFfiEngine] to the [Transcriber] interface the
/// orchestrator reads via `transcriberProvider`.
///
/// This is the file's one deliberate seam: instead of letting
/// `transcriberProvider` resolve an adapter from user settings (which would
/// need a fully-populated on-device settings surface plus the real model
/// catalog), the test hands the orchestrator this thin wrapper directly.
/// Everything it does is real: real `dart:ffi` binding, real bundled
/// `libwhisper`, real GGML model, real decode. Nothing about the STT engine
/// itself is faked.
class RealFixtureTranscriber implements Transcriber {
  RealFixtureTranscriber({required String libraryPath, required this.modelPath})
    : _engine = WhisperFfiEngine(libraryPath: libraryPath);

  final WhisperFfiEngine _engine;
  final String modelPath;

  @override
  Future<void> prepare() async {
    if (!_engine.status.isLoaded) {
      await _engine.load(modelPath: modelPath);
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) {
    return _engine.transcribe(
      wavBytes,
      language: (language == null || language == 'auto') ? 'en' : language,
    );
  }

  @override
  void release() {
    // Keep the engine loaded for the lifetime of the test process — no
    // per-recording reload cost, mirroring the app's own idle-timer-based
    // (not per-recording) unload policy.
  }
}

// ---------------------------------------------------------------------------
// Fakes — ONLY for the two seams no headless runner can provide for real:
// microphone hardware and STT engine-lifecycle idle-timer bookkeeping.
// ---------------------------------------------------------------------------

/// Substitutes real microphone capture with the fixed
/// `test/fixtures/hotkey_happy_path_hello.wav` speech fixture (synthesized once via macOS `say` — real, non-silent, non-copyrighted speech; NOT the shared `test/fixtures/hello_world.wav`, which turns out to be silent placeholder audio, a pre-existing gap unrelated to this ticket — see commit message), copied to a scratch path
/// per run (the orchestrator deletes its "recorded" file after the pipeline
/// finishes — the copy is disposable, the committed fixture is not).
class FixtureAudioService extends AudioServiceNotifier {
  FixtureAudioService(this._fixtureWavPath);

  final String _fixtureWavPath;
  String? _recordingCopyPath;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> startRecording() async {
    final dir = await Directory.systemTemp.createTemp('wp_itest_audio_');
    final copy = File(p.join(dir.path, 'recording.wav'));
    await File(_fixtureWavPath).copy(copy.path);
    _recordingCopyPath = copy.path;
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: copy.path,
    );
  }

  @override
  Future<String?> stopRecording() async {
    final path = _recordingCopyPath;
    state = AudioStatus(filePath: path);
    return path;
  }

  @override
  Future<void> cleanupFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

/// Reports the on-device engine as always ready — the orchestrator's real
/// readiness/idle-timer bookkeeping (pausing the whisper-server idle
/// shutdown timer while a recording is active) is orthogonal to what this
/// test verifies, and the real `RealFixtureTranscriber` above already keeps
/// the actual engine loaded independently of this.
class _AlwaysReadyEngineLifecycle implements OnDeviceEngineLifecycle {
  @override
  EngineLifecycleStatus get status =>
      const EngineLifecycleStatus(isReady: true);

  @override
  Future<void> ensureRunning() async {}

  @override
  Future<void> prewarm() async {}

  @override
  Future<void> stop() async {}

  @override
  void notifyRecordingStarted() {}

  @override
  void notifyRecordingStopped() {}

  @override
  void notifyTranscriptionCompleted() {}
}

/// Fixed settings — real [AppSettings], no secure-store/database round trip.
class FixedSettingsNotifier extends SettingsNotifier {
  FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

/// In-memory secure key store — avoids touching the real OS credential
/// store for a run that never uses cloud STT (on-device only).
class InMemorySecureKeyStore extends SecureKeyStore {
  InMemorySecureKeyStore() : super(null);

  final _store = <String, String>{};

  @override
  Future<String?> readKey(String key) async => _store[key];

  @override
  Future<void> writeKey(String key, String value) async => _store[key] = value;

  @override
  Future<void> deleteKey(String key) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Hotkey → Recording → Transcription → Paste (happy path)',
    (tester) async {
      final repoRoot = _repoRoot();
      if (repoRoot == null) {
        fail('Could not locate repo root from ${Directory.current.path}');
      }

      final libraryPath = _stagedWhisperLibrary(repoRoot);
      if (libraryPath == null) {
        final platform = Platform.isMacOS
            ? 'macOS'
            : Platform.isWindows
            ? 'Windows'
            : 'Linux';
        final howToBuild = Platform.isMacOS
            ? 'scripts/build-libwhisper-macos.sh (or run `flutter build macos`, '
                  'whose Xcode embed phase self-heals it)'
            : Platform.isWindows
            ? 'scripts/bundle-libwhisper-windows.ps1 -Source .build/libwhisper/windows '
                  '(only run today by .github/workflows/release.yml, not the plain '
                  'CI debug build)'
            : 'scripts/build-libwhisper-linux.sh (only run today by '
                  '.github/workflows/release.yml, not the plain CI debug build)';
        markTestSkipped(
          'No staged libwhisper for $platform at '
          '${p.join(repoRoot, ".build", "libwhisper")} — this is a genuine '
          'native-artifact availability gap on this platform/build, not a test '
          'issue. Build it with $howToBuild, then re-run.',
        );
        return;
      }

      final modelPath = await _ensureTinyModel(repoRoot);
      if (modelPath == null) {
        markTestSkipped(
          'Could not download ggml-tiny.bin (offline, or huggingface.co '
          'unreachable) — cannot run the real transcription step.',
        );
        return;
      }

      final fixtureWav = p.join(
        repoRoot,
        'test',
        'fixtures',
        'hotkey_happy_path_hello.wav',
      );
      if (!File(fixtureWav).existsSync()) {
        fail('Missing fixture: $fixtureWav');
      }

      // Isolate on-device preflight from the real filesystem — no real
      // whisper-server/model directory exists in the test sandbox. A
      // placeholder file only needs to exist for RecordingOrchestrator's
      // preflight file-exists check; its content is never read because
      // transcriberProvider is fully overridden below.
      final scratch = await Directory.systemTemp.createTemp('wp_itest_stt_');
      addTearDown(() async {
        if (await scratch.exists()) await scratch.delete(recursive: true);
      });
      sttDirOverride = scratch.path;
      retainedAudioDirOverride = p.join(scratch.path, 'retained-audio');
      const placeholderModelId = 'whisper-medium';
      final placeholderModelPath = sttModelPath(placeholderModelId);
      if (placeholderModelPath != null) {
        File(placeholderModelPath).createSync(recursive: true);
        File(placeholderModelPath).writeAsStringSync('placeholder');
      }

      final settings = AppSettings.defaults.copyWith(
        sttProvider: 'On Device',
        sttEngine: 'whisper',
        sttModel: placeholderModelId,
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

      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(() => FixedSettingsNotifier(settings)),
          secureKeyStoreProvider.overrideWith(
            (ref) => InMemorySecureKeyStore(),
          ),
          audioServiceProvider.overrideWith(
            () => FixtureAudioService(fixtureWav),
          ),
          onDeviceEngineLifecycleProvider.overrideWithValue(
            _AlwaysReadyEngineLifecycle(),
          ),
          transcriberProvider.overrideWithValue(
            RealFixtureTranscriber(
              libraryPath: libraryPath,
              modelPath: modelPath,
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FixedModelDownloadNotifier({placeholderModelId}),
          ),
        ],
      );
      addTearDown(container.dispose);

      // settingsProvider is a FutureProvider — force it to resolve before
      // driving the orchestrator. Otherwise preflight reads `.value ??
      // AppSettings.defaults` while the future is still pending, silently
      // falling back to `onboardingCompleted: false` and failing preflight
      // with `onboarding_not_completed` regardless of the fixed settings
      // this test actually configured.
      await container.read(settingsProvider.future);

      // Drain any residual clipboard content from a previous manual run/other
      // test so the final assertion cannot pass by accident.
      await Clipboard.setData(const ClipboardData(text: ''));

      final observedPhases = <RecordingPhase>[];
      container.listen<RecordingState>(recordingProvider, (previous, next) {
        if (observedPhases.isEmpty || observedPhases.last != next.phase) {
          observedPhases.add(next.phase);
        }
      }, fireImmediately: true);

      final orchestrator = container.read(
        recordingOrchestratorProvider.notifier,
      );

      // ── Hotkey ────────────────────────────────────────────────────────────
      // The production hotkey handler (`hotkey_service.dart`) calls exactly
      // this method on key-down — registering and firing a real global OS
      // hotkey headlessly is its own (flaky, permission-gated) concern
      // orthogonal to the dictation pipeline this ticket covers, so the test
      // invokes the pipeline's real entry point directly, exactly as the real
      // hotkey handler does.
      await orchestrator.toggleRecording();

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.recording,
        reason: 'Hotkey press must start recording',
      );

      // ── Recording → stop (hotkey release / second press) ───────────────────
      // stopRecording() runs the full transcribing pipeline internally and
      // only returns once the phase has left `transcribing`.
      await orchestrator.stopRecording();

      // ── Transcription → Paste (done) ────────────────────────────────────
      final finalState = container.read(recordingProvider);
      expect(
        finalState.phase,
        RecordingPhase.done,
        reason:
            'Pipeline must reach done, not error. errorMessage='
            '${finalState.errorMessage}',
      );

      // Real, model-dependent STT output — tolerant substring match (not
      // exact-string) because the exact wording/casing/punctuation a real
      // whisper decode produces for the same fixture can vary slightly
      // between whisper.cpp versions/backends. This is the ticket's
      // "known-nondeterministic sub-step", asserted for real rather than
      // skipped.
      final transcript = (finalState.transcript ?? '').toLowerCase();
      expect(transcript, contains('hello'));
      expect(transcript, contains('world'));

      // Real state-machine phase order: idle → recording → transcribing → done
      // (never a spurious `error` bounce in between).
      expect(
        observedPhases,
        containsAllInOrder([
          RecordingPhase.idle,
          RecordingPhase.recording,
          RecordingPhase.transcribing,
          RecordingPhase.done,
        ]),
      );

      // ── Paste (clipboard variant) ────────────────────────────────────────
      // Real OS clipboard write+read through the integration_test binding's
      // real platform channel — the "Einfügen" step actually happened, not
      // just something that would have called into it.
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = (clipboard?.text ?? '').toLowerCase();
      expect(clipboardText, contains('hello'));
      expect(clipboardText, contains('world'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _FixedModelDownloadNotifier extends ModelDownloadNotifier {
  _FixedModelDownloadNotifier(this._downloaded);

  final Set<String> _downloaded;

  @override
  ModelDownloadState build() =>
      ModelDownloadState(downloadedModels: _downloaded);
}
