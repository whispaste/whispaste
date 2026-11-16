import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/repaste_service.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';
import 'package:whispaste/services/replacements/learn_correction_hotkey.dart';
import 'package:whispaste/services/replacements/selection_correction_match.dart'
    show matchSelectionToDictation;
import 'package:whispaste/services/selection_edit/selection_edit_service.dart';

/// Clipboard of a fake app in front: the copy puts [selection] on it.
class _FakeClipboard implements SelectionClipboard {
  _FakeClipboard(this.text);

  String? text;

  @override
  Future<String?> readText() async => text;

  @override
  Future<void> writeTransient(String value) async => text = value;

  @override
  Future<bool> readAccessDenied() async => false;
}

SelectionReader _readerFor(String? selection) {
  final clipboard = _FakeClipboard('previous clipboard');
  return SelectionReader(
    copy: (_) async {
      if (selection != null) clipboard.text = selection;
      return const NativePasteResult(status: NativePasteStatus.success);
    },
    clipboard: clipboard,
    pollInterval: Duration.zero,
    pollTimeout: Duration.zero,
    lateCopyGrace: Duration.zero,
  );
}

class _Settings extends SettingsNotifier {
  _Settings({required this.learning});
  final bool learning;

  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    behavior: AppSettings.defaults.behavior.copyWith(
      correctionLearningEnabled: learning,
    ),
  );
}

