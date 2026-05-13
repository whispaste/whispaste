/// Voice action tests — parser edge cases, VoiceNoteButton widget tests,
/// and integration flow tests (record → transcribe → dispatch).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
// SttServerState is re-exported from stt_bundle.dart.
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/widgets/voice_note_button.dart';
import 'package:whispaste/features/history/data/history_detail_provider.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/voice_action_service.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors recording_orchestrator_test.dart patterns)
// ---------------------------------------------------------------------------

class _FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

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
    state = AudioStatus(filePath: wavPathToReturn);
    return wavPathToReturn;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeSttService extends SttServerStateNotifier {
  String transcriptToReturn = 'Hello world';
  bool ensureRunningThrows = false;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning() async {
    if (ensureRunningThrows) {
      throw Exception('STT server failed to start');
    }
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    return transcriptToReturn;
  }

  @override
  Future<void> prewarm() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps a [VoiceNoteButton] in a testable widget tree with all required
/// providers, localization, and theme.
///
/// A [Consumer] watches [historyDetailProvider] to pre-warm it — otherwise
/// the async build hasn't completed by the time the voice-action pipeline
/// dispatches to the notifier.
Widget _makeTestableButton({
  required String entryId,
  required HistoryDatabase db,
  required _FakeAudioService fakeAudio,
  required _FakeSttService fakeStt,
  bool isDark = true,
}) {
  final theme = isDark ? wpDarkTheme() : wpLightTheme();
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      audioServiceProvider.overrideWith(() => fakeAudio),
      localSttBundleProvider.overrideWith(() => fakeStt),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) {
              // Pre-warm the detail provider so it's loaded before dispatch.
              ref.watch(historyDetailProvider(entryId));
              return VoiceNoteButton(entryId: entryId, isDark: isDark);
            },
          ),
        ),
      ),
    ),
  );
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // 1. Parser edge cases (supplements existing 20 tests)
  // =========================================================================

  group('parseVoiceAction — edge cases', () {
    // ── Mixed-case prefixes ──────────────────────────────────────────────

    test('detects "TAG AS" all-caps prefix', () {
      final result = parseVoiceAction('TAG AS review');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'review');
    });

    test('detects "tAg aS" weird-case prefix', () {
      final result = parseVoiceAction('tAg aS random');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'random');
    });

    test('detects "TAG:" upper-case colon prefix', () {
      final result = parseVoiceAction('TAG:priority');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'priority');
    });

    test('detects "CORRECT:" all-caps prefix', () {
      final result = parseVoiceAction('CORRECT: Fixed text here');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Fixed text here');
    });

    test('detects "cOrReCt:" mixed-case prefix', () {
      final result = parseVoiceAction('cOrReCt: Something else');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Something else');
    });

    test('detects "KORREKTUR:" all-caps German prefix', () {
      final result = parseVoiceAction('KORREKTUR: Neuer Text');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Neuer Text');
    });

    test('detects "Korrektur:" title-case German prefix', () {
      final result = parseVoiceAction('Korrektur: Bearbeiteter Inhalt');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Bearbeiteter Inhalt');
    });

    // ── Unicode content after prefix ─────────────────────────────────────

    test('tag with Unicode emoji payload', () {
      final result = parseVoiceAction('tag as 🏷️ important');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, '🏷️ important');
    });

    test('correction with CJK characters', () {
      final result = parseVoiceAction('correct: 修正されたテキスト');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, '修正されたテキスト');
    });

    test('tag with German umlauts', () {
      final result = parseVoiceAction('tag as Büroarbeit');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'Büroarbeit');
    });

    test('korrektur with German umlauts in payload', () {
      final result = parseVoiceAction('korrektur: Ärger über Änderungen für Ü');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Ärger über Änderungen für Ü');
    });

    test('note with Arabic script', () {
      final result = parseVoiceAction('مرحبا بالعالم');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'مرحبا بالعالم');
    });

    // ── Very long input ──────────────────────────────────────────────────

    test('handles very long note input', () {
      final longText = 'a' * 10000;
      final result = parseVoiceAction(longText);
      expect(result!.type, VoiceActionType.note);
      expect(result.payload.length, 10000);
    });

    test('handles very long tag payload', () {
      final longTag = 'b' * 5000;
      final result = parseVoiceAction('tag as $longTag');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload.length, 5000);
    });

    test('handles very long correction payload', () {
      final longCorrection = 'c' * 5000;
      final result = parseVoiceAction('correct: $longCorrection');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload.length, 5000);
    });

    // ── Only first prefix should match ───────────────────────────────────

    test('tag prefix takes priority even with correction text inside', () {
      final result = parseVoiceAction('tag as correct: value');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'correct: value');
    });

    test('tag prefix takes priority even with korrektur text inside', () {
      final result = parseVoiceAction('tag as korrektur: something');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'korrektur: something');
    });

    test('correction payload may contain "tag as" without affecting type', () {
      final result = parseVoiceAction('correct: please tag as important later');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'please tag as important later');
    });

    test('note starting with "tag" but not "tag as " or "tag:" is note', () {
      final result = parseVoiceAction('tagging along for the ride');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'tagging along for the ride');
    });

    test('"tag a" without trailing "s " is a note, not a tag', () {
      final result = parseVoiceAction('tag a new item');
      expect(result!.type, VoiceActionType.note);
    });

    test('"correct" without colon is a note', () {
      final result = parseVoiceAction('correct me if I am wrong');
      expect(result!.type, VoiceActionType.note);
    });

    test('"korrektur" without colon is a note', () {
      final result = parseVoiceAction('korrektur ist wichtig');
      expect(result!.type, VoiceActionType.note);
    });

    // ── Whitespace handling ──────────────────────────────────────────────

    test('tag with extra spaces between prefix and payload', () {
      final result = parseVoiceAction('tag as    spaced');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'spaced');
    });

    test('correction with extra leading spaces on payload', () {
      final result = parseVoiceAction('correct:     padded text');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'padded text');
    });

    test('leading/trailing whitespace stripped before prefix matching', () {
      final result = parseVoiceAction('   tag as trimmed   ');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'trimmed');
    });

    // ── Newlines and special whitespace ───────────────────────────────────

    test('tag payload preserves internal newlines', () {
      final result = parseVoiceAction('tag as line1\nline2');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'line1\nline2');
    });

    test('note with tab characters is preserved', () {
      final result = parseVoiceAction('item\tone\ttwo');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'item\tone\ttwo');
    });
  });

  // =========================================================================
  // 2. VoiceNoteButton widget tests
  // =========================================================================

  group('VoiceNoteButton', () {
    late HistoryDatabase db;
    late _FakeAudioService fakeAudio;
    late _FakeSttService fakeStt;
    const entryId = 'voice-btn-test-1';

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      fakeAudio = _FakeAudioService();
      fakeStt = _FakeSttService();

      // Seed an entry so HistoryDetailNotifier can load it.
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: entryId,
          timestamp: DateTime(2025, 7, 1, 12, 0),
          content: const Value('Original transcript'),
          title: const Value('Test Entry'),
          model: const Value('whisper-small'),
          isLocal: const Value(true),
          durationSec: const Value(5.0),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('renders mic icon in idle state', (tester) async {
      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Should find the mic icon.
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);

      // Should have a tooltip.
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('renders InkWell that is tappable', (tester) async {
      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNotNull);
    });

    testWidgets('shows stop icon after tap starts recording', (tester) async {
      fakeAudio.wavPathToReturn = 'fake_path.wav';

      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial mic icon.
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);

      // Tap to start recording.
      await tester.tap(find.byType(InkWell));
      await tester.pump();

      // Should now show the stop (square) icon.
      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.mic), findsNothing);
    });

    testWidgets('shows error state and returns to idle on mic error', (
      tester,
    ) async {
      fakeAudio.errorOnStart = true;

      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Tap to try recording — error on start.
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should show a WpToast error message (overlay-based, not SnackBar).
      expect(find.text('Voice note failed'), findsOneWidget);

      // Should return to idle (mic icon).
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);

      // Drain the WpToast auto-dismiss timer + animation controller.
      // Timeline: Future.delayed(3s) → controller.reverse(200ms) → dispose
      await tester.pump(const Duration(seconds: 3)); // fires Future.delayed
      await tester.pump(const Duration(milliseconds: 300)); // reverse completes
      await tester.pump(); // .then() callback disposes
    });

    testWidgets('does not start when main recording is active', (tester) async {
      // Simulate main dictation already recording.
      fakeAudio = _FakeAudioService();

      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Manually set recording phase to recording (simulating main dictation).
      // VoiceNoteButton guards via recordingOrchestratorProvider.currentPhase
      // which reads recordingProvider — so we drive that directly.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VoiceNoteButton)),
      );
      container.read(recordingProvider.notifier).startRecording();
      await tester.pump();

      // Tap — should be ignored since orchestrator phase is recording.
      await tester.tap(find.byType(InkWell));
      await tester.pump();

      // Should still show mic icon (idle).
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    });

    testWidgets('renders correctly in light mode', (tester) async {
      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
          isDark: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    });
  });

  // =========================================================================
  // 3. Voice action dispatch tests (parse → notifier → DB)
  //
  // Uses ProviderContainer (not widget tests) to directly verify the
  // parse-then-dispatch pipeline that VoiceNoteButton._dispatchAction runs.
  // This avoids the fire-and-forget async / File I/O issues of widget tests.
  // =========================================================================

  group('Voice action dispatch flow', () {
    late HistoryDatabase db;
    late ProviderContainer container;
    const entryId = 'voice-dispatch-1';

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());

      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: entryId,
          timestamp: DateTime(2025, 7, 1, 12, 0),
          content: const Value('Original content'),
          title: const Value('Flow Test Entry'),
          model: const Value('whisper-small'),
          isLocal: const Value(true),
          durationSec: const Value(5.0),
        ),
      );

      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
    });

    tearDown(() => container.dispose());

    /// Loads and returns the notifier, keeping a listener alive.
    Future<HistoryDetailNotifier> loadNotifier() async {
      container.listen(historyDetailProvider(entryId), (_, _) {});
      final state = await container.read(historyDetailProvider(entryId).future);
      expect(state.entry.id, entryId);
      return container.read(historyDetailProvider(entryId).notifier);
    }

    test('note: parseVoiceAction → addNote → note persisted', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('Buy groceries tomorrow');
      expect(action!.type, VoiceActionType.note);

      await notifier.addNote(action.payload);

      final notes = await db.notesForEntry(entryId);
      expect(notes, hasLength(1));
      expect(notes.first.content, 'Buy groceries tomorrow');
    });

    test('tag: parseVoiceAction "tag as X" → addTag → tag persisted', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('tag as important');
      expect(action!.type, VoiceActionType.tag);

      await notifier.addTag(action.payload);

      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'important');
    });

    test('tag: parseVoiceAction "tag:work" → addTag → tag persisted', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('tag:work');
      expect(action!.type, VoiceActionType.tag);

      await notifier.addTag(action.payload);

      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'work');
    });

    test('correction: parseVoiceAction "correct: X" → updateContent', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('correct: Updated transcript content');
      expect(action!.type, VoiceActionType.correction);

      await notifier.updateContent(action.payload);

      final entry = await db.getEntry(entryId);
      expect(entry!.content, 'Updated transcript content');
    });

    test(
      'correction: parseVoiceAction "korrektur: X" → updateContent',
      () async {
        final notifier = await loadNotifier();

        final action = parseVoiceAction('korrektur: Korrigierter Inhalt');
        expect(action!.type, VoiceActionType.correction);

        await notifier.updateContent(action.payload);

        final entry = await db.getEntry(entryId);
        expect(entry!.content, 'Korrigierter Inhalt');
      },
    );

    test('empty/null action not dispatched', () async {
      await loadNotifier();

      final action = parseVoiceAction('   ');
      expect(action, isNull);

      // Verify nothing changed.
      final notes = await db.notesForEntry(entryId);
      expect(notes, isEmpty);
      final entry = await db.getEntry(entryId);
      expect(entry!.content, 'Original content');
    });

    test('full dispatch switch matches VoiceNoteButton logic', () async {
      final notifier = await loadNotifier();

      // Simulate the exact dispatch logic from VoiceNoteButton._dispatchAction
      for (final input in [
        'Remember to call Bob',
        'tag as urgent',
        'correct: Fixed transcript',
      ]) {
        final action = parseVoiceAction(input)!;
        switch (action.type) {
          case VoiceActionType.note:
            await notifier.addNote(action.payload);
          case VoiceActionType.tag:
            await notifier.addTag(action.payload);
          case VoiceActionType.correction:
            await notifier.updateContent(action.payload);
        }
      }

      final notes = await db.notesForEntry(entryId);
      expect(notes, hasLength(1));
      expect(notes.first.content, 'Remember to call Bob');

      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'urgent');

      final entry = await db.getEntry(entryId);
      expect(entry!.content, 'Fixed transcript');
    });
  });
}
