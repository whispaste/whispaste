/// Tests for [SettingsPortabilitySection] — the standalone "Backup & Transfer"
/// settings section that hosts the file-based settings export/import entry
/// (moved out of AdvancedSection).
///
/// Only structural/render coverage lives here — tapping either button
/// resolves a real Downloads/Documents directory via `path_provider`,
/// which hangs in `flutter_test` without a platform-channel mock. The
/// actual export/import/round-trip behaviour is covered by
/// `test/services/settings_portability_controller_test.dart` and
/// `test/services/settings_portability_service_test.dart` against
/// injected fakes.
///
/// The second group covers discoverability: the section is reachable via the
/// settings search, and selecting its suggestion scrolls to the section and
/// draws the temporary highlight border around it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/sections/settings_portability_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('SettingsPortabilitySection', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPortabilitySection()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'renders the Export/Import Settings entry with both action buttons',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SettingsPortabilitySection()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Export / Import Settings'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Export'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Import'), findsOneWidget);
      },
    );

    testWidgets('section title is distinct from the row label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SettingsPortabilitySection()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Section header and row label must not collapse into the same string —
      // both are rendered on the same page.
      expect(find.text('Backup & Transfer'), findsOneWidget);
      expect(find.text('Export / Import Settings'), findsOneWidget);
    });
  });

  group('Settings search — portability section is discoverable', () {
    List<String> sectionKeysFor(String query, {String locale = 'en'}) =>
        matchSettingsEntries(
          kSettingsSearchTable,
          query,
          locale,
        ).map((e) => e.sectionKey).toList();

    test('EN queries (export, import, migrate, backup, restore) match', () {
      for (final query in [
        'export',
        'import',
        'migrate',
        'transfer',
        'move',
        'backup',
        'restore',
      ]) {
        expect(
          sectionKeysFor(query),
          contains('settingsPortability'),
          reason: '"$query" must find the portability section',
        );
      }
    });

    test('DE queries (Umzug, übertragen, sichern, …) match', () {
      for (final query in [
        'Umzug',
        'übertragen',
        'sichern',
        'wiederherstellen',
        'Gerätewechsel',
      ]) {
        expect(
          sectionKeysFor(query, locale: 'de'),
          contains('settingsPortability'),
          reason: '"$query" must find the portability section',
        );
      }
    });
  });

  group('Settings search — jump to portability section sets highlight', () {
    testWidgets(
      'selecting the search suggestion scrolls to the section and draws '
      'the highlight border, which auto-clears afterwards',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(const SettingsPage(), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        final element = tester.element(find.byType(SettingsPage));
        final container = ProviderScope.containerOf(element);

        // Type a query that uniquely matches the portability entry; set the
        // provider directly as well to bypass the 250 ms debounce.
        final field = find.descendant(
          of: find.byType(SettingsSearchField),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'migrate');
        container.read(settingsSearchQueryProvider.notifier).set('migrate');
        await tester.pumpAndSettle();

        final matches = container.read(settingsSearchMatchesProvider);
        expect(
          matches.map((e) => e.sectionKey),
          contains('settingsPortability'),
          reason: '"migrate" must surface the portability suggestion',
        );
        expect(
          matches.first.sectionKey,
          'settingsPortability',
          reason: '"migrate" must match only the portability entry',
        );

        // ArrowDown highlights the first suggestion; Enter selects it — the
        // same path a keyboard user takes (see settings_search_field.dart's
        // _selectEntry, which sets scroll + highlight targets).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(
          container.read(settingsHighlightTargetProvider),
          'settingsPortability',
          reason: 'Selecting the suggestion must set the highlight target',
        );

        // Let the scroll-jump and the highlight animation play out.
        await tester.pumpAndSettle();

        // The sectionWithHighlight wrapper (settings_page.dart) renders the
        // highlight as a bordered BoxDecoration on an AnimatedContainer
        // directly around the section widget.
        final wrapperFinder = find
            .ancestor(
              of: find.byType(SettingsPortabilitySection),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final highlighted = tester.widget<AnimatedContainer>(wrapperFinder);
        final decoration = highlighted.decoration;
        expect(
          decoration,
          isA<BoxDecoration>().having((d) => d.border, 'border', isNotNull),
          reason: 'Jump target must carry the highlight border',
        );

        // The highlight clears itself after 1.5 s (SettingsPage timer).
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(container.read(settingsHighlightTargetProvider), isNull);
        final cleared = tester.widget<AnimatedContainer>(wrapperFinder);
        expect(
          (cleared.decoration as BoxDecoration?)?.border,
          isNull,
          reason: 'Highlight border must be gone after the clear timer',
        );
      },
    );
  });
}
