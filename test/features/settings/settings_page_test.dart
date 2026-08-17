import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/overlay_button_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/widgets/page_shell.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

void main() {
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
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsAudio), findsOneWidget);
    });

    testWidgets('shows Keyboard Shortcut section', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsKeyboardShortcut), findsOneWidget);
    });

    testWidgets('shows Interface section', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsInterface), findsOneWidget);
    });

    testWidgets('shows key setting labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsMicrophone), findsOneWidget);
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
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      // Scroll down to find the section
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsSoundFeedback), findsOneWidget);
    });

    testWidgets('shows Recording Overlay section', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsOverlayFloatingButton), findsOneWidget);
    });

    testWidgets('shows reset action', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsResetToDefaults), findsOneWidget);
    });

    testWidgets('shows always-on "Rate & support WhisPaste" entry — AC1', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      // The entry lives at the end of the settings list — scroll it into view.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      // Always-on entry is visible and not gated by the review-prompt cooldown.
      expect(find.text(l10n.reviewSupportEntry), findsOneWidget);
    });

    group('Floating Button section — platform gating', () {
      testWidgets(
        'is entirely absent on Linux, not just an empty card '
        '(sectionCard wraps even a SizedBox.shrink() child in a padded, '
        'bordered container, so hiding only the inner content still leaves '
        'a bare outline)',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;

          await tester.pumpWidget(
            makeTestable(const SettingsPage(), locale: const Locale('en')),
          );
          await tester.pumpAndSettle();

          expect(find.byType(FloatingButtonSection), findsNothing);

          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets('is present on Windows', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        await tester.pumpWidget(
          makeTestable(const SettingsPage(), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FloatingButtonSection), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      });
    });
  });
}
