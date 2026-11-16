/// Tests for [WpVoiceInputButton] as the note editor uses it (Ticket 08).
///
/// Vorbild `voice_actions_test.dart`'s `VoiceNoteButton — via FFI engine
/// seam` group: fake [AudioServiceNotifier]/[SttServerStateNotifier]/
/// [RecordingOrchestrator] subclasses that override the pipeline methods, so
/// the real `record`/whisper-engine plugins are never touched. The button's
/// `_stopAndTranscribe` reads the WAV off real disk (`dart:io File`) — a
/// genuine async gap flutter_test's FakeAsync zone cannot resolve via
/// `pump()` alone, so every record→stop→transcribe cycle gives the real
/// event loop turns until the pipeline is done, while the shrunk timeouts
/// and the toasts run on the fake clock. See `_recordStopAndDrain` below.
library;

// test_bundles: own run (real WAV I/O; hung 39 s in a bundle on the lab, run
// 2845).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/widgets/wp_voice_input_button.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/pump_until.dart';

late L10n l10n;

// ─── Fakes ────────────────────────────────────────────────────────────────

/// Skips the real pipeline wiring (state machine, OOM handler, STT prewarm)
/// — Vorbild `test_recording_step_test.dart`'s `_FakeRecordingOrchestrator`.
/// `tryAcquireStartLock`/`releaseStartLock` themselves are plain field
/// mutations plus a `recordingProvider` phase read, so they work unchanged
/// against the real (un-overridden) `recordingProvider`'s default idle state.
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  _FakeRecordingOrchestrator([this.preflightError]);

  /// What the dictation preflight reports — `null` means ready.
  final String? preflightError;

  @override
  void build() {}

  @override
  Future<String?> checkTranscriptionReady() async => preflightError;
}

/// Stands in for whichever engine [transcriberProvider] picks — Parakeet in
/// the engine test below.
class _FakeTranscriber implements Transcriber {
  int transcribeCalls = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    transcribeCalls++;
    return 'from the active engine';
  }

  @override
  void release() {}
}

