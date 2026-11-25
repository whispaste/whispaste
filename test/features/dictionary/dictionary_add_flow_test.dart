/// #855/#623: one way to add a term or a replacement. The "often misspelled
/// as" switch turns the bar into a replacement, a term that is already a
/// trigger is refused, an example in the empty list fills the bar.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._settings);

  AppSettings _settings;
  final List<AppSettings> updates = <AppSettings>[];

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    updates.add(_settings);
    state = AsyncData(_settings);
  }
}

late L10n l10n;

Finder _id(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<(_Settings, ProviderContainer)> pump(
    WidgetTester tester, {
    String vocabulary = '',
    List<(String, String)> replacements = const [],
    bool samples = true,
  }) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    if (!samples) await db.writeAppSettings({'replacementsSamplesSeeded': '1'});
    for (final (i, r) in replacements.indexed) {
      await db.upsertReplacementWithTriggers(
        id: 'r$i',
        triggers: [r.$1],
        replacement: r.$2,
        createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
    }
    final notifier = _Settings(
      AppSettings.defaults.copyWith(customVocabulary: vocabulary),
    );
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: db,
        overrides: [
          settingsProvider.overrideWith(() => notifier),
          pendingCorrectionCandidatesProvider.overrideWith(
            (ref) async => const <CorrectionCandidate>[],
          ),
        ],
        locale: const Locale('en'),
        noticeBar: true,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DictionaryPage)),
    );
    return (notifier, container);
  }

  Future<void> submit(WidgetTester tester, Finder field, String text) async {
    await tester.enterText(field, text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  const bar = ValueKey('dictionary-terms-bar');

  testWidgets('the switch turns Enter into a replacement', (tester) async {
    final (settings, container) = await pump(tester);

    // The switch only shows once the bar holds text (#1969).
    await tester.enterText(find.byKey(bar), 'kubernets');
    await tester.pumpAndSettle();
    await tester.tap(_id('dictionary-terms-misspelled-toggle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dictionary-terms-right')),
      'Kubernetes',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The list also holds the first-start samples.
    final made = container
        .read(replacementsProvider)
        .value!
        .where((r) => r.triggers.contains('kubernets'));
    expect(made.single.replacement, 'Kubernetes');
    // No term was written.
    expect(settings.updates, isEmpty);
  });

  testWidgets('a term that already is a trigger is refused with the cause', (
    tester,
  ) async {
    final (settings, _) = await pump(
      tester,
      replacements: [('mfg', 'Manufacturing')],
    );

    await submit(tester, find.byKey(bar), 'Mfg');

    expect(settings.updates, isEmpty);
    // The trigger is already in the one list (#1969).
    expect(find.text(l10n.dictionaryTermsDuplicate('Mfg')), findsOne);
  });

  testWidgets('a term over 60 characters is refused', (tester) async {
    final (settings, _) = await pump(tester);

    await submit(tester, find.byKey(bar), 'a' * 61);

    expect(settings.updates, isEmpty);
    expect(find.text(l10n.dictionaryTermsTooLong), findsOne);
  });

  testWidgets('an example in the empty list fills the bar, Enter adds it', (
    tester,
  ) async {
    final (_, container) = await pump(tester, samples: false);

    await tester.tap(_id('dictionary-terms-example-0'));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // A term is the entry "Kubernetes → Kubernetes" (#1969).
    final entries = container.read(replacementsProvider).value!;
    expect(entries.single.triggers, ['Kubernetes']);
    expect(entries.single.replacement, 'Kubernetes');
  });
}
