/// The Snippet-Picker trigger word, in its home in Settings → After
/// Transcription.
///
/// It used to ride the Snippets page's list header, where it pushed the first
/// snippet a card down the page. These cases moved with it: the row itself is
/// macOS-only, and the "your trigger currently does nothing" warning has to
/// survive the move, because it is the only place the app admits that a set
/// trigger plus an empty snippet list is a no-op.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/features/snippets/snippets_page.dart'
    show snippetsProvider;

import '../../fixtures/test_helpers.dart';

late L10n l10n;

Widget _section({String trigger = ''}) => makeTestable(
  const AfterTranscriptionSection(),
  locale: const Locale('en'),
  overrides: [
    settingsProvider.overrideWith(
      () => _FakeSettingsNotifier(
        AppSettings(behavior: BehaviorSettings(snippetPickerTrigger: trigger)),
      ),
    ),
  ],
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Snippet-Picker trigger in Settings', () {
    // The row only renders on macOS — see the `Platform.isMacOS` guard in
    // `AfterTranscriptionSection`.
    testWidgets('the trigger row lives in the After-Transcription section', (
      tester,
    ) async {
      if (!Platform.isMacOS) return;
      await tester.pumpWidget(_section());
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerTriggerLabel), findsOneWidget);
    });

    testWidgets(
      'a set trigger word with an empty snippet list shows the "trigger does '
      'nothing yet" hint until the first snippet exists',
      (tester) async {
        if (!Platform.isMacOS) return;
        await tester.pumpWidget(_section(trigger: 'snippet'));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.snippetsPickerTriggerEmptyListHint),
          findsOneWidget,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AfterTranscriptionSection)),
        );
        await container
            .read(snippetsProvider.notifier)
            .add('Signature', 'Best,\nSilvio');
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.snippetsPickerTriggerEmptyListHint),
          findsNothing,
        );
      },
    );

    testWidgets('an empty trigger word shows no empty-list hint even while '
        'the snippet list is empty', (tester) async {
      if (!Platform.isMacOS) return;
      await tester.pumpWidget(_section());
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerTriggerEmptyListHint), findsNothing);
    });
  });
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}
