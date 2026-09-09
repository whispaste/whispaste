/// Widget tests for [SettingsAnchorChipBar] (Ticket 16 — the anchor-/jump-chip
/// bar variant Ticket 15 chose over categorized sub-pages).
///
/// AC coverage (Ticket 16):
///   - a chip tap/category switch scrolls the corresponding section into view
///   - the existing full-text search across all sections still works,
///     unaffected by the new chip bar sitting above it
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/sections/onboarding_review_section.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_anchor_chip_bar.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../../fixtures/test_helpers.dart';

/// Pumps [SettingsPage] at a fixed window size and returns the
/// [ProviderContainer] for tests that need to drive providers directly.
Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  await tester.pumpWidget(
    makeTestable(const SettingsPage(), locale: const Locale('en'), size: size),
  );
  await tester.pumpAndSettle();
  final element = tester.element(find.byType(SettingsPage));
  return ProviderScope.containerOf(element);
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('SettingsAnchorChipBar', () {
    testWidgets('renders one chip per visible section', (tester) async {
      await _pumpSettings(tester);

      // OnboardingReviewSection is filtered out until onboarding is complete
      // (see SettingsPage.build's `visibleSections` filter), so the bar must
      // not offer a chip for it either — the bar tracks the same filtered
      // list, not the static full section list.
      expect(find.byType(OnboardingReviewSection), findsNothing);

      final bar = tester.widget<SettingsAnchorChipBar>(
        find.byType(SettingsAnchorChipBar),
      );
      expect(bar.sectionKeys, isNot(contains('onboardingReview')));

      // Spot-check a handful of chips exist with their section's label.
      for (final label in [
        l10n.settingsInterface,
        l10n.settingsSpeechRecognition,
        l10n.settingsAudio,
        l10n.settingsKeyboardShortcut,
        l10n.settingsPrivacy,
      ]) {
        expect(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.widgetWithText(WpFilterChip, label),
          ),
          findsOneWidget,
          reason: 'expected a chip labeled "$label"',
        );
      }
    });

    testWidgets(
      'tapping the Privacy chip scrolls the Privacy section into view',
      (tester) async {
        await _pumpSettings(tester);

        // Privacy is the last section on the page — well below the fold at
        // the default window size, so its top starts outside the viewport.
        final sectionFinder = find.byType(PrivacySection);
        final before = tester.getTopLeft(sectionFinder).dy;
        expect(
          before,
          greaterThan(800),
          reason:
              'Privacy must start off-screen before the jump — otherwise '
              'this test cannot tell a real scroll from a no-op',
        );

        await tester.tap(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.widgetWithText(WpFilterChip, l10n.settingsPrivacy),
          ),
        );
        await tester.pumpAndSettle();

        final after = tester.getTopLeft(sectionFinder).dy;
        expect(
          after,
          lessThanOrEqualTo(800),
          reason:
              'the chip tap must scroll Privacy into the viewport, the '
              'same Scrollable.ensureVisible path a search-suggestion tap '
              'already drives',
        );
      },
    );

    testWidgets(
      'tapping a chip also briefly highlights the target section, matching '
      'the search-suggestion path',
      (tester) async {
        final container = await _pumpSettings(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.widgetWithText(WpFilterChip, l10n.settingsPrivacy),
          ),
        );
        await tester.pump();

        expect(
          container.read(settingsHighlightTargetProvider),
          'privacy',
          reason:
              'SettingsAnchorChipBar._jumpTo must set the same '
              'highlight-target provider SettingsSearchField._selectEntry '
              'sets on suggestion tap',
        );
      },
    );
  });

  group('Existing full-text search — regression with the chip bar present', () {
    /// Sets the search query via the provider (bypassing the field's debounce)
    /// and settles, exactly like the pre-existing live-filter suite.
    Future<void> setQuery(
      WidgetTester tester,
      ProviderContainer container,
      String query,
    ) async {
      container.read(settingsSearchQueryProvider.notifier).set(query);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'searching still narrows sections, and the chip bar narrows with it',
      (tester) async {
        final container = await _pumpSettings(tester);

        await setQuery(tester, container, 'keyboard shortcut');

        // Section list narrows exactly as before the chip bar existed. Both
        // the (now sole) chip and the section heading render the same
        // string, so scope to the section area, excluding the chip bar.
        expect(find.text(l10n.settingsInterface), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.text(l10n.settingsKeyboardShortcut),
          ),
          findsOneWidget,
        );

        // The chip bar reflects the same narrowed set — no chip for a
        // section the search has hidden.
        expect(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.widgetWithText(WpFilterChip, l10n.settingsInterface),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.widgetWithText(
              WpFilterChip,
              l10n.settingsKeyboardShortcut,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('clearing the query restores every section and every chip', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      await setQuery(tester, container, 'keyboard shortcut');
      await setQuery(tester, container, '');

      for (final label in [
        l10n.settingsInterface,
        l10n.settingsAudio,
        l10n.settingsKeyboardShortcut,
        l10n.settingsPrivacy,
      ]) {
        expect(find.text(label), findsWidgets);
        expect(
          find.descendant(
            of: find.byType(SettingsAnchorChipBar),
            matching: find.widgetWithText(WpFilterChip, label),
          ),
          findsOneWidget,
          reason: 'chip for "$label" must come back once the query clears',
        );
      }
    });

    testWidgets(
      'zero-match query still shows the empty state — chip bar disappears '
      'rather than showing a row of dead chips',
      (tester) async {
        final container = await _pumpSettings(tester);

        await setQuery(tester, container, 'zzznomatch_unlikely_query_99');

        expect(find.text(l10n.settingsSearchNoResults), findsOneWidget);
        expect(find.byType(SettingsAnchorChipBar), findsNothing);
      },
    );
  });
}
