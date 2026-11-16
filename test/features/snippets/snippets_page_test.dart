/// Tests for [SnippetsPage].
///
/// Covers: empty state, Add editor, editor validation, Edit pre-fill, search
/// filter, no-results state, hover → delete with undo toast, telemetry category.
library;

import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/find_replace_bar.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/wp_search_field.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

import '../../fixtures/test_helpers.dart';

import 'package:whispaste/widgets/wp_copy_feedback.dart';

Finder _id(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

Finder _k(String key) => find.byKey(ValueKey(key));

Finder _edit(String key) =>
    find.descendant(of: _k(key), matching: find.byType(EditableText));

/// Stored snippet rows, addressed by their key prefix.
Finder _rows() => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> &&
      (k.value.startsWith('snippets-row-') ||
          k.value.startsWith('snippets-trash-row-'));
});

/// Trashed snippet rows, addressed by their key prefix.
Finder _trashRows() => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> && k.value.startsWith('snippets-trash-row-');
});

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SnippetsPage)));

/// The toolbar search field, found through its wrapper, not by tree index.
Finder get _searchField => find.descendant(
  of: find.byType(WpSearchField),
  matching: find.byType(TextField),
);

/// Sends the platform's "new item" chord — Cmd on macOS, Ctrl elsewhere,
/// exactly as `WpSearchableListPage` binds it.
Future<void> _pressNewItemChord(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(modifier);
}

