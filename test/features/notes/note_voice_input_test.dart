/// Tests for [WpVoiceInputButton] as the note editor uses it (Ticket 08).
///
/// Vorbild `voice_actions_test.dart`'s `VoiceNoteButton — via FFI engine
/// seam` group: fake [AudioServiceNotifier]/[SttServerStateNotifier]/
/// [RecordingOrchestrator] subclasses that override the pipeline methods, so
/// the real `record`/whisper-engine plugins are never touched. The button's
/// `_stopAndTranscribe` reads the WAV off real disk (`dart:io File`) — a
/// genuine async gap flutter_test's FakeAsync zone cannot resolve via
/// `pump()` alone, so every full record→stop→transcribe cycle taps inside
/// `tester.runAsync()` to let real I/O (and the shrunk real-time
/// `.timeout()` in the timeout tests) actually complete. See
/// `recordStopAndDrain` below for the exact mechanics/timing rationale.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_voice_input_button.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

// ─── Fakes ────────────────────────────────────────────────────────────────

/// Skips the real pipeline wiring (state machine, OOM handler, STT prewarm)
/// — Vorbild `test_recording_step_test.dart`'s `_FakeRecordingOrchestrator`.
/// `tryAcquireStartLock`/`releaseStartLock` themselves are plain field
/// mutations plus a `recordingProvider` phase read, so they work unchanged
/// against the real (un-overridden) `recordingProvider`'s default idle state.
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  @override
  void build() {}
}

class _FakeAudioServiceNotifier extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;
  String? cleanedUpPath;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Future<void> startRecording() async {
    if (errorOnStart) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_error',
      );
      return;
    }
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPathToReturn,
    );
  }

  @override
  Future<String?> stopRecording() async {
    state = const AudioStatus();
    return wavPathToReturn;
  }

  @override
  Future<void> cleanupFile(String? path) async {
    cleanedUpPath = path;
  }
}

class _FakeSttServerStateNotifier extends SttServerStateNotifier {
  _FakeSttServerStateNotifier({
    this.transcript = 'hello world',
    this.notReady = false,
    this.ensureRunningHangs = false,
    this.transcribeHangs = false,
    this.transcribeGate,
  });

  final String transcript;
  final bool notReady;

  /// Held open by the caller to park transcription at a chosen point — lets a
  /// test unmount the button while the transcript is still in flight.
  final Completer<void>? transcribeGate;

  /// Never completes — lets [WpVoiceInputButton.ensureRunningTimeout] fire.
  final bool ensureRunningHangs;

  /// Never completes — lets [WpVoiceInputButton.transcribeTimeout] fire.
  final bool transcribeHangs;

  bool ensureRunningCalled = false;
  bool transcribeCalled = false;

  @override
  SttStatus build() => SttStatus(
    serverState: notReady ? SttServerState.error : SttServerState.ready,
  );

  @override
  Future<void> ensureRunning() async {
    ensureRunningCalled = true;
    if (ensureRunningHangs) await Completer<void>().future;
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    transcribeCalled = true;
    if (transcribeHangs) await Completer<void>().future;
    if (transcribeGate != null) await transcribeGate!.future;
    return transcript;
  }
}

// ─── Harness ──────────────────────────────────────────────────────────────

Widget _makeTestableButton({
  required _FakeAudioServiceNotifier fakeAudio,
  required _FakeSttServerStateNotifier fakeStt,
  required ValueChanged<String> onTranscript,
}) {
  return makeTestable(
    WpVoiceInputButton(onTranscript: onTranscript),
    overrides: [
      audioServiceProvider.overrideWith(() => fakeAudio),
      localSttBundleProvider.overrideWith(() => fakeStt),
      recordingOrchestratorProvider.overrideWith(
        _FakeRecordingOrchestrator.new,
      ),
    ],
    locale: const Locale('en'),
  );
}