class _FakeAudioServiceNotifier extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;
  String? cleanedUpPath;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Future<void> startRecording({bool streamRawPcm = false}) async {
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
  Future<String?> stopRecording({bool keepTail = true}) async {
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
  Future<void> ensureRunning({bool warmup = true}) async {
    ensureRunningCalled = true;
    if (ensureRunningHangs) await Completer<void>().future;
  }

  @override
  Future<String> transcribeBytesWithProgress(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) async {
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
  Transcriber? transcriber,
  String? preflightError,
  ValueChanged<String>? onError,
}) {
  return makeTestable(
    WpVoiceInputButton(onTranscript: onTranscript, onError: onError),
    overrides: [
      audioServiceProvider.overrideWith(() => fakeAudio),
      localSttBundleProvider.overrideWith(() => fakeStt),
      recordingOrchestratorProvider.overrideWith(
        () => _FakeRecordingOrchestrator(preflightError),
      ),
      if (transcriber != null)
        transcriberProvider.overrideWithValue(transcriber),
    ],
    locale: const Locale('en'),
  );
}

/// Messages the toasts announced to screen readers; a toast is asserted by
/// its announcement.
final List<String> _announced = [];

/// Taps to start recording, then taps again to stop+transcribe. The WAV-file
/// read is genuine `dart:io` I/O, which only progresses on the real event
/// loop, so real event-loop turns alternate with fake-clock pumps until the
/// button is back at idle (#1491). Timeouts and the toast run on the fake
/// clock: [step] is the fake time per round, then the toast is run out.
Future<void> _recordStopAndDrain(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 50),
}) async {
  await tester.tap(find.byIcon(LucideIcons.mic));
  await tester.pump();
  expect(find.byIcon(LucideIcons.square), findsOneWidget);

  await tester.tap(find.byIcon(LucideIcons.square));
  await tester.pump();
  await pumpUntil(
    tester,
    () => find.byIcon(LucideIcons.mic).evaluate().isNotEmpty,
    what: 'the voice input to be back at idle',
    step: step,
  );
  // Let a toast run out (2 s auto-dismiss plus its exit).
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// Stop + transcribe up to the point where the fake engine was asked, for
/// the tests that park transcription on a gate.
Future<void> _stopUntilTranscribing(
  WidgetTester tester,
  _FakeSttServerStateNotifier stt,
) async {
  await tester.tap(find.byIcon(LucideIcons.square));
  await pumpUntil(
    tester,
    () => stt.transcribeCalled,
    what: 'transcription to start',
  );
}

void main() {
  late Directory wavDir;
  late String wavPath;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    _announced.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final data = (message as Map<Object?, Object?>)['data'];
          if (data is Map<Object?, Object?> && data['message'] is String) {
            _announced.add(data['message']! as String);
          }
          return null;
        });
    wavDir = await Directory.systemTemp.createTemp('note_voice_input_test_');
    wavPath = '${wavDir.path}/note.wav';
    // Non-empty is all `_stopAndTranscribe` checks for — no WAV-header
    // validation happens before the fake STT notifier's transcribeBytes.
    await File(wavPath).writeAsBytes(const [1, 2, 3, 4]);
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        );
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

    // Notices go through the notice bar and the screen-reader announcement.
    expect(_announced, contains(l10n.voiceNoteError));
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('with onError a failure goes to the caller and raises no toast', (
    tester,
  ) async {
    final audio = _FakeAudioServiceNotifier()..errorOnStart = true;
    final errors = <String>[];
    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: audio,
        fakeStt: _FakeSttServerStateNotifier(),
        onTranscript: (_) {},
        onError: errors.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.mic));
    await tester.pumpAndSettle();

    expect(errors, [l10n.voiceNoteError]);
    expect(_announced, isNot(contains(l10n.voiceNoteError)));
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
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

      await _recordStopAndDrain(tester);

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

    await _recordStopAndDrain(tester);

    expect(lastTranscript, isNull);
    expect(_announced, contains(l10n.voiceNoteEmpty));
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

    await _recordStopAndDrain(tester);

    expect(lastTranscript, isNull);
    // The engine's own failure, not the generic "voice note failed". The toast
    // is raised on the real clock, so it is asserted by its announcement.
    expect(_announced, contains(l10n.errorSttServerFailed));
    expect(_announced, isNot(contains(l10n.voiceNoteError)));
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

      // Stop + transcribe, parked on the gate.
      await _stopUntilTranscribing(tester, stt);
      expect(stt.transcribeCalled, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      gate.complete();
      await pumpUntil(
        tester,
        () => audio.cleanedUpPath != null,
        what: 'the pipeline to finish its housekeeping',
      );
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

      await _recordStopAndDrain(tester);

      expect(lastTranscript, isNull);
      expect(_announced, contains(l10n.voiceNoteError));
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

      await _recordStopAndDrain(tester);

      expect(lastTranscript, isNull);
      expect(_announced, contains(l10n.voiceNoteError));
      expect(audio.cleanedUpPath, wavPath);
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    },
  );

  testWidgets(
    'a dictation started on one note does not follow the editor to the next',
    (tester) async {
      // The editor panel is updated in place across a note switch now (see
      // WpCollectionSplit.crossFadeDetail), so without a note-scoped key the
      // button's element — and with it a transcription still in flight — is
      // reused for the next note and the transcript lands in the wrong one.
      final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
      final gate = Completer<void>();
      final stt = _FakeSttServerStateNotifier(transcribeGate: gate);
      var handOffs = 0;

      final controller = TextEditingController(text: 'Notiz a');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      final hostKey = GlobalKey<_NoteHostState>();
      await tester.pumpWidget(
        makeTestable(
          _NoteHost(
            key: hostKey,
            initial: _note('a'),
            builder: (note) => _panelFor(
              note,
              controller: controller,
              focusNode: focusNode,
              onVoiceTranscript: (_) => handOffs++,
            ),
          ),
          overrides: [
            audioServiceProvider.overrideWith(() => audio),
            localSttBundleProvider.overrideWith(() => stt),
            recordingOrchestratorProvider.overrideWith(
              _FakeRecordingOrchestrator.new,
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.mic));
      await tester.pump();
      expect(find.byIcon(LucideIcons.square), findsOneWidget);

      // Stop + transcribe, parked on the gate, as in the unmount test above.
      await _stopUntilTranscribing(tester, stt);
      expect(stt.transcribeCalled, isTrue);

      hostKey.currentState!.select(_note('b'));
      // Not pumpAndSettle: a carried-over button is still running its
      // processing animation, and a settle timeout is a muddier failure than
      // the icon assertion below.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byIcon(LucideIcons.mic),
        findsOneWidget,
        reason: 'the next note starts with an idle button, not a busy one',
      );
      expect(find.byIcon(LucideIcons.loader), findsNothing);

      gate.complete();
      await pumpUntil(
        tester,
        () => audio.cleanedUpPath != null,
        what: 'the pipeline to finish its housekeeping',
      );
      await tester.pump();

      expect(
        handOffs,
        0,
        reason: "note a's dictation must never be inserted into note b",
      );
      expect(audio.cleanedUpPath, wavPath);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('transcribes with the active engine, not always whisper', (
    tester,
  ) async {
    // XP-6-08: with Parakeet as the only model, the button went to the
    // whisper server and failed with "model file not found".
    final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
    final whisper = _FakeSttServerStateNotifier();
    final engine = _FakeTranscriber();
    String? lastTranscript;
    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: audio,
        fakeStt: whisper,
        transcriber: engine,
        onTranscript: (t) => lastTranscript = t,
      ),
    );

    await _recordStopAndDrain(tester);

    expect(engine.transcribeCalls, 1);
    expect(whisper.transcribeCalled, isFalse);
    expect(lastTranscript, 'from the active engine');
  });

  testWidgets('a missing model says so before anything is recorded', (
    tester,
  ) async {
    final audio = _FakeAudioServiceNotifier()..wavPathToReturn = wavPath;
    await tester.pumpWidget(
      _makeTestableButton(
        fakeAudio: audio,
        fakeStt: _FakeSttServerStateNotifier(),
        preflightError: 'stt_model_not_found',
        onTranscript: (_) {},
      ),
    );

    await tester.tap(find.byIcon(LucideIcons.mic));
    await tester.pump();

    expect(_announced, contains(l10n.errorSttModelNotFound));
    // Never started: no stop button, the mic stays on offer.
    expect(find.byIcon(LucideIcons.square), findsNothing);
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    // Let the error toast run out.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}

// ─── Note-switch harness ──────────────────────────────────────────────────

Note _note(String id) => Note(
  id: id,
  content: 'Notiz $id',
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  isQuickNote: false,
  deletedAt: null,
);

/// The real panel, so the test sees the production keying rather than its own.
Widget _panelFor(
  Note note, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required ValueChanged<String> onVoiceTranscript,
}) => NoteEditorPanel(
  note: note,
  tags: const [],
  controller: controller,
  focusNode: focusNode,
  onClose: () {},
  onToggleFavorite: () {},
  onQuickNoteSet: () {},
  onQuickNoteClear: () {},
  onMoveToTrash: () {},
  onRestore: () {},
  onDeleteForever: () {},
  onAddTag: (_) {},
  onRemoveTag: (_) {},
  onDuplicate: () {},
  onExport: () {},
  onVoiceTranscript: onVoiceTranscript,
);

/// Rebuilds [builder] with whatever the last `select` passed — the panel takes
/// its note from above, so a switch has to come from a parent rebuild.
class _NoteHost extends StatefulWidget {
  const _NoteHost({super.key, required this.initial, required this.builder});

  final Note initial;
  final Widget Function(Note note) builder;

  @override
  State<_NoteHost> createState() => _NoteHostState();
}

class _NoteHostState extends State<_NoteHost> {
  late Note _selected = widget.initial;

  void select(Note note) => setState(() => _selected = note);

  @override
  Widget build(BuildContext context) => widget.builder(_selected);
}