void main() {
  group('SnippetsPage', () {
    testWidgets('starts empty — no sample data is seeded', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(_container(tester).read(snippetsProvider).value, isEmpty);
      expect(_rows(), findsNothing);
    });

    testWidgets('Add button opens the editor', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();

      expect(_byId('snippets-editor'), findsOneWidget);
      expect(_k('snippets-title-field'), findsOneWidget);
      expect(_k('snippets-body-field'), findsOneWidget);
    });

    // The editor treats Escape as "close", and by then it may hold a prompt
    // template the user has been typing into. The body text still being there
    // after Escape on the find bar is the assertion.
    testWidgets('the editor carries the editor toolbar; Escape closes the find '
        'bar without discarding the draft', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      expect(find.byType(WpMarkdownToolbar), findsOneWidget);

      await tester.enterText(
        _edit('snippets-body-field'),
        'a template worth keeping',
      );
      // The 48 dp bar wraps in the narrow test window, so the find button
      // can sit below the fold of the scrolling form (#652).
      final findToggle = _byId('snippets-body-toolbar-find');
      await tester.ensureVisible(findToggle);
      await tester.pumpAndSettle();
      await tester.tap(findToggle);
      await tester.pumpAndSettle();
      expect(find.byType(WpFindReplaceBar), findsOneWidget);

      await tester.tap(
        find
            .descendant(
              of: find.byType(WpFindReplaceBar),
              matching: find.byType(TextField),
            )
            .first,
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(WpFindReplaceBar), findsNothing);
      expect(_byId('snippets-editor'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(_edit('snippets-body-field'))
            .controller
            .text,
        'a template worth keeping',
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

      // TextFields in tree order: [0] page search, [1] title, [2] body
      await tester.enterText(_edit('snippets-title-field'), 'Signature');
      await tester.enterText(_edit('snippets-body-field'), 'Best,\nSilvio');
      await tester.pumpAndSettle();

      await tester.pump(SnippetEditor.autosaveDelay);
      await tester.pumpAndSettle();

      expect(_rows(), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      final counts = container
          .read(telemetrySessionAggregatorProvider)
          .debugCounts;
      expect(counts[('snippets', 'create', null)], 1);
      expect(counts[('replacements', 'create', null)], isNull);
    });

    testWidgets('tapping a tile opens it straight in the editor with the '
        'stored title (#1498)', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(_edit('snippets-title-field'), 'Greeting');
      await tester.enterText(_edit('snippets-body-field'), 'Hi there');
      await tester.pumpAndSettle();
      await tester.pump(SnippetEditor.autosaveDelay);
      await tester.pumpAndSettle();

      await tester.tap(_byId('snippets-editor-close'));
      await tester.pumpAndSettle();
      expect(_byId('snippets-editor'), findsNothing);

      await tester.tap(_rows().first);
      await tester.pumpAndSettle();
      expect(_byId('snippets-editor'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(_edit('snippets-title-field'))
            .controller
            .text,
        'Greeting',
      );
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
        await tester.enterText(_edit('snippets-title-field'), title);
        await tester.enterText(_edit('snippets-body-field'), body);
        await tester.pumpAndSettle();
        await tester.pump(SnippetEditor.autosaveDelay);
        await tester.pumpAndSettle();
      }

      expect(_rows(), findsNWidgets(2));

      await tester.enterText(_searchField, 'Sign');
      await tester.pumpAndSettle();

      expect(_rows(), findsOneWidget);
    });

    testWidgets('search with no match lists no rows', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(_edit('snippets-title-field'), 'Signature');
      await tester.enterText(_edit('snippets-body-field'), 'Best, Silvio');
      await tester.pumpAndSettle();
      await tester.pump(SnippetEditor.autosaveDelay);
      await tester.pumpAndSettle();

      await tester.enterText(_searchField, 'zzzznonexistent');
      await tester.pumpAndSettle();

      expect(_rows(), findsNothing);
    });

    testWidgets('hover shows delete icon; tapping it deletes and offers undo', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          noticeBar: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(_edit('snippets-title-field'), 'Signature');
      await tester.enterText(_edit('snippets-body-field'), 'Best, Silvio');
      await tester.pumpAndSettle();
      await tester.pump(SnippetEditor.autosaveDelay);
      await tester.pumpAndSettle();

      final tile = _rows().first;
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();

      expect(_rowDelete, findsOneWidget);

      await tester.tap(_rowDelete);
      await tester.pumpAndSettle();

      // Deleted at once; the undo toast is the safety net.
      expect(find.byKey(const ValueKey('snippets-undo')), findsOneWidget);
      expect(_rows(), findsNothing);

      // The undo click brings the snippet back.
      await tester.tap(find.byKey(const ValueKey('snippets-undo')));
      await tester.pumpAndSettle();
      expect(_rows(), findsOneWidget);
    });

    testWidgets('a deleted snippet waits in the trash and can be restored', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(_edit('snippets-title-field'), 'Signature');
      await tester.enterText(_edit('snippets-body-field'), 'Best, Silvio');
      await tester.pumpAndSettle();
      await tester.pump(SnippetEditor.autosaveDelay);
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(_rows().first));
      await tester.pumpAndSettle();
      await tester.tap(_rowDelete);
      await tester.pumpAndSettle();

      await tester.tap(_id('snippets-filter-menu'));
      await tester.pumpAndSettle();
      await tester.tap(_id('snippets-filter-trash'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_trashRows(), findsOneWidget);

      await gesture.moveTo(tester.getCenter(_trashRows().first));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'snippets-restore-',
              ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_rows(), findsNothing);

      await tester.tap(_id('snippets-filter-mark-view-remove'));
      await tester.pumpAndSettle();
      expect(_rows(), findsOneWidget);
    });

    // UIA-SNP-07: the duplicate keeps the copy suffix in the app language.
    testWidgets('a duplicate gets a localised copy suffix (UIA-SNP-07)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      await container
          .read(snippetsProvider.notifier)
          .add('Signature', 'Best, Silvio');
      await tester.pumpAndSettle();

      // Duplicate has no row button (one action set per row, #1498): it is
      // the row's context-menu item.
      await tester.tap(_rows().first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) {
          final k = w.key;
          return k is ValueKey<String> &&
              k.value.startsWith('snippets-duplicate-');
        }),
      );
      await tester.pumpAndSettle();

      final titles = container
          .read(snippetsProvider)
          .requireValue
          .map((e) => e.title);
      expect(titles, contains('Signature (Kopie)'));
      expect(titles, isNot(contains('Signature (copy)')));
    });

    testWidgets('copying a snippet answers at its row, not with a toast', (
      tester,
    ) async {
      final written = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            written.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      await container
          .read(snippetsProvider.notifier)
          .add('Signature', 'Best, Silvio');
      await tester.pumpAndSettle();
      final id = container.read(snippetsProvider).requireValue.single.id;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(_rows().first));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('snippets-copy-$id')));
      await tester.pump();
      await tester.pump();

      expect(written, ['Best, Silvio']);
      expect(find.byKey(ValueKey('copy-note-snippet-$id')), findsOneWidget);
      await tester.pumpAndSettle(WpCopyMarkNotifier.copiedFor);
    });

    // Notizen bound Ctrl/Cmd+N from the start; its two sibling list screens
    // did not, so "create the next one without leaving the keyboard" was a
    // skill that only paid off on one of the three. The shared shell binds
    // it for both.
    testWidgets('Ctrl/Cmd+N opens the add editor', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(_byId('snippets-editor'), findsNothing);

      await _pressNewItemChord(tester);
      await tester.pumpAndSettle();

      expect(_byId('snippets-editor'), findsOneWidget);
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

      await tester.tap(_searchField);
      await tester.pumpAndSettle();

      await _pressNewItemChord(tester);
      await tester.pumpAndSettle();

      expect(_byId('snippets-editor'), findsOneWidget);
    });

    testWidgets('Delete on the focused row deletes and offers undo', (
      tester,
    ) async {
      // Notizen deletes the focused row from the keyboard; its two siblings
      // could only do it by mouse. Same keys now, different consequence by
      // necessity: the row goes to the trash and the undo toast takes it back.
      await tester.pumpWidget(
        makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          noticeBar: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      await tester.enterText(_edit('snippets-title-field'), 'Signature');
      await tester.enterText(_edit('snippets-body-field'), 'Best, Silvio');
      await tester.pumpAndSettle();
      await tester.pump(SnippetEditor.autosaveDelay);
      await tester.pumpAndSettle();
      // The editor stays open after the autosave (#1498); Esc closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Walk the traversal order until the row reveals its delete action.
      for (var i = 0; i < 14; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (_rowDelete.evaluate().isNotEmpty) break;
      }
      expect(
        _rowDelete,
        findsOneWidget,
        reason: 'the row reveals its delete action on focus, not just hover',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      // Deleted at once; the undo toast is the safety net.
      expect(find.byKey(const ValueKey('snippets-undo')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Interactive-snippet template editor — user-placed {{fieldName}}
  // placeholders instead of the old fixed heading-per-field layout.
  // ---------------------------------------------------------------------------

  group('Interactive snippet templates', () {
    Future<void> openInteractiveEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestable(const SnippetsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      tester
          .widget<WpSegmentedChoice<String>>(_k('snippets-kind-choice'))
          .onChanged('interactive');
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows a warning and disables save while a field is not referenced '
      'in the template',
      (tester) async {
        await openInteractiveEditor(tester);

        await tester.enterText(_edit('snippets-title-field'), 'Bug Report');
        await tester.enterText(_edit('snippets-field-name-0'), 'Titel');
        // Let the focused field's caret scroll settle first, then bring the
        // add button (below the template and the field list) into view.
        await tester.pumpAndSettle();
        await tester.ensureVisible(_k('snippets-field-add'));
        await tester.pumpAndSettle();
        await tester.tap(_k('snippets-field-add'));
        await tester.pumpAndSettle();
        await tester.enterText(_edit('snippets-field-name-1'), 'Beschreibung');
        await tester.pumpAndSettle();

        await tester.pump(SnippetEditor.autosaveDelay);
        await tester.pumpAndSettle();
        expect(
          _container(tester).read(snippetsProvider).value,
          isEmpty,
          reason: 'nothing is stored while a field has no placeholder',
        );
        expect(_byId('snippets-editor-invalid'), findsOneWidget);
      },
    );

    testWidgets(
      'the insert button places {{fieldName}} in the template and the '
      'saved snippet composes from it',
      (tester) async {
        await openInteractiveEditor(tester);

        await tester.enterText(_edit('snippets-title-field'), 'Bug Report');
        await tester.enterText(_edit('snippets-field-name-0'), 'Titel');
        // Let the focused field's caret scroll settle first, then bring the
        // add button (below the template and the field list) into view.
        await tester.pumpAndSettle();
        await tester.ensureVisible(_k('snippets-field-add'));
        await tester.pumpAndSettle();
        await tester.tap(_k('snippets-field-add'));
        await tester.pumpAndSettle();
        await tester.enterText(_edit('snippets-field-name-1'), 'Beschreibung');
        await tester.pumpAndSettle();

        final insertButtons = _k('snippets-field-insert');
        expect(insertButtons, findsNWidgets(2));
        await tester.ensureVisible(insertButtons.at(0));
        await tester.tap(insertButtons.at(0));
        await tester.pumpAndSettle();
        await tester.ensureVisible(insertButtons.at(1));
        await tester.tap(insertButtons.at(1));
        await tester.pumpAndSettle();

        final template = tester.widget<EditableText>(
          _edit('snippets-body-field'),
        );
        expect(template.controller.text, '{{Titel}}{{Beschreibung}}');

        await tester.pump(SnippetEditor.autosaveDelay);
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SnippetsPage)),
        );
        final saved = container.read(snippetsProvider).value!.single;
        expect(saved.body, '{{Titel}}{{Beschreibung}}');
        expect(saved.fields, ['Titel', 'Beschreibung']);
      },
    );

    testWidgets(
      'reopening an existing interactive snippet pre-fills its template',
      (tester) async {
        await openInteractiveEditor(tester);
        await tester.enterText(_edit('snippets-title-field'), 'Bug Report');
        await tester.enterText(_edit('snippets-field-name-0'), 'Titel');
        // Let the focused field's caret scroll settle first, then bring the
        // add button (below the template and the field list) into view.
        await tester.pumpAndSettle();
        await tester.ensureVisible(_k('snippets-field-add'));
        await tester.pumpAndSettle();
        await tester.tap(_k('snippets-field-add'));
        await tester.pumpAndSettle();
        await tester.enterText(_edit('snippets-field-name-1'), 'Beschreibung');
        await tester.pumpAndSettle();
        final insertButtons = _k('snippets-field-insert');
        await tester.ensureVisible(insertButtons.at(0));
        await tester.tap(insertButtons.at(0));
        await tester.pumpAndSettle();
        await tester.enterText(
          _edit('snippets-body-field'),
          'Betreff: {{Titel}}\n\n{{Beschreibung}}',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(insertButtons.at(1));
        await tester.tap(insertButtons.at(1));
        await tester.pumpAndSettle();
        await tester.pump(SnippetEditor.autosaveDelay);
        await tester.pumpAndSettle();

        await tester.tap(_byId('snippets-editor-close'));
        await tester.pumpAndSettle();
        await tester.tap(_rows().first);
        await tester.pumpAndSettle();

        expect(_byId('snippets-editor'), findsOneWidget);
        final template = tester.widget<EditableText>(
          _edit('snippets-body-field'),
        );
        expect(template.controller.text, contains('Betreff: {{Titel}}'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Picker-Hotkey auf der Seite — zweite Aufrufstelle, eine Wahrheit (Ticket 27)
  // ---------------------------------------------------------------------------

  group('SnippetsPage — picker link (UX-030)', () {
    Widget subject({AppSettings? settings, bool available = true}) =>
        makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings ?? const AppSettings()),
            ),
            // The one availability answer the Settings row reads as well.
            snippetPickerAvailabilityProvider.overrideWithValue(available),
          ],
        );

    testWidgets('the link opens Settings at the trigger-word row', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      // The link sits in the empty state's footer, under the example chips.
      await tester.ensureVisible(_byId('snippets-picker-settings-link'));
      await tester.pumpAndSettle();
      await tester.tap(_byId('snippets-picker-settings-link'));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SnippetsPage)),
      );
      expect(
        container.read(settingsScrollTargetProvider),
        'general-snippet-picker-trigger',
      );
      expect(container.read(activePageProvider), 'settings');
    });

    testWidgets('where the platform has no picker, the page offers no link', (
      tester,
    ) async {
      await tester.pumpWidget(subject(available: false));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetsPickerUnavailable')),
        findsOneWidget,
      );
      expect(_byId('snippets-picker-settings-link'), findsNothing);
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

/// The row's delete action, addressed by its key (the trash chip carries the
/// same icon).
final _rowDelete = find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('snippets-delete-') &&
      !(w.key! as ValueKey<String>).value.startsWith('snippets-delete-forever'),
);

/// A control found by its stable id (the accessibility identifier).
Finder _byId(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);
