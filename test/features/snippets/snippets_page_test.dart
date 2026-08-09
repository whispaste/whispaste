/// Tests for [SnippetsPage].
///
/// Covers: empty state, Add dialog, dialog validation, Edit pre-fill, search
/// filter, no-results state, hover → delete confirmation, telemetry category.
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// The page header renders a macOS-only picker-trigger [TextField] ahead of
/// the search field (see `Platform.isMacOS` in `SnippetsPage`'s header) —
/// shifts every subsequent `find.byType(TextField).at(N)` index by one on
/// macOS relative to Windows/Linux.
final _fieldOffset = Platform.isMacOS ? 1 : 0;

/// Sends the platform's "new item" chord — Cmd on macOS, Ctrl elsewhere,
/// exactly as `WpSearchableListPage` binds it.
Future<void> _pressNewItemChord(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(modifier);
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('SnippetsPage', () {
    testWidgets('starts empty — no sample data is seeded', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsEmpty), findsOneWidget);
    });

    testWidgets('Add button opens dialog with correct labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
      expect(
        find.text(l10n.snippetsDialogHint),
        findsOneWidget,
        reason:
            'the explanatory subtitle comes from WpFormDialogShell — without '
            'it this dialog reads barer than its Replacements twin',
      );
      expect(find.text(l10n.snippetsTitleLabel), findsOneWidget);
      expect(find.text(l10n.snippetsBodyLabel), findsOneWidget);
    });

    testWidgets('the dialog stays whole at a 2x system text size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the dialog body scrolls instead of overflowing',
      );
    });

    testWidgets('save button is disabled while both fields are empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      final buttons = tester.widgetList<WpButton>(find.byType(WpButton));
      expect(
        buttons.any((b) => b.onPressed == null),
        isTrue,
        reason: 'Dialog save button should be disabled with empty fields',
      );
    });

    testWidgets('adding a snippet persists it, shows it in the list, and fires '
        'a distinct "snippets" telemetry category', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      // TextFields in tree order: [0] picker trigger (macOS only), [_fieldOffset]
      // page search, [_fieldOffset + 1] title, [_fieldOffset + 2] body
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best,\nSilvio',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      expect(find.text('Signature'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      final counts = container
          .read(telemetrySessionAggregatorProvider)
          .debugCounts;
      expect(counts[('snippets', 'create', null)], 1);
      expect(counts[('replacements', 'create', null)], isNull);
    });

    testWidgets('tapping a tile opens edit dialog with pre-filled title', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Greeting',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Hi there',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Greeting'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsEditSnippet), findsOneWidget);
      expect(find.text('Greeting'), findsWidgets);
    });

    testWidgets('search field filters visible snippets', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      for (final (title, body) in [
        ('Signature', 'Best, Silvio'),
        ('Greeting', 'Hi there'),
      ]) {
        await tester.tap(find.byIcon(LucideIcons.plus));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(_fieldOffset + 1),
          title,
        );
        await tester.enterText(
          find.byType(TextField).at(_fieldOffset + 2),
          body,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.snippetsAdd).last);
        await tester.pumpAndSettle();
      }

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Greeting'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(_fieldOffset), 'Sign');
      await tester.pumpAndSettle();

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Greeting'), findsNothing);
    });

    testWidgets('search with no match shows no-results empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best, Silvio',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(_fieldOffset),
        'zzzznonexistent',
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNoMatches), findsOneWidget);
    });

    testWidgets('hover shows delete icon; tapping it opens confirm dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 1),
        'Signature',
      );
      await tester.enterText(
        find.byType(TextField).at(_fieldOffset + 2),
        'Best, Silvio',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.snippetsAdd).last);
      await tester.pumpAndSettle();

      final tile = find.text('Signature');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsDeleteTitle), findsOneWidget);
    });

    // The picker-trigger header (and thus its empty-list hint) only renders
    // on macOS — see the `Platform.isMacOS` guard in `SnippetsPage`.
    testWidgets('a set trigger word with an empty snippet list shows the '
        '"trigger does nothing yet" hint until the first snippet exists', (
      tester,
    ) async {
      if (!Platform.isMacOS) return;
      await tester.pumpWidget(
        makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(
                const AppSettings(
                  behavior: BehaviorSettings(snippetPickerTrigger: 'snippet'),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.snippetsPickerTriggerEmptyListHint),
        findsOneWidget,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      await container
          .read(snippetsProvider.notifier)
          .add('Signature', 'Best,\nSilvio');
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerTriggerEmptyListHint), findsNothing);
    });

    testWidgets('an empty trigger word shows no empty-list hint even while '
        'the snippet list is empty', (tester) async {
      if (!Platform.isMacOS) return;
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsPickerTriggerEmptyListHint), findsNothing);
    });

    // Notizen bound Ctrl/Cmd+N from the start; its two sibling list screens
    // did not, so "create the next one without leaving the keyboard" was a
    // skill that only paid off on one of the three. The shared shell binds
    // it for both.
    testWidgets('Ctrl/Cmd+N opens the add dialog', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.snippetsNewSnippet), findsNothing);

      await _pressNewItemChord(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
    });

    testWidgets('Ctrl/Cmd+N also fires while the search field has focus', (
      tester,
    ) async {
      // Deliberately unguarded: Ctrl/Cmd+N is not a text-editing binding on
      // any of the three platforms, so the chord means "new snippet"
      // wherever the caret happens to sit — the same contract Notizen has.
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).at(_fieldOffset));
      await tester.pumpAndSettle();

      await _pressNewItemChord(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.snippetsNewSnippet), findsOneWidget);
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
