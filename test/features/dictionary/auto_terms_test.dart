// #1969: the dictionary is one list. Terms come from the replacements used
// most, and the old hand-kept term list becomes replacement entries once.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/auto_terms_sync.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/dictionary/auto_terms.dart';

class _MemorySettings extends SettingsNotifier {
  _MemorySettings(this._initial);
  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.requireValue));
  }
}

final _t = DateTime(2026);

void main() {
  group('autoTermsVocabulary', () {
    test('orders by use, keeps list order on ties, each once', () {
      expect(
        autoTermsVocabulary([
          (
            replacement: 'Kubernetes',
            usageCount: 1,
            isTerm: false,
            changed: _t,
          ),
          (replacement: 'WhisPaste', usageCount: 7, isTerm: false, changed: _t),
          (replacement: 'kubernetes', usageCount: 0, isTerm: true, changed: _t),
          (replacement: 'Grafana', usageCount: 1, isTerm: false, changed: _t),
        ]),
        'WhisPaste, Kubernetes, Grafana',
      );
    });

    test('leaves out what a term hint cannot carry', () {
      expect(
        autoTermsVocabulary([
          (
            replacement: 'Mit freundlichen Grüßen,\nSilke',
            usageCount: 9,
            isTerm: false,
            changed: _t,
          ),
          (
            replacement: 'Hallo {name}',
            usageCount: 9,
            isTerm: false,
            changed: _t,
          ),
          (replacement: 'a, b', usageCount: 9, isTerm: false, changed: _t),
          (replacement: 'x' * 61, usageCount: 9, isTerm: false, changed: _t),
          (replacement: 'Ortho', usageCount: 0, isTerm: true, changed: _t),
        ]),
        'Ortho',
      );
    });

    test('equally used: the newest change first, then list order', () {
      expect(
        autoTermsVocabulary([
          (replacement: 'Alt', usageCount: 3, isTerm: false, changed: _t),
          (
            replacement: 'Neu',
            usageCount: 3,
            isTerm: false,
            changed: DateTime(2026, 6),
          ),
          (replacement: 'Auch alt', usageCount: 3, isTerm: false, changed: _t),
        ]),
        'Neu, Alt, Auch alt',
      );
    });

    test('stops at the cap', () {
      final many = [
        for (var i = 0; i < kAutoTermsMax + 5; i++)
          (replacement: 'Term$i', usageCount: 0, isTerm: true, changed: _t),
      ];
      expect(autoTermsVocabulary(many).split(', '), hasLength(kAutoTermsMax));
    });
  });

  test('termMigrationPlan skips triggers and repeats', () {
    expect(
      termMigrationPlan(
        'Kubernetes, mfg\nGrafana, grafana, ???',
        existingTriggers: const ['MFG'],
      ),
      ['Kubernetes', 'Grafana'],
    );
  });

  group('syncAutoTerms', () {
    late HistoryDatabase db;
    late ProviderContainer container;

    Future<void> setUpWith(String vocabulary, {bool migrated = false}) async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.writeAppSettings({'replacementsSamplesSeeded': '1'});
      await db.upsertReplacementWithTriggers(
        id: 'mfg',
        triggers: const ['mfg'],
        replacement: 'Mit freundlichen Grüßen',
        createdAt: DateTime(2026),
      );
      final settings = AppSettings.defaults.copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          customVocabulary: vocabulary,
          termsMigrated: migrated,
        ),
      );
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(() => _MemorySettings(settings)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    }

    Future<List<Replacement>> entries() =>
        container.read(replacementsProvider.future);

    test('turns the hand-kept terms into entries once, skipping triggers, '
        'and keeps the old text', () async {
      await setUpWith('Kubernetes, mfg, Grafana');

      await syncAutoTerms(container);
      await syncAutoTerms(container);

      final list = await entries();
      expect(
        [
          for (final r in list)
            if (r.triggers.single == r.replacement) r.replacement,
        ]..sort(),
        ['Grafana', 'Kubernetes'],
      );
      expect(list.where((r) => r.triggers.single == 'mfg'), hasLength(1));
      final stt = container.read(settingsProvider).requireValue.stt;
      expect(stt.termsMigrated, isTrue);
      expect(stt.manualVocabularyArchive, 'Kubernetes, mfg, Grafana');
      // The hint now follows the replacements.
      expect(
        vocabularyTermsOf(stt.customVocabulary),
        containsAll(['Kubernetes', 'Grafana']),
      );
      // An unused sample does not reach the recogniser.
      expect(stt.customVocabulary, isNot(contains('Grüßen')));
    });

    test(
      'after the step the term text is no longer a list of its own',
      () async {
        await setUpWith('Old', migrated: true);

        await syncAutoTerms(container);

        expect(await entries(), hasLength(1));
        expect(
          container.read(settingsProvider).requireValue.stt.customVocabulary,
          // "Old" is not migrated again; the unused sample stays out.
          isEmpty,
        );
      },
    );
  });
}

List<String> vocabularyTermsOf(String s) => s.split(', ');