/// Taps to start recording, then taps again to stop+transcribe — the second
/// tap runs inside [WidgetTester.runAsync] so the real WAV-file read (and
/// any shrunk real-time `.timeout()`) can actually complete; a bare `pump()`
/// loop cannot resolve genuine `dart:io` I/O inside flutter_test's FakeAsync
/// zone. Because the tap is dispatched from inside `runAsync()`, the whole
/// downstream async chain — including a WpToast error animation — stays
/// zone-sticky to that real Zone for its entire lifetime, so [pipelineWait]
/// must cover the full toast lifecycle (~2 s auto-dismiss + reverse) too, or
/// a leftover Ticker ticks against the FakeAsync clock on a later test.
Future<void> _recordStopAndDrain(
  WidgetTester tester, {
  required Duration pipelineWait,
}) async {
  await tester.tap(find.byIcon(LucideIcons.mic));
  await tester.pump();
  expect(find.byIcon(LucideIcons.square), findsOneWidget);

  final totalRealWait = pipelineWait + const Duration(milliseconds: 2600);
  await tester.runAsync(() async {
    await tester.tap(find.byIcon(LucideIcons.square));
    await Future<void>.delayed(totalRealWait);
  });
  await tester.pump(totalRealWait);
  await tester.pump();
}

void main() {
  late Directory wavDir;
  late String wavPath;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    wavDir = await Directory.systemTemp.createTemp('note_voice_input_test_');
    wavPath = '${wavDir.path}/note.wav';
    // Non-empty is all `_stopAndTranscribe` checks for — no WAV-header
    // validation happens before the fake STT notifier's transcribeBytes.
    await File(wavPath).writeAsBytes(const [1, 2, 3, 4]);
  });

  tearDown(() async {
    await wavDir.delete(recursive: true);
  });

  testWidgets('idle state shows the mic icon and voiceNoteButton tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: _FakeAudioServiceNotifier(),
        fakeStt: _FakeSttServerStateNotifier(),
        onTranscript: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    expect(find.byTooltip(l10n.voiceNoteButton), findsOneWidget);
  });

  testWidgets('a mic error on start shows an error toast and stays idle', (
    tester,
  ) async {
    final audio = _FakeAudioServiceNotifier()..errorOnStart = true;
    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: audio,
        fakeStt: _FakeSttServerStateNotifier(),
        onTranscript: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.mic));
    await tester.pumpAndSettle();

    expect(find.text(l10n.voiceNoteError), findsOneWidget);
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets(
    'full record → transcribe cycle invokes onTranscript and cleans up the WAV',
    (tester) async {
      final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
      final stt = _FakeSttServerStateNotifier();
      String? lastTranscript;

      await tester.pumpWidget(
        _makeTestableButton(
          fakeAudio: audio,
          fakeStt: stt,
          onTranscript: (t) => lastTranscript = t,
        ),
      );
      await tester.pumpAndSettle();

      await _recordStopAndDrain(
        tester,
        pipelineWait: const Duration(milliseconds: 300),
      );

      expect(stt.ensureRunningCalled, isTrue);
      expect(stt.transcribeCalled, isTrue);
      expect(lastTranscript, 'hello world');
      expect(audio.cleanedUpPath, wavPath);
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.byIcon(LucideIcons.loader), findsNothing);
    },
  );

  testWidgets('empty transcript shows an error toast and resets to idle', (
    tester,
  ) async {
    final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
    final stt = _FakeSttServerStateNotifier(transcript: '   ');
    String? lastTranscript;

    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: audio,
        fakeStt: stt,
        onTranscript: (t) => lastTranscript = t,
      ),
    );
    await tester.pumpAndSettle();

    await _recordStopAndDrain(
      tester,
      pipelineWait: const Duration(milliseconds: 300),
    );

    expect(lastTranscript, isNull);
    expect(find.text(l10n.voiceNoteEmpty), findsOneWidget);
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
  });

  testWidgets('STT not ready after ensureRunning shows an error toast', (
    tester,
  ) async {
    final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
    final stt = _FakeSttServerStateNotifier(notReady: true);
    String? lastTranscript;

    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: audio,
        fakeStt: stt,
        onTranscript: (t) => lastTranscript = t,
      ),
    );
    await tester.pumpAndSettle();

    await _recordStopAndDrain(
      tester,
      pipelineWait: const Duration(milliseconds: 300),
    );

    expect(lastTranscript, isNull);
    expect(find.text(l10n.voiceNoteError), findsOneWidget);
  });

  testWidgets(
    'a transcript that lands after the button is gone is dropped, not handed '
    'into a dead tree',
    (tester) async {
      // Transcription may run for up to transcribeTimeout (45 s in
      // production), and the surface around the button can vanish meanwhile:
      // the detail panel closes, the entry is deleted, another item is
      // selected. Both sinks grab `context`/`ref` the moment they are called,
      // so the hand-off has to be skipped rather than attempted.
      final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
      final gate = Completer<void>();
      final stt = _FakeSttServerStateNotifier(transcribeGate: gate);
      var handOffs = 0;

      await tester.pumpWidget(
        _makeTestableButton(
          fakeAudio: audio,
          fakeStt: stt,
          onTranscript: (_) => handOffs++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.mic));
      await tester.pump();

      // Stop + transcribe, parked on the gate. `pumpWidget` is not allowed
      // inside `runAsync`, hence the two separate real-async windows.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(LucideIcons.square));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      expect(stt.transcribeCalled, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.runAsync(() async {
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(handOffs, 0);
      // The pipeline still finishes its own housekeeping — an unmount must not
      // leave the temp WAV behind.
      expect(audio.cleanedUpPath, wavPath);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ensureRunning() stuck beyond its timeout ends in a clean idle error '
    'state, not a hang',
    (tester) async {
      final originalTimeout = WpVoiceInputButton.ensureRunningTimeout;
      WpVoiceInputButton.ensureRunningTimeout = const Duration(
        milliseconds: 100,
      );
      addTearDown(
        () => WpVoiceInputButton.ensureRunningTimeout = originalTimeout,
      );

      final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
      final stt = _FakeSttServerStateNotifier(ensureRunningHangs: true);
      String? lastTranscript;

      await tester.pumpWidget(
        _makeTestableButton(
          fakeAudio: audio,
          fakeStt: stt,
          onTranscript: (t) => lastTranscript = t,
        ),
      );
      await tester.pumpAndSettle();

      await _recordStopAndDrain(
        tester,
        pipelineWait: const Duration(milliseconds: 400),
      );

      expect(lastTranscript, isNull);
      expect(find.text(l10n.voiceNoteError), findsOneWidget);
      expect(audio.cleanedUpPath, wavPath);
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.byIcon(LucideIcons.loader), findsNothing);
    },
  );

  testWidgets(
    'transcribeBytes() stuck beyond its timeout ends in a clean idle error '
    'state, not a hang',
    (tester) async {
      final originalTimeout = WpVoiceInputButton.transcribeTimeout;
      WpVoiceInputButton.transcribeTimeout = const Duration(milliseconds: 100);
      addTearDown(() => WpVoiceInputButton.transcribeTimeout = originalTimeout);

      final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
      final stt = _FakeSttServerStateNotifier(transcribeHangs: true);
      String? lastTranscript;

      await tester.pumpWidget(
        _makeTestableButton(
          fakeAudio: audio,
          fakeStt: stt,
          onTranscript: (t) => lastTranscript = t,
        ),
      );
      await tester.pumpAndSettle();

      await _recordStopAndDrain(
        tester,
        pipelineWait: const Duration(milliseconds: 400),
      );

      expect(lastTranscript, isNull);
      expect(find.text(l10n.voiceNoteError), findsOneWidget);
      expect(audio.cleanedUpPath, wavPath);
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    },
  );
}
