/// Widget tests for settings search keyboard accessibility (slice 09).
///
/// AC coverage:
///   AC1: Ctrl+F / Cmd+F focus shortcut moves focus into the search field
///   AC2: ArrowDown/Up navigate suggestions; Enter triggers section jump
///   AC3: The search field has a Semantics label; a live-region node carries
///        the result count when the query is non-blank
///   AC4: All widget tests pass without flakes
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helper: pump SettingsPage and return the ProviderContainer.
// ---------------------------------------------------------------------------

Future<ProviderContainer> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(const SettingsPage(), locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
  final element = tester.element(find.byType(SettingsPage));
  return ProviderScope.containerOf(element);
}

// ---------------------------------------------------------------------------
// Helper: pump a standalone SettingsSearchField for focused unit tests.
// ---------------------------------------------------------------------------

/// Returns (container, focusNode) for a standalone [SettingsSearchField].
Future<(ProviderContainer, FocusNode)> _pumpStandaloneField(
  WidgetTester tester,
) async {
  final focusNode = FocusNode();
  ProviderContainer? container;

  await tester.pumpWidget(
    ProviderScope(
      child: Builder(
        builder: (ctx) {
          container = ProviderScope.containerOf(ctx);
          return MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(size: Size(800, 600)),
                child: SettingsSearchField(focusNode: focusNode),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container!, focusNode);
}

// ---------------------------------------------------------------------------

void main() {
  // ── AC1: Ctrl/Cmd+F focus shortcut ────────────────────────────────────────

  group('AC1: Ctrl/Cmd+F focus shortcut (SettingsPage)', () {
    testWidgets('Ctrl+F / Cmd+F focuses the settings search field', (
      tester,
    ) async {
      await _pumpSettings(tester);

      // The search field's EditableText should not have focus initially.
      final editableText = find.descendant(
        of: find.byType(SettingsSearchField),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(editableText).focusNode.hasFocus,
        isFalse,
        reason: 'Field must not have focus before the shortcut',
      );

      // Press the platform-appropriate shortcut.
      if (Platform.isMacOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      }
      await tester.pumpAndSettle();

      expect(
        tester.widget<EditableText>(editableText).focusNode.hasFocus,
        isTrue,
        reason: 'Field must have focus after the shortcut',
      );
    });
  });

  // ── AC2: Arrow/Enter navigation in dropdown ────────────────────────────────

  group('AC2: Arrow/Enter dropdown navigation', () {
    testWidgets('ArrowDown then Enter triggers section jump', (tester) async {
      final (container, focusNode) = await _pumpStandaloneField(tester);
      addTearDown(focusNode.dispose);
      addTearDown(container.dispose);

      // Use a query that produces at least one match; set provider directly to
      // bypass the 250 ms debounce and immediately show the dropdown.
      focusNode.requestFocus();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'audio');
      container.read(settingsSearchQueryProvider.notifier).set('audio');
      await tester.pumpAndSettle();

      final matches = container.read(settingsSearchMatchesProvider);
      expect(
        matches,
        isNotEmpty,
        reason: '"audio" must match at least one section',
      );

      // No scroll target set yet.
      expect(container.read(settingsScrollTargetProvider), isNull);

      // ArrowDown once → highlight index 0; Enter → jump.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        container.read(settingsScrollTargetProvider),
        isNotNull,
        reason: 'Enter after ArrowDown must set settingsScrollTargetProvider',
      );
    });

    testWidgets(
      'ArrowDown → ArrowDown → ArrowUp navigates to first suggestion on Enter',
      (tester) async {
        final (container, focusNode) = await _pumpStandaloneField(tester);
        addTearDown(focusNode.dispose);
        addTearDown(container.dispose);

        focusNode.requestFocus();
        await tester.pump();

        // "recording" appears in Audio, Overlay, Floating Button, Hotkey and
        // Recording Safety sections — guaranteed > 1 match.
        await tester.enterText(find.byType(TextField), 'recording');
        container.read(settingsSearchQueryProvider.notifier).set('recording');
        await tester.pumpAndSettle();

        final matches = container.read(settingsSearchMatchesProvider);
        expect(
          matches.length,
          greaterThan(1),
          reason: '"recording" must match multiple sections',
        );

        // Down → 0, Down → 1, Up → 0.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // idx 0
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // idx 1
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // idx 0
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(
          container.read(settingsScrollTargetProvider),
          equals(matches[0].sectionKey),
        );
      },
    );

    testWidgets('Escape clears the search query', (tester) async {
      final (container, focusNode) = await _pumpStandaloneField(tester);
      addTearDown(focusNode.dispose);
      addTearDown(container.dispose);

      focusNode.requestFocus();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'audio');
      container.read(settingsSearchQueryProvider.notifier).set('audio');
      await tester.pumpAndSettle();

      expect(container.read(settingsSearchMatchesProvider), isNotEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(container.read(settingsSearchQueryProvider), equals(''));
    });
  });

  // ── AC3: Semantics ────────────────────────────────────────────────────────

  group('AC3: Semantics accessibility', () {
    testWidgets('Search field has an accessible Semantics label', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));

      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(l10n.settingsSearchFieldLabel),
        findsWidgets,
        reason: 'Search field must expose its accessible label',
      );
    });

    testWidgets('Live region carries result count for non-blank query', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));

      final (container, focusNode) = await _pumpStandaloneField(tester);
      addTearDown(focusNode.dispose);
      addTearDown(container.dispose);

      container.read(settingsSearchQueryProvider.notifier).set('audio');
      await tester.pumpAndSettle();

      final matches = container.read(settingsSearchMatchesProvider);
      expect(matches, isNotEmpty);

      final expectedLabel = l10n.settingsSearchResultCount(matches.length);
      expect(
        find.bySemanticsLabel(expectedLabel),
        findsWidgets,
        reason: 'Live region must carry the current result count',
      );
    });

    testWidgets('Live region is blank when query is empty', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));

      final (container, focusNode) = await _pumpStandaloneField(tester);
      addTearDown(focusNode.dispose);
      addTearDown(container.dispose);

      container.read(settingsSearchQueryProvider.notifier).set('');
      await tester.pumpAndSettle();

      // "1 result" label must not appear when query is blank.
      expect(
        find.bySemanticsLabel(l10n.settingsSearchResultCount(1)),
        findsNothing,
        reason: 'Live region must not show count when query is blank',
      );
    });
  });
}
