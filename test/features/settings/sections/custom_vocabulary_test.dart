/// What the terms list (Wörterbuch, "Begriffe" tab) triggers: Enter in the bar
/// adds a term, the row actions edit and delete, and every change reaches
/// `customVocabulary` through the settings provider. Found by testID only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/dictionary/dictionary_notice.dart';
import 'package:whispaste/features/dictionary/widgets/dictionary_terms_list.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  String get vocabulary => _settings.stt.customVocabulary;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

Future<_FakeSettingsNotifier> _pump(
  WidgetTester tester,
  String vocabulary,
) async {
  final notifier = _FakeSettingsNotifier(
    AppSettings.defaults.copyWith(customVocabulary: vocabulary),
  );
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(
        child: Column(
          children: [
            WpPageNoticeSlot(page: dictionaryNoticePage),
            DictionaryTermsList(),
          ],
        ),
      ),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Finder _id(String id) => find.byKey(ValueKey(id));

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('every stored term is a row', (tester) async {
    await _pump(tester, 'GitHub, npm\nJSON');
    expect(_id('dictionary-term-row-0'), findsOneWidget);
    expect(_id('dictionary-term-row-2'), findsOneWidget);
    expect(_id('dictionary-terms-empty'), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pump(tester, '');
    expect(_id('dictionary-terms-empty'), findsOneWidget);
  });

  testWidgets('typing filters without touching the stored text', (
    tester,
  ) async {
    final notifier = await _pump(tester, 'GitHub, npm, JSON');
    await tester.enterText(_id('dictionary-terms-bar'), 'js');
    await tester.pumpAndSettle();
    expect(_id('dictionary-term-row-2'), findsOneWidget);
    expect(_id('dictionary-term-row-0'), findsNothing);
    expect(notifier.vocabulary, 'GitHub, npm, JSON');
  });

  testWidgets('Enter adds the typed term once and clears the bar', (
    tester,
  ) async {
    final notifier = await _pump(tester, 'GitHub');
    await tester.enterText(_id('dictionary-terms-bar'), 'Kubernetes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'GitHub, Kubernetes');
    expect(_id('dictionary-term-row-1'), findsOneWidget);

    await tester.enterText(_id('dictionary-terms-bar'), 'github');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'GitHub, Kubernetes');
  });

  testWidgets('delete removes at once', (tester) async {
    final notifier = await _pump(tester, 'a\nb\nc');
    await tester.tap(_id('dictionary-term-delete-1'));
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'a\nc');
  });

  testWidgets('edit renames the entry in place', (tester) async {
    final notifier = await _pump(tester, 'a, b, c');
    await tester.tap(_id('dictionary-term-edit-1'));
    await tester.pumpAndSettle();
    await tester.enterText(_id('dictionary-term-edit-field'), 'bee');
    await tester.tap(_id('dictionary-term-edit-save'));
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'a, bee, c');
  });

  testWidgets('undo puts a deleted term back at its position', (tester) async {
    final notifier = await _pump(tester, 'a\nb\nc');
    await tester.tap(_id('dictionary-term-delete-1'));
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'a\nc');
    await tester.tap(_id('dictionary-term-undo'));
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'a\nb\nc');
  });

  testWidgets('the undo notice stays until it is closed', (tester) async {
    await _pump(tester, 'a, b');
    await tester.tap(_id('dictionary-term-delete-0'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 5));
    expect(_id('dictionary-term-undo'), findsOneWidget);
  });

  testWidgets('a comma in the bar adds one entry per part', (tester) async {
    final notifier = await _pump(tester, 'GitHub');
    await tester.enterText(_id('dictionary-terms-bar'), 'Dr. Müller, PhD');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(notifier.vocabulary, 'GitHub, Dr. Müller, PhD');
  });

  testWidgets('a comma in the edit dialog is refused', (tester) async {
    final notifier = await _pump(tester, 'a, b');
    await tester.tap(_id('dictionary-term-edit-0'));
    await tester.pumpAndSettle();
    await tester.enterText(_id('dictionary-term-edit-field'), 'x, y');
    await tester.tap(_id('dictionary-term-edit-save'));
    await tester.pumpAndSettle();
    expect(_id('dictionary-term-edit-problem'), findsOneWidget);
    expect(notifier.vocabulary, 'a, b');
  });
}
