import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

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

    testWidgets(
      'on a Sparkle platform, tapping while readyToInstall ALSO opens the '
      'native dialog — NOT the Linux/portable installUpdate() flow, which '
      'expects a local downloaded-file path the native path never sets',
      (tester) async {
        platformSupportsSparkle = () => true;
        var foregroundCheckCalled = false;
        checkForUpdatesFn = ({inBackground}) async {
          foregroundCheckCalled = true;
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
        container.read(updateProvider.notifier).markReadyToInstallNative();
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.updateInstall));
        await tester.pump();

        expect(
          foregroundCheckCalled,
          isTrue,
          reason:
              'presentSparkleUpdate must run for readyToInstall on a '
              'Sparkle platform too',
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

  // Every interactive element on this page used to be a bare GestureDetector
  // under a `Semantics(label: X)` that duplicated the text the subtree already
  // rendered. Two defects in one node: pointer-only operation on a page of an
  // app that promises you never have to reach for the mouse, and a doubled
  // announcement. Both are pinned here.
  group('About affordances are keyboard-reachable and named once', () {
    // "Star on GitHub" is a WpButton since the page's four hand-built button
    // dialects were folded into it. The name it announces is therefore the
    // button's own label rather than a hand-written Semantics label — which is
    // the same guarantee this test always made, one layer lower.
    testWidgets('the GitHub support action is a focusable button, named once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(const AboutPage(), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // Walking up from the caption lands on the button's own node: a
        // WpButton merges its label into one node, so there is nothing in
        // between to pick up by accident.
        final node = tester.getSemantics(find.text(l10n.aboutStarOnGitHub));
        expect(
          find.ancestor(
            of: find.text(l10n.aboutStarOnGitHub),
            matching: find.byType(WpButton),
          ),
          findsOneWidget,
        );

        // Exactly the rendered caption — not "Star on GitHub\nStar on GitHub".
        expect(node.label, l10n.aboutStarOnGitHub);
        expect(
          node.getSemanticsData().flagsCollection.isButton,
          isTrue,
          reason:
              'the four hand-built affordances announced as links; as '
              'WpButtons they announce as buttons',
        );
        // …and it can be reached and triggered without a pointer.
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.focus),
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('every tappable affordance owns a real focus node', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const AboutPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Every tap on this page has to arrive through an InkWell, because that
      // is what carries the FocusNode. A tappable GestureDetector *without* an
      // InkWell above it is the old, pointer-only shape. (InkWell builds its
      // own GestureDetector internally, hence the ancestor check rather than a
      // blanket ban.)
      final strays = find
          .byType(GestureDetector)
          .evaluate()
          .where((e) => (e.widget as GestureDetector).onTap != null)
          .where(
            (e) => find
                .ancestor(
                  of: find.byWidget(e.widget),
                  matching: find.byType(InkWell),
                )
                .evaluate()
                .isEmpty,
          );
      expect(
        strays,
        isEmpty,
        reason:
            'A tappable GestureDetector outside an InkWell is unreachable by '
            'keyboard — wrap it the way _AboutTapTarget does.',
      );
    });
  });
}
