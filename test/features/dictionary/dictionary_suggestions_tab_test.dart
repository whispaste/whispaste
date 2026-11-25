/// Suggestions tab hand-offs: the learning switch writes
/// `correctionLearningEnabled`, and accepting a candidate stores a replacement
/// and removes the candidate from the list; rejecting can be undone from the
/// notice it leaves (#321).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/dictionary_notice.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

Future<ProviderContainer> _pumpTab(
  WidgetTester tester, {
  HistoryDatabase? db,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const Scaffold(
        body: Column(
          children: [
            WpPageNoticeSlot(page: dictionaryNoticePage),
            Expanded(child: DictionarySuggestionsTab()),
          ],
        ),
      ),
      locale: const Locale('en'),
      db: db,
      overrides: [settingsProvider.overrideWith(_FakeSettings.new)],
      noticeBar: true,
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(DictionarySuggestionsTab)),
  );
}

/// Lets the success toast expire and unmounts the tree, so no timer is left.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<HistoryDatabase> _seed(
  WidgetTester tester, {
  String id = 'c1',
  String source = 'foo',
  String target = 'bar',
}) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  final now = DateTime.now();
  await tester.runAsync(
    () => db.upsertCorrectionObservation(
      id: id,
      normalizedKey: normalizeCorrectionKey(source, target),
      sourceText: source,
      targetText: target,
      occurrenceCount: correctionCandidateThreshold,
      status: CorrectionObservationStatus.pending.name,
      source: CorrectionSignalSource.voiceCommand.name,
      unit: correctionUnitWord,
      firstSeenAt: now,
      lastSeenAt: now,
    ),
  );
  return db;
}

void main() {
  testWidgets('term acceptance offers undo which reopens the suggestion', (
    tester,
  ) async {
    final db = await _seed(
      tester,
      id: 'term1',
      source: 'kubernets',
      target: 'Kubernetes',
    );
    final container = await _pumpTab(tester, db: db);
    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestion-term-term1')),
    );
    await tester.pumpAndSettle();
    // A term is the entry "Kubernetes → Kubernetes" (#1969).
    Future<int> termEntries() async => (await tester.runAsync(
      db.readAllReplacements,
    ))!.where((r) => r.triggers.single == 'Kubernetes').length;
    expect(await termEntries(), 1);
    expect(await container.read(learnedTermsProvider.future), {'kubernetes'});
    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestion-term-undo')),
    );
    await tester.pumpAndSettle();
    expect(await termEntries(), 0);
    expect(
      find.byKey(const ValueKey('dictionary-suggestion-term-term1')),
      findsOneWidget,
    );
    expect(await container.read(learnedTermsProvider.future), isEmpty);
    await _teardown(tester);
  });

  testWidgets('the learning switch toggles correctionLearningEnabled', (
    tester,
  ) async {
    final container = await _pumpTab(tester);
    bool learning() => container
        .read(settingsProvider)
        .value!
        .behavior
        .correctionLearningEnabled;
    final before = learning();

    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestions-learning-toggle')),
    );
    await tester.pumpAndSettle();
    expect(learning(), !before);

    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestions-learning-toggle')),
    );
    await tester.pumpAndSettle();
    expect(learning(), before);

    await _teardown(tester);
  });

  testWidgets('accepting a candidate stores the replacement and drops it', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime(2026, 11, 3);
    await tester.runAsync(
      () => db.upsertCorrectionObservation(
        id: 'c1',
        normalizedKey: normalizeCorrectionKey('foo', 'bar'),
        sourceText: 'foo',
        targetText: 'bar',
        occurrenceCount: correctionCandidateThreshold,
        status: CorrectionObservationStatus.pending.name,
        source: CorrectionSignalSource.voiceCommand.name,
        unit: correctionUnitWord,
        firstSeenAt: now,
        lastSeenAt: now,
      ),
    );

    await _pumpTab(tester, db: db);
    const accept = ValueKey('dictionary-suggestion-replace-c1');
    expect(find.byKey(accept), findsOneWidget);

    await tester.tap(find.byKey(accept));
    await tester.pumpAndSettle();

    final stored = await tester.runAsync(db.readAllReplacements);
    expect(stored, hasLength(1));
    expect(stored!.single.triggers, ['foo']);
    expect(stored.single.row.replacement, 'bar');
    expect(find.byKey(accept), findsNothing);

    await _teardown(tester);
  });

  testWidgets('a rejected suggestion comes back with undo', (tester) async {
    final db = await _seed(tester);
    await _pumpTab(tester, db: db);
    const reject = ValueKey('dictionary-suggestion-reject-c1');
    const replace = ValueKey('dictionary-suggestion-replace-c1');

    await tester.tap(find.byKey(reject));
    await tester.pumpAndSettle();
    expect(find.byKey(replace), findsNothing);
    final rejected = await tester.runAsync(
      () => db.readCorrectionObservationById('c1'),
    );
    expect(rejected!.status, CorrectionObservationStatus.rejected.name);

    await tester.tap(find.byKey(const ValueKey('dictionary-suggestion-undo')));
    await tester.pumpAndSettle();

    final restored = await tester.runAsync(
      () => db.readCorrectionObservationById('c1'),
    );
    expect(restored!.status, CorrectionObservationStatus.pending.name);
    expect(find.byKey(replace), findsOneWidget);

    await _teardown(tester);
  });
}
