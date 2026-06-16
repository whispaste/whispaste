/// Widget tests for the settings live-row-filter (slice 08).
///
/// AC coverage:
///   AC1: typing hides non-matching sections across all sections
///   AC2: a section whose rows are all filtered is hidden entirely (no empty header)
///   AC3: zero matches → "No Results" empty state visible
///   AC4: clearing the query (setting to '') restores the full, unfiltered list
///
/// The filter logic lives in [settingsSectionMatchSetProvider] (derived from the
/// slice-07 matcher) and is applied in [SettingsPage._build].  These tests set the
/// query directly via the provider to bypass the debounce in [SettingsSearchField].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps [SettingsPage] with EN locale and returns the [ProviderContainer]
/// so that tests can drive [settingsSearchQueryProvider] directly.
Future<ProviderContainer> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(const SettingsPage(), locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
  final element = tester.element(find.byType(SettingsPage));
  return ProviderScope.containerOf(element);
}

/// Sets the settings search query via the provider and settles the widget tree.
Future<void> _setQuery(
  WidgetTester tester,
  ProviderContainer container,
  String query,
) async {
  container.read(settingsSearchQueryProvider.notifier).set(query);
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late L10n l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Settings live filter', () {
    // ── AC1: typing hides non-matching sections ──────────────────────────────

    testWidgets('AC1: query "keyboard shortcut" hides Interface section', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      // Baseline: Interface section is visible before filtering
      expect(find.text(l10n.settingsInterface), findsOneWidget);

      // Filter to 'hotkey' only — Interface should disappear
      await _setQuery(tester, container, 'keyboard shortcut');

      expect(find.text(l10n.settingsInterface), findsNothing);
    });

    testWidgets(
      'AC1: query "keyboard shortcut" keeps Keyboard Shortcut section visible',
      (tester) async {
        final container = await _pumpSettings(tester);

        await _setQuery(tester, container, 'keyboard shortcut');

        expect(find.text(l10n.settingsKeyboardShortcut), findsOneWidget);
      },
    );

    testWidgets(
      'AC1: query "microphone" shows Audio section and hides Keyboard Shortcut',
      (tester) async {
        final container = await _pumpSettings(tester);

        await _setQuery(tester, container, 'microphone');

        expect(find.text(l10n.settingsAudio), findsOneWidget);
        expect(find.text(l10n.settingsKeyboardShortcut), findsNothing);
      },
    );

    // ── AC2: sections without matches are hidden entirely ────────────────────

    testWidgets('AC2: filtered-out sections leave no header text in the tree', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      // Query matches only the 'hotkey' section
      await _setQuery(tester, container, 'global hotkey');

      // These section headers must not appear anywhere in the tree
      expect(find.text(l10n.settingsInterface), findsNothing);
      expect(find.text(l10n.settingsSpeechRecognition), findsNothing);
      expect(find.text(l10n.settingsAudio), findsNothing);
      expect(find.text(l10n.settingsAfterTranscription), findsNothing);
    });

    // ── AC3: zero matches → "No Results" message ────────────────────────────

    testWidgets('AC3: zero-match query shows No Results empty state', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      await _setQuery(tester, container, 'zzznomatch_unlikely_query_99');

      expect(find.text(l10n.settingsSearchNoResults), findsOneWidget);
    });

    testWidgets('AC3: no section headers visible when no results', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      await _setQuery(tester, container, 'zzznomatch_unlikely_query_99');

      expect(find.text(l10n.settingsInterface), findsNothing);
      expect(find.text(l10n.settingsKeyboardShortcut), findsNothing);
    });

    // ── AC4: clearing the query restores the full unfiltered list ────────────

    testWidgets('AC4: clearing query after filter restores Interface section', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      // Apply a filter
      await _setQuery(tester, container, 'keyboard shortcut');
      expect(find.text(l10n.settingsInterface), findsNothing);

      // Clear the query
      await _setQuery(tester, container, '');

      // Interface must be back
      expect(find.text(l10n.settingsInterface), findsOneWidget);
    });

    testWidgets(
      'AC4: clearing query after zero-match hides the No Results state',
      (tester) async {
        final container = await _pumpSettings(tester);

        // Trigger zero-match state
        await _setQuery(tester, container, 'zzznomatch_unlikely_query_99');
        expect(find.text(l10n.settingsSearchNoResults), findsOneWidget);

        // Clear the query
        await _setQuery(tester, container, '');

        // Empty state must be gone
        expect(find.text(l10n.settingsSearchNoResults), findsNothing);
      },
    );

    testWidgets(
      'AC4: blank query shows all sections including Audio and Sound',
      (tester) async {
        final container = await _pumpSettings(tester);

        // Apply filter then clear
        await _setQuery(tester, container, 'keyboard shortcut');
        await _setQuery(tester, container, '');

        expect(find.text(l10n.settingsAudio), findsOneWidget);
        expect(find.text(l10n.settingsKeyboardShortcut), findsOneWidget);
      },
    );
  });

  // ── settingsSectionMatchSetProvider unit-level checks ─────────────────────

  group('settingsSectionMatchSetProvider', () {
    test('returns null for blank query (show all)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Blank query → null (show all)
      expect(container.read(settingsSectionMatchSetProvider), isNull);
    });

    test('returns Set for non-blank query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(settingsSearchQueryProvider.notifier).set('keyboard');
      final result = container.read(settingsSectionMatchSetProvider);

      expect(result, isNotNull);
      expect(result, isA<Set<String>>());
    });

    test('matches hotkey section for "keyboard shortcut"', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(settingsSearchQueryProvider.notifier)
          .set('keyboard shortcut');
      final result = container.read(settingsSectionMatchSetProvider);

      expect(result, contains('hotkey'));
      expect(result, isNot(contains('interface')));
    });

    test('returns empty set for no-match query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(settingsSearchQueryProvider.notifier).set('zzznomatch_99');
      final result = container.read(settingsSectionMatchSetProvider);

      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('returns null again after clearing query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(settingsSearchQueryProvider.notifier).set('keyboard');
      expect(container.read(settingsSectionMatchSetProvider), isNotNull);

      container.read(settingsSearchQueryProvider.notifier).set('');
      expect(container.read(settingsSectionMatchSetProvider), isNull);
    });
  });
}
