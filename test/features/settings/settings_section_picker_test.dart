/// Widget tests for the settings section picker (concept proposal 5, which
/// replaced the Ticket 16 anchor-chip wall).
///
/// AC coverage:
///   - choosing a section scrolls it into view and highlights it, through the
///     same providers the search suggestions drive
///   - the trigger follows the scroll spy, so it shows the section on screen
///   - search narrows the entries and zero matches hides the picker
///   - at 800x640 the picker shares a row with search and the first real
///     setting sits inside the first viewport
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
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/features/settings/widgets/settings_section_picker.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../../fixtures/test_helpers.dart';

const _pickerKey = Key('settings-section-picker');

Key _itemKey(String sectionKey) => Key('settings-section-picker-$sectionKey');

/// Pumps [SettingsPage] at a fixed window size and returns the
/// [ProviderContainer] for tests that need to drive providers directly.
Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Locale locale = const Locale('en'),
}) async {
  // makeTestable only sizes MediaQuery; the surface decides real constraints.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(const SettingsPage(), locale: locale, size: size),
  );
  await tester.pumpAndSettle();
  final element = tester.element(find.byType(SettingsPage));
  return ProviderScope.containerOf(element);
}

/// The section key the trigger currently displays.
String? _shownSection(WidgetTester tester) =>
    tester.widget<WpDropdown<String>>(find.byKey(_pickerKey)).value;

/// Opens the picker menu and waits for it to settle.
Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(_pickerKey));
  await tester.pumpAndSettle();
}

/// Scrolls the open menu until [sectionKey]'s entry is built. The menu is a
/// lazily built list, so entries past the bottom edge do not exist yet.
Future<void> _revealItem(WidgetTester tester, String sectionKey) async {
  await tester.scrollUntilVisible(
    find.byKey(_itemKey(sectionKey)),
    48,
    scrollable: find.byType(Scrollable).last,
  );
  // scrollUntilVisible only needs a sliver of the entry; a tap needs all of it.
  await tester.ensureVisible(find.byKey(_itemKey(sectionKey)));
  await tester.pumpAndSettle();
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('SettingsSectionPicker', () {
    testWidgets(
      'offers one entry per visible section, without the hidden one',
      (tester) async {
        await _pumpSettings(tester);

        // OnboardingReviewSection is filtered out until onboarding is complete,
        // so the picker must not offer it either.
        expect(find.byType(OnboardingReviewSection), findsNothing);
        await _openPicker(tester);

        for (final key in ['interface', 'stt', 'hotkey']) {
          expect(find.byKey(_itemKey(key)), findsOneWidget, reason: key);
        }
        await _revealItem(tester, 'privacy');
        expect(find.byKey(_itemKey('privacy')), findsOneWidget);
        expect(find.byKey(_itemKey('onboardingReview')), findsNothing);
      },
    );

    testWidgets('choosing a section scrolls it into view and highlights it', (
      tester,
    ) async {
      final container = await _pumpSettings(tester);

      final privacy = find.byType(PrivacySection);
      final before = tester.getTopLeft(privacy).dy;
      expect(
        before,
        greaterThan(800),
        reason:
            'Privacy must start below the fold for the jump to mean anything',
      );

      await _openPicker(tester);
      await _revealItem(tester, 'privacy');
      await tester.tap(find.byKey(_itemKey('privacy')));
      await tester.pumpAndSettle();

      // Privacy sits at the bottom of the page, so the scroll clamps and its
      // top edge may stay below the fold. Being on screen is the contract.
      expect(
        tester
            .getRect(privacy)
            .overlaps(const Offset(0, 0) & const Size(1280, 800)),
        isTrue,
      );
      expect(container.read(settingsHighlightTargetProvider), 'privacy');
    });

    testWidgets('scroll spy moves the trigger when the user scrolls by hand', (
      tester,
    ) async {
      await _pumpSettings(tester);
      expect(_shownSection(tester), 'interface');

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();

      expect(
        _shownSection(tester),
        isNot('interface'),
        reason: 'the trigger must follow the section on screen, not a tap',
      );
    });

    testWidgets(
      'search narrows the entries and zero matches hides the picker',
      (tester) async {
        final container = await _pumpSettings(tester);

        container
            .read(settingsSearchQueryProvider.notifier)
            .set('keyboard shortcut');
        await tester.pumpAndSettle();

        expect(find.byKey(_pickerKey), findsOneWidget);
        await _openPicker(tester);
        expect(find.byKey(_itemKey('hotkey')), findsOneWidget);
        expect(find.byKey(_itemKey('interface')), findsNothing);
        await tester.tapAt(const Offset(5, 5)); // close the menu
        await tester.pumpAndSettle();

        container
            .read(settingsSearchQueryProvider.notifier)
            .set('zzznomatch_unlikely_query_99');
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsSearchNoResults), findsOneWidget);
        expect(find.byKey(_pickerKey), findsNothing);
      },
    );

    testWidgets('clearing the query restores every entry', (tester) async {
      final container = await _pumpSettings(tester);

      container.read(settingsSearchQueryProvider.notifier).set('zzznomatch');
      await tester.pumpAndSettle();
      container.read(settingsSearchQueryProvider.notifier).set('');
      await tester.pumpAndSettle();

      expect(find.byKey(_pickerKey), findsOneWidget);
      await _openPicker(tester);
      expect(find.byKey(_itemKey('interface')), findsOneWidget);
      await _revealItem(tester, 'privacy');
      expect(find.byKey(_itemKey('privacy')), findsOneWidget);
    });

    testWidgets('at 800x640 the picker shares the search row and the first '
        'setting is visible without scrolling', (tester) async {
      await _pumpSettings(tester, size: const Size(800, 640));

      final searchCenter = tester.getCenter(find.byType(SettingsSearchField));
      final pickerCenter = tester.getCenter(find.byKey(_pickerKey));
      expect(pickerCenter.dy, closeTo(searchCenter.dy, 2));
      expect(tester.getSize(find.byKey(_pickerKey)).width, 232);

      final firstRow = tester.getRect(find.byType(SettingRow).first);
      expect(firstRow.bottom, lessThanOrEqualTo(640));
    });
  });

  group('SettingsSearchSectionRow', () {
    testWidgets('stacks search and picker at a large text scale', (
      tester,
    ) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(1280, 800),
                textScaler: const TextScaler.linear(1.5),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                child: SettingsSearchSectionRow(
                  searchFocusNode: focusNode,
                  sectionKeys: const ['interface', 'stt'],
                  locale: 'en',
                  activeSectionKey: 'interface',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchTop = tester.getTopLeft(find.byType(SettingsSearchField)).dy;
      final pickerTop = tester.getTopLeft(find.byKey(_pickerKey)).dy;
      expect(pickerTop, greaterThan(searchTop));
    });
  });
}
