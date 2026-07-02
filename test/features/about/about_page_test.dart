import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_service.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('AboutPage update-check routing (PRD Bug 2 regression)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      setFeedUrlFn = (_) async {};
      setIntervalFn = (_) async {};
      checkForUpdatesFn = ({inBackground}) async {};
    });

    tearDown(() {
      platformSupportsSparkle = () => false;
      setFeedUrlFn = (_) async {};
      setIntervalFn = (_) async {};
      checkForUpdatesFn = ({inBackground}) async {};
    });

    testWidgets(
      'on a Sparkle platform, "Check Now" opens the native foreground check '
      '(presentSparkleUpdate) — before the fix it always fell through to the '
      'channel-blind GitHub-API checkForUpdate(), which never finds a beta',
      (tester) async {
        platformSupportsSparkle = () => true;
        var foregroundCheckCalled = false;
        bool? capturedInBackground;
        checkForUpdatesFn = ({inBackground}) async {
          foregroundCheckCalled = true;
          capturedInBackground = inBackground;
        };

        await tester.pumpWidget(
          makeTestable(
            const AboutPage(),
            locale: const Locale('en'),
            overrides: [
              deployChannelProvider.overrideWith(
                (ref) => DeployChannel.installer,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AboutPage)),
        );

        await tester.tap(find.text(l10n.updateCheckNow));
        await tester.pump();

        expect(
          foregroundCheckCalled,
          isTrue,
          reason: 'presentSparkleUpdate must have run',
        );
        expect(capturedInBackground, isFalse, reason: 'foreground, not silent');
        expect(
          container.read(updateProvider).phase,
          UpdatePhase.idle,
          reason:
              'the channel-blind checkForUpdate() (GitHub-API path) must '
              'NOT have run on a Sparkle platform',
        );
      },
    );
  });

  group('AboutPage review & support', () {
    testWidgets('shows always-on "Rate & support WhisPaste" entry plus its '
        'existing GitHub-Stern link — AC2', (tester) async {
      await tester.pumpWidget(
        makeTestable(const AboutPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // The Support section sits near the bottom of the scroll view.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();

      // Always-on entry is present.
      expect(find.text(l10n.reviewSupportEntry), findsOneWidget);
      // The existing GitHub-Stern link is preserved.
      expect(find.text(l10n.aboutStarOnGitHub), findsOneWidget);
    });
  });
}
