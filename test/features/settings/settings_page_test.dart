import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/sections/overlay_button_section.dart';
import 'package:whispaste/features/settings/sections/updates_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_scroll_affordance.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/floating_button/floating_button_support.dart';
import 'package:whispaste/services/floating_button/floating_button_support_provider.dart';
import 'package:whispaste/widgets/page_shell.dart';

import '../../fixtures/test_helpers.dart';
import 'settings_area_fixture.dart';
import '../../fixtures/record_device_listing_stub.dart';

late L10n l10n;

/// Finds [text] inside the scroll content only, excluding the sticky header
/// (search field + section picker). A section's own heading and the picker's
/// trigger can render the identical localized label, so a bare
/// `find.text(...)` anywhere on the page may match both.
Finder _sectionText(String text) => find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.text(text),
);

void main() {
  stubRecordDeviceListing();
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('SettingsPage', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows Audio section', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.recording)],
        ),
      );
      await tester.pumpAndSettle();
      expect(_sectionText(l10n.settingsAudio), findsOneWidget);
      expect(_sectionText(l10n.settingsKeyboardShortcut), findsNothing);
    });

    testWidgets('shows Keyboard Shortcut section in Keyboard shortcuts', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.shortcuts)],
        ),
      );
      await tester.pumpAndSettle();
      expect(_sectionText(l10n.shortcutsGroupDictate), findsOneWidget);
    });

    testWidgets('shows Interface section in General', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(_sectionText(l10n.settingsInterface), findsOneWidget);
    });

    testWidgets('shows key setting labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.recording)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsMicrophone), findsOneWidget);
      expect(_sectionText(l10n.settingsHoldToRecord), findsNothing);
    });

    testWidgets('shows Hold to Record in Keyboard shortcuts', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.shortcuts)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsHoldToRecord), findsOneWidget);
    });

    testWidgets('settings page is scrollable', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets(
      'page frame comes from WpPageShell, with the search field sticky '
      'above the scroll area',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(const SettingsPage(), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(WpPageShell),
          findsOneWidget,
          reason:
              'Settings used to hand-roll the shell — padding drifted apart '
              'from every other page as soon as the default changed',
        );
        expect(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(SettingsSearchField),
          ),
          findsNothing,
          reason: 'the search field must stay put while sections scroll',
        );
      },
    );

    testWidgets('shows new Sound & Feedback section', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.recording)],
        ),
      );
      await tester.pumpAndSettle();
      // Scroll down to find the section
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(_sectionText(l10n.settingsSoundFeedback), findsOneWidget);
    });

    testWidgets('shows Recording Overlay section in Appearance', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.appearance)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      expect(_sectionText(l10n.settingsOverlayFloatingButton), findsOneWidget);
    });

    testWidgets('shows reset action in Advanced', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          locale: const Locale('en'),
          overrides: [settingsAreaAt(SettingsArea.advanced)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsResetToDefaults), findsOneWidget);
    });

    testWidgets(
      'the rate entry moved to the Help page, not listed here — UX-015',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [settingsAreaAt(SettingsArea.advanced)],
          ),
        );
        await tester.pumpAndSettle();
        // Scroll to the bottom of the advanced area, where the rate entry used to be.
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        // The entry lives on the Help page now (see about_page_test).
        expect(_sectionText(l10n.reviewSupportEntry), findsNothing);
      },
    );

    group('Floating Button section — platform gating', () {
      testWidgets('is present on Linux, so the Linux button is reachable '
          '(PAR-010)', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              settingsAreaAt(SettingsArea.appearance),
              floatingButtonSupportProvider.overrideWith(
                (ref) async => FloatingButtonSupport.full,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonSection), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('is present on Windows', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [settingsAreaAt(SettingsArea.appearance)],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonSection), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('Updates section — deploy-channel gating', () {
      // WP-23g: store builds keep the section with its rows disabled and the
      // reason shown (AR-19). Only package-managed installs drop it.
      testWidgets('stays on the store deploy channel, with disabled rows', (
        tester,
      ) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith((ref) => DeployChannel.store),
              settingsAreaAt(SettingsArea.general),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpdatesSection), findsOneWidget);
      });

      testWidgets('is absent on package-managed installs', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.packageManaged,
              ),
              settingsAreaAt(SettingsArea.general),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpdatesSection), findsNothing);
      });

      testWidgets('is present on the portable deploy channel', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.portable,
              ),
              settingsAreaAt(SettingsArea.general),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(UpdatesSection), findsOneWidget);
      });
    });
  });

  group('SettingsPage scroll gutter (UX-035)', () {
    // Narrow enough for the collapsed layout, where the content column is the
    // only scrolling area.
    Future<void> pumpAt420(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingsPage(),
          size: const Size(420, 900),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
    }

    // Scrollbar box and its widest (hovered) thumb, as the theme paints it.
    Rect scrollbarRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(SettingsScrollAffordance),
            matching: find.byType(Scrollbar),
          )
          .first,
    );

    double hoveredThumb(WidgetTester tester) => ScrollbarTheme.of(
      tester.element(find.byType(Scrollbar).first),
    ).thickness!.resolve({WidgetState.hovered})!;

    Rect firstCard(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('settings-group-card')).first);

    testWidgets('card right edge stays clear of the scrollbar at 420 px', (
      tester,
    ) async {
      await pumpAt420(tester, const Locale('en'));

      expect(
        firstCard(tester).right,
        lessThanOrEqualTo(scrollbarRect(tester).right - hoveredThumb(tester)),
      );
    });

    testWidgets('gutter mirrors in RTL: card left edge clears the scrollbar', (
      tester,
    ) async {
      await pumpAt420(tester, const Locale('he'));

      expect(
        firstCard(tester).left,
        greaterThanOrEqualTo(scrollbarRect(tester).left + hoveredThumb(tester)),
      );
    });
  });
}
