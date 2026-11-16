/// Tests for [ReplacementsPage].
///
/// Behaviour only (#1267): elements are addressed by key/testID, never by
/// visible text. Covers: sample data on empty DB, Add dialog, dialog
/// validation, Edit pre-fill, search filter, enable/disable toggle,
/// delete confirmation, fuzzy mode.
library;

import 'dart:ui';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/services/replacements/vocabulary_import_service.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake settings notifier — captures updateSettings calls without touching
// SQLite (the real notifier reads/writes the DB).
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

Finder _k(String key) => find.byKey(ValueKey(key));

/// The list rows only (not their `-similar` / `-origin` parts).
Finder _rows() => find.byWidgetPredicate((w) {
  final k = w.key;
  if (k is! ValueKey<String>) return false;
  final v = k.value;
  return v.startsWith('replacements-row-') &&
      !v.endsWith('-similar') &&
      !v.endsWith('-origin');
});

Finder _search() => find.byType(TextField).first;

Future<void> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    makeTestable(
      const ReplacementsPage(),
      overrides: overrides,
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAdd(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.plus));
  await tester.pumpAndSettle();
}

Future<void> _chooseMode(
  WidgetTester tester,
  TextReplacementMatchMode mode,
) async {
  tester
      .widget<WpSegmentedChoice<TextReplacementMatchMode>>(
        _k('replacements-match-mode-choice'),
      )
      .onChanged(mode);
  await tester.pumpAndSettle();
}

