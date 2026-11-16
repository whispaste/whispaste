/// The search in a dock dropdown with many options (UIA-DOCK-01): the field
/// appears above the threshold and takes focus when the menu opens, it filters
/// by label and code ignoring case and accents, a pinned option stays listed,
/// and Enter, arrow down and Escape work on the filtered result.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';

const _languages = [
  WpDockChoice(value: 'de', label: 'Deutsch'),
  WpDockChoice(value: 'fr', label: 'Français'),
  WpDockChoice(value: 'en', label: 'English'),
  WpDockChoice(value: 'es', label: 'Español'),
  WpDockChoice(value: 'it', label: 'Italiano'),
  WpDockChoice(value: 'pt', label: 'Português'),
  WpDockChoice(value: 'ru', label: 'Русский'),
  WpDockChoice(value: 'he', label: 'עברית'),
  WpDockChoice(value: 'zh', label: '中文'),
  WpDockChoice(value: 'nl', label: 'Nederlands'),
  WpDockChoice(value: 'pl', label: 'Polski'),
  WpDockChoice(value: 'sv', label: 'Svenska'),
];

WpDockChoiceSet _languageSet({
  required List<WpDockChoice> languages,
  ValueChanged<String>? onChanged,
}) => WpDockChoiceSet(
  id: 'language',
  menuId: 'language',
  overline: 'Language',
  icon: LucideIcons.languages,
  choices: [
    const WpDockChoice(value: 'auto', label: 'Auto-detect'),
    ...languages,
  ],
  current: 'de',
  currentLabel: 'Deutsch',
  onChanged: onChanged ?? (_) {},
  searchHint: 'Search…',
  noMatchesLabel: 'No matches',
);

WpRecordingDock _dock(WpDockChoiceSet language) => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  language: language,
  recordingPhase: RecordingPhase.idle,
  microphoneLabel: 'Built-in',
  microphoneOptions: const ['Built-in'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Copy',
  afterAction: null,
);

Future<void> _open(WidgetTester tester, WpDockChoiceSet language) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1224, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 1200, child: _dock(language)),
      ),
      size: const Size(1224, 800),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('dock-language')));
  await tester.pumpAndSettle();
}

Finder _search() => find.byKey(const ValueKey('dock-menu-language-search'));

Finder _field() =>
    find.descendant(of: _search(), matching: find.byType(EditableText));

Finder _row(String value) => find.byKey(ValueKey('dock-menu-language-$value'));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field(), text);
  await tester.pumpAndSettle();
}

void main() {
  group('search in long dropdowns (UIA-DOCK-01)', () {
    testWidgets('no search field up to ten options', (tester) async {
      // Nine languages plus the pinned auto-detect: ten options in all.
      await _open(tester, _languageSet(languages: _languages.take(9).toList()));

      expect(_search(), findsNothing);
      expect(_row('de'), findsOneWidget);
    });

    testWidgets('a search field from eleven options on', (tester) async {
      // Ten languages plus the pinned auto-detect: eleven options in all.
      await _open(
        tester,
        _languageSet(languages: _languages.take(10).toList()),
      );

      expect(_search(), findsOneWidget);
    });

    testWidgets('the search field takes focus when the menu opens', (
      tester,
    ) async {
      await _open(tester, _languageSet(languages: _languages));

      final field = tester.widget<EditableText>(_field());
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('filters by label, ignoring case and accents', (tester) async {
      await _open(tester, _languageSet(languages: _languages));

      await _type(tester, 'FRANCAIS');

      expect(_row('fr'), findsOneWidget);
      expect(_row('en'), findsNothing);
    });

    testWidgets('matches the language code as well as the label', (
      tester,
    ) async {
      await _open(tester, _languageSet(languages: _languages));

      await _type(tester, 'nl');

      expect(_row('nl'), findsOneWidget);
      expect(_row('pt'), findsNothing);
    });

    testWidgets('auto-detect is searchable like every other option', (
      tester,
    ) async {
      await _open(tester, _languageSet(languages: _languages));

      await _type(tester, 'ital');
      expect(
        find.byKey(const ValueKey('dock-menu-language-auto')),
        findsNothing,
      );

      await _type(tester, 'auto');
      expect(find.byKey(const ValueKey('dock-menu-language-auto')), findsOne);
      expect(_row('it'), findsNothing);
    });

    testWidgets('shows the empty state when nothing matches', (tester) async {
      await _open(tester, _languageSet(languages: _languages));

      await _type(tester, 'zzqx');

      expect(find.byKey(const ValueKey('dock-menu-language-empty')), findsOne);
      expect(find.text('No matches'), findsOneWidget);
      expect(_row('de'), findsNothing);
    });

    testWidgets('Enter picks the first match and closes the menu', (
      tester,
    ) async {
      String? picked;
      await _open(
        tester,
        _languageSet(languages: _languages, onChanged: (v) => picked = v),
      );

      await _type(tester, 'ital');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(picked, 'it');
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsNothing);
    });

    testWidgets('arrow down moves focus from the field to the first match', (
      tester,
    ) async {
      await _open(tester, _languageSet(languages: _languages));

      await _type(tester, 'ital');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final row = tester.widget<InkWell>(
        find.descendant(of: _row('it'), matching: find.byType(InkWell)),
      );
      expect(row.focusNode!.hasFocus, isTrue);
    });

    testWidgets('Escape clears the query first, a second Escape closes', (
      tester,
    ) async {
      await _open(tester, _languageSet(languages: _languages));

      await _type(tester, 'fr');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(tester.widget<EditableText>(_field()).controller.text, '');
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsOneWidget);
      expect(_row('en'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsNothing);
    });
  });
}