void main() {
  group('learnCorrectionLogLine', () {
    test('names the app by its last path segment and the result', () {
      expect(
        learnCorrectionLogLine(
          app: '/Applications/Notes.app',
          outcome: LearnCorrectionOutcome.proposed,
        ),
        'Learn correction hotkey: app=Notes.app, result=proposed',
      );
      expect(
        learnCorrectionLogLine(
          app: r'C:\Program Files\Word\WINWORD.EXE',
          outcome: LearnCorrectionOutcome.nothingFound,
        ),
        'Learn correction hotkey: app=WINWORD.EXE, result=nothingFound',
      );
    });

    test('an unknown app reads "unknown"', () {
      for (final app in [null, '', '  ']) {
        expect(
          learnCorrectionLogLine(
            app: app,
            outcome: LearnCorrectionOutcome.noSelection,
          ),
          'Learn correction hotkey: app=unknown, result=noSelection',
        );
      }
    });
  });

  group('matchSelectionToDictation', () {
    const dictation = 'we tested whis paste with the new kubernetis cluster';

    test('finds a misheard word with its context', () {
      expect(matchSelectionToDictation('Kubernetes', dictation), (
        sourceText: 'kubernetis',
        targetText: 'Kubernetes',
        contextBefore: 'with the new',
      ));
    });

    test('joins words the dictation split', () {
      final m = matchSelectionToDictation('WhisPaste', dictation);
      expect(m?.sourceText, 'whis paste');
      expect(m?.targetText, 'WhisPaste');
      expect(m?.contextBefore, 'we tested');
    });

    test('a case fix mid-sentence counts, at a sentence start it does not', () {
      expect(
        matchSelectionToDictation(
          'Berlin',
          'we flew to berlin today',
        )?.sourceText,
        'berlin',
      );
      expect(matchSelectionToDictation('Today', 'today we flew home'), isNull);
      expect(
        matchSelectionToDictation('Today', 'It rained. today we flew home'),
        isNull,
      );
    });

    test('nothing to learn when the selection already stands there', () {
      expect(matchSelectionToDictation('tested', dictation), isNull);
    });

    test('too short, too long, empty or unrelated selections give null', () {
      expect(matchSelectionToDictation('in', dictation), isNull);
      expect(matchSelectionToDictation('', dictation), isNull);
      expect(
        matchSelectionToDictation('one two three four five', dictation),
        isNull,
      );
      expect(matchSelectionToDictation('Xylophon', dictation), isNull);
    });

    test('two equally close places are ambiguous', () {
      expect(
        matchSelectionToDictation('Meyer', 'meier called and mayer answered'),
        isNull,
      );
    });
  });

  group('LearnCorrectionHotkeyService.learnFromSelection', () {
    Future<(ProviderContainer, HistoryDatabase)> setUp({
      required bool learning,
      required String? selection,
      String? dictation = 'we deployed it to kubernetis today',
      bool reader = true,
    }) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(learning: learning)),
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          desktopPasteControllerProvider.overrideWithValue(null),
          learnCorrectionSelectionReaderProvider.overrideWithValue(
            reader ? _readerFor(selection) : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      if (dictation != null) {
        container.read(lastDictationTextProvider.notifier).set(dictation);
      }
      return (container, db);
    }

    Future<LearnCorrectionOutcome?> press(ProviderContainer c) async {
      await c.read(learnCorrectionHotkeyServiceProvider).learnFromSelection();
      return c.read(learnCorrectionFeedbackProvider)?.outcome;
    }

    test('one press proposes the replacement in the Dictionary', () async {
      final (c, db) = await setUp(learning: true, selection: 'Kubernetes');
      expect(await press(c), LearnCorrectionOutcome.proposed);
      final row = await db.readCorrectionObservation(
        normalizeCorrectionKey('kubernetis', 'Kubernetes'),
      );
      expect(row?.source, CorrectionSignalSource.selectionHotkey.name);
      final pending = await c
          .read(correctionLearningServiceProvider)
          .pendingCandidates(db);
      expect(
        pending.map((p) => (p.sourceText, p.targetText)),
        contains(('kubernetis', 'Kubernetes')),
      );
    });

    test('with learning off nothing is read or recorded', () async {
      var copied = false;
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(learning: false)),
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          desktopPasteControllerProvider.overrideWithValue(null),
          learnCorrectionSelectionReaderProvider.overrideWithValue(
            SelectionReader(
              copy: (_) async {
                copied = true;
                return const NativePasteResult(
                  status: NativePasteStatus.success,
                );
              },
              clipboard: _FakeClipboard('x'),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);
      c.read(lastDictationTextProvider.notifier).set('kubernetis');
      expect(await press(c), LearnCorrectionOutcome.learningOff);
      expect(copied, isFalse);
      expect(
        await db.readCorrectionObservation(
          normalizeCorrectionKey('kubernetis', 'Kubernetes'),
        ),
        isNull,
      );
    });

    test('nothing selected says so', () async {
      final (c, _) = await setUp(learning: true, selection: null);
      expect(await press(c), LearnCorrectionOutcome.noSelection);
      final (c2, _) = await setUp(
        learning: true,
        selection: 'Kubernetes',
        reader: false,
      );
      expect(await press(c2), LearnCorrectionOutcome.noSelection);
    });

    test('a selection that fits no dictated place finds nothing', () async {
      final (c, _) = await setUp(learning: true, selection: 'Xylophon');
      expect(await press(c), LearnCorrectionOutcome.nothingFound);
      final (c2, _) = await setUp(
        learning: true,
        selection: 'Kubernetes',
        dictation: null,
      );
      expect(await press(c2), LearnCorrectionOutcome.nothingFound);
    });

    test('a rejected suggestion is not brought back', () async {
      final (c, db) = await setUp(learning: true, selection: 'Kubernetes');
      expect(await press(c), LearnCorrectionOutcome.proposed);
      final row = await db.readCorrectionObservation(
        normalizeCorrectionKey('kubernetis', 'Kubernetes'),
      );
      await db.setCorrectionObservationStatus(row!.id, 'rejected');
      expect(await press(c), LearnCorrectionOutcome.nothingFound);
      final pending = await c
          .read(correctionLearningServiceProvider)
          .pendingCandidates(db);
      expect(pending, isEmpty);
    });

    test('two presses in a row both reach the listeners', () async {
      final (c, _) = await setUp(learning: true, selection: 'Xylophon');
      await press(c);
      final first = c.read(learnCorrectionFeedbackProvider)!.seq;
      await press(c);
      expect(c.read(learnCorrectionFeedbackProvider)!.seq, first + 1);
    });
  });
}