void main() {
  group('ReplacementsPage', () {
    testWidgets('renders sample entries on first load (empty DB)', (
      tester,
    ) async {
      await _pump(tester);
      expect(_rows(), findsNWidgets(3));
    });

    testWidgets('Add opens the dialog; save stays disabled while empty', (
      tester,
    ) async {
      await _pump(tester);
      expect(_k('replacements-trigger-field-0'), findsNothing);

      await _openAdd(tester);

      expect(_k('replacements-trigger-field-0'), findsOneWidget);
      expect(
        tester
            .widget<WpButton>(
              find.ancestor(
                of: _k('replacements-save'),
                matching: find.byType(WpButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField).at(1), 'omw');
      await tester.enterText(find.byType(TextField).at(2), 'on my way');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WpButton>(
              find.ancestor(
                of: _k('replacements-save'),
                matching: find.byType(WpButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('adding a second trigger phrase saves both triggers', (
      tester,
    ) async {
      await _pump(tester);
      await _openAdd(tester);

      await tester.enterText(find.byType(TextField).at(1), 'omw');
      await tester.tap(_k('replacements-trigger-add'));
      await tester.pumpAndSettle();
      await tester.enterText(_k('replacements-trigger-field-1'), 'otw');
      await tester.enterText(_k('replacements-replacement-field'), 'on my way');
      await tester.pumpAndSettle();

      await tester.tap(_k('replacements-save'));
      await tester.pumpAndSettle();

      expect(_rows(), findsNWidgets(4));
      await tester.enterText(_search(), 'otw');
      await tester.pumpAndSettle();
      expect(_rows(), findsOneWidget);
    });

    testWidgets('the last remaining trigger cannot be removed', (tester) async {
      await _pump(tester);
      await _openAdd(tester);

      expect(_k('replacements-trigger-remove-0'), findsNothing);

      await tester.tap(_k('replacements-trigger-add'));
      await tester.pumpAndSettle();
      expect(_k('replacements-trigger-remove-0'), findsOneWidget);
      expect(_k('replacements-trigger-remove-1'), findsOneWidget);

      await tester.tap(_k('replacements-trigger-remove-0'));
      await tester.pumpAndSettle();
      expect(_k('replacements-trigger-remove-0'), findsNothing);
      expect(_k('replacements-trigger-field-1'), findsNothing);
    });

    testWidgets('tapping a row opens the edit dialog with its trigger', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(_rows().first);
      await tester.pumpAndSettle();

      expect(_k('replacements-trigger-field-0'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(
          of: _k('replacements-trigger-field-0'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, isNotEmpty);
    });

    testWidgets('search field filters visible replacements', (tester) async {
      await _pump(tester);
      expect(_rows(), findsNWidgets(3));

      await tester.enterText(_search(), 'mfg');
      await tester.pumpAndSettle();
      expect(_rows(), findsOneWidget);

      await tester.enterText(_search(), 'zzzznonexistent');
      await tester.pumpAndSettle();
      expect(_rows(), findsNothing);

      await tester.enterText(_search(), '');
      await tester.pumpAndSettle();
      expect(_rows(), findsNWidgets(3));
    });

    testWidgets(
      'the master switch sits in the overflow menu and turns the list off',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(textReplacementsEnabled: true),
        );
        await _pump(
          tester,
          overrides: [settingsProvider.overrideWith(() => notifier)],
        );
        expect(_k('replacements-enable'), findsNothing);

        await tester.tap(_k('replacements-more'));
        await tester.pumpAndSettle();
        await tester.tap(_k('replacements-toggle'));
        await tester.pumpAndSettle();

        expect(notifier.state.value?.behavior.textReplacementsEnabled, isFalse);
        expect(_k('replacements-enable'), findsOneWidget);
      },
    );

    testWidgets('toolbar controls and the disabled banner carry identifiers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(textReplacementsEnabled: false),
            ),
          ),
        ],
      );

      expect(find.bySemanticsIdentifier('replacements-search'), findsOneWidget);
      expect(find.bySemanticsIdentifier('replacements-add'), findsOneWidget);
      expect(find.bySemanticsIdentifier('replacements-more'), findsOneWidget);
      expect(find.bySemanticsIdentifier('replacements-enable'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('hover shows delete icon; confirming removes the row', (
      tester,
    ) async {
      await _pump(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(_rows().first));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pumpAndSettle();

      await tester.tap(_k('confirm-dialog-confirm'));
      await tester.pumpAndSettle();
      expect(_rows(), findsNWidgets(2));
    });

    testWidgets('Ctrl/Cmd+N opens the add dialog', (tester) async {
      await _pump(tester);
      expect(_k('replacements-trigger-field-0'), findsNothing);

      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();

      expect(_k('replacements-trigger-field-0'), findsOneWidget);
    });

    testWidgets('Delete on the focused row opens the delete confirmation', (
      tester,
    ) async {
      await _pump(tester);

      // Walk past the toolbar controls until a row reveals its delete action.
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (find.byIcon(LucideIcons.trash2).evaluate().isNotEmpty) break;
      }
      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(_k('confirm-dialog-confirm'), findsOneWidget);
    });

    testWidgets('Backspace in the search field edits text, deletes nothing', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(_search(), 'mfgx');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(_k('confirm-dialog-confirm'), findsNothing);
      expect(tester.widget<TextField>(_search()).controller!.text, 'mfg');
    });

    testWidgets('switching to Similar mode reveals the tolerance selector', (
      tester,
    ) async {
      await _pump(tester);
      await _openAdd(tester);
      expect(_k('replacements-fuzzy-tolerance-choice'), findsNothing);

      await tester.enterText(find.byType(TextField).at(1), 'get user by id');
      await tester.pumpAndSettle();
      await _chooseMode(tester, TextReplacementMatchMode.fuzzy);

      expect(_k('replacements-fuzzy-tolerance-choice'), findsOneWidget);
    });

    testWidgets(
      'Similar mode is locked for a trigger below the fuzzy minimum length',
      (tester) async {
        await _pump(tester);
        await _openAdd(tester);

        await tester.enterText(find.byType(TextField).at(1), 'id');
        await tester.pumpAndSettle();

        final choice = tester
            .widget<WpSegmentedChoice<TextReplacementMatchMode>>(
              _k('replacements-match-mode-choice'),
            );
        expect(
          choice.options
              .singleWhere((o) => o.value == TextReplacementMatchMode.fuzzy)
              .enabled,
          isFalse,
        );
        expect(_k('replacements-fuzzy-tolerance-choice'), findsNothing);
      },
    );

    testWidgets(
      'saving in Similar mode persists the mode across a reopened edit dialog',
      (tester) async {
        await _pump(tester);
        await _openAdd(tester);

        await tester.enterText(find.byType(TextField).at(1), 'get user by id');
        await tester.enterText(
          _k('replacements-replacement-field'),
          'getUserById',
        );
        await tester.pumpAndSettle();
        await _chooseMode(tester, TextReplacementMatchMode.fuzzy);
        tester
            .widget<WpSegmentedChoice<double>>(
              _k('replacements-fuzzy-tolerance-choice'),
            )
            .onChanged(0.75);
        await tester.pumpAndSettle();

        await tester.ensureVisible(_k('replacements-save'));
        await tester.tap(_k('replacements-save'));
        await tester.pumpAndSettle();

        await tester.enterText(_search(), 'get user by id');
        await tester.pumpAndSettle();
        await tester.tap(_rows().first);
        await tester.pumpAndSettle();

        final segmented = tester.widget<WpSegmentedChoice<double>>(
          _k('replacements-fuzzy-tolerance-choice'),
        );
        expect(segmented.selected, 0.75);
      },
    );

    testWidgets('an imported entry carries the imported origin marker', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final fakeService = VocabularyImportService(
        fileSystem: MemoryFileSystem(),
        pickFolder: ({initialDirectory}) async => '/fake/project',
        extract: (files) async => {'ImportedClassName'},
      );
      await _pump(
        tester,
        overrides: [
          vocabularyImportServiceProvider.overrideWithValue(fakeService),
        ],
      );

      await tester.tap(_k('replacements-more'));
      await tester.pumpAndSettle();
      await tester.tap(_k('replacements-import-folder'));
      await tester.pumpAndSettle();

      // Nothing is imported until the candidate is picked and confirmed.
      await tester.tap(_k('dictionary-import-review-row-ImportedClassName'));
      await tester.pumpAndSettle();
      await tester.tap(_k('vocabulary-import-confirm'));
      await tester.pumpAndSettle();

      await tester.enterText(_search(), 'ImportedClassName');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('replacements-origin-imported'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
