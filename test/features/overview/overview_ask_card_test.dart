import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_ask_card.dart';
import 'package:whispaste/features/overview/overview_providers.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/services/review_prompt_service.dart';
import 'package:whispaste/services/prompt_display_arbiter.dart';

import '../../fixtures/test_helpers.dart';

/// Hand-off test: each action of the milestone and rate/share card records
/// its choice where the next visit reads it. Actions are found by testID.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester,
    OverviewAskCard card,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: OverviewAskCardView()),
        overrides: [overviewAskCardProvider.overrideWithValue(card)],
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(OverviewAskCardView)),
    );
  }

  Future<SharedPreferences> tapAndRead(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
    return SharedPreferences.getInstance();
  }

  testWidgets('"Später" snoozes, the close button stops asking', (
    tester,
  ) async {
    await pump(tester, const OverviewRateShareCard());
    var prefs = await tapAndRead(tester, 'overview-rate-later');
    expect(prefs.getInt('review_prompt_last_snooze'), isNotNull);
    expect(prefs.getBool('review_prompt_permanently_dismissed'), isNull);

    prefs = await tapAndRead(tester, 'overview-rate-never');
    expect(prefs.getBool('review_prompt_permanently_dismissed'), isTrue);
  });

  testWidgets('sharing copies the website link and counts as asked', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester, const OverviewRateShareCard());
    final prefs = await tapAndRead(tester, 'overview-share');
    expect(copied, startsWith('https://whispaste.de'));
    expect(prefs.getInt('review_prompt_last_shown'), isNotNull);
  });

  testWidgets('closing a milestone remembers it and the day', (tester) async {
    final container = await pump(tester, const OverviewMilestoneCard(100));
    await tester.tap(find.bySemanticsIdentifier('overview-milestone-close'));
    await tester.pumpAndSettle();
    final prefs = container.read(overviewPrefsProvider);
    expect(prefs.milestonesSeen, {100});
    expect(prefs.askCardDay, isNotNull);
  });

  group('support card (#1094)', () {
    const card = OverviewSupportCard(recurring: false);

    testWidgets('showing it counts one round and claims the session', (
      tester,
    ) async {
      final container = await pump(tester, card);
      expect(find.bySemanticsIdentifier('overview-support'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('support_prompt_impression_count'), 1);
      expect(
        container
            .read(promptDisplayArbiterProvider)
            .tryClaim(PromptOwner.review, close: () {}),
        isFalse,
      );
    });

    testWidgets('"Unterstützen" opens Help › Support and pauses', (
      tester,
    ) async {
      final container = await pump(tester, card);
      final prefs = await tapAndRead(tester, 'overview-support-open');
      expect(container.read(activePageProvider), 'help');
      expect(
        container.read(helpTargetProvider),
        const HelpTarget(tab: HelpTab.support),
      );
      expect(prefs.getInt('support_prompt_snooze_ms'), isNotNull);
      expect(prefs.getBool('support_prompt_never'), isNull);
      expect(container.read(overviewPrefsProvider).askCardDay, isNotNull);
    });

    testWidgets('"Später" pauses, it never stops asking for good', (
      tester,
    ) async {
      await pump(tester, card);
      final prefs = await tapAndRead(tester, 'overview-support-later');
      expect(prefs.getInt('support_prompt_snooze_ms'), isNotNull);
      expect(prefs.getBool('support_prompt_never'), isNull);
    });

    testWidgets('"Nicht mehr fragen" stops asking for good', (tester) async {
      await pump(tester, card);
      final prefs = await tapAndRead(tester, 'overview-support-never');
      expect(prefs.getBool('support_prompt_never'), isTrue);
      expect(prefs.getInt('support_prompt_snooze_ms'), isNull);
    });

    testWidgets('a hotkey hides it without answering', (tester) async {
      final container = await pump(tester, card);
      container.read(promptDisplayArbiterProvider).closeOpenPrompt();
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('overview-support'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('support_prompt_snooze_ms'), isNull);
      expect(prefs.getBool('support_prompt_never'), isNull);
    });
  });

  for (final surface in ReviewSurface.values) {
    testWidgets('$surface is refused after support claims the session', (
      tester,
    ) async {
      final arbiter = PromptDisplayArbiter();
      expect(arbiter.tryClaim(PromptOwner.support, close: () {}), isTrue);
      var requests = 0;
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: OverviewAskCardView()),
          overrides: [
            overviewAskCardProvider.overrideWithValue(
              const OverviewRateShareCard(),
            ),
            promptDisplayArbiterProvider.overrideWithValue(arbiter),
            reviewSurfaceProvider.overrideWithValue(surface),
            systemReviewRequesterProvider.overrideWithValue(() async {
              requests++;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('overview-rate'), findsNothing);
      expect(requests, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('review_prompt_shown_count'), isNull);
      expect(prefs.getInt('review_prompt_last_snooze'), isNull);
    });

    testWidgets('$surface blocks support even after navigating away', (
      tester,
    ) async {
      final arbiter = PromptDisplayArbiter();
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: OverviewAskCardView()),
          overrides: [
            overviewAskCardProvider.overrideWithValue(
              const OverviewRateShareCard(),
            ),
            promptDisplayArbiterProvider.overrideWithValue(arbiter),
            reviewSurfaceProvider.overrideWithValue(surface),
            systemReviewRequesterProvider.overrideWithValue(() async {}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(arbiter.tryClaim(PromptOwner.support, close: () {}), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      arbiter.closeOpenPrompt();
      expect(tester.takeException(), isNull);
      expect(arbiter.tryClaim(PromptOwner.support, close: () {}), isFalse);
    });
  }

  testWidgets('hotkey cancels the review card without snoozing', (
    tester,
  ) async {
    final container = await pump(tester, const OverviewRateShareCard());
    container.read(promptDisplayArbiterProvider).closeOpenPrompt();
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('overview-rate'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('review_prompt_last_snooze'), isNull);
    expect(prefs.getInt('review_prompt_shown_count'), isNull);
  });

  group('build-dependent rating surface', () {
    test('only the Mac App Store build uses the system dialog', () {
      expect(reviewSurfaceFor(isMasBuild: true), ReviewSurface.systemDialog);
      expect(reviewSurfaceFor(isMasBuild: false), ReviewSurface.ownCard);
    });

    test('the Mac App Store review link is an apps.apple.com https link', () {
      expect(kMacAppStoreReviewUrl, startsWith('https://apps.apple.com/'));
      expect(kMacAppStoreReviewUrl, isNot(contains('macappstore://')));
    });

    testWidgets('system dialog: no own card, dialog requested once', (
      tester,
    ) async {
      var requests = 0;
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: OverviewAskCardView()),
          overrides: [
            overviewAskCardProvider.overrideWithValue(
              const OverviewRateShareCard(),
            ),
            reviewSurfaceProvider.overrideWithValue(ReviewSurface.systemDialog),
            systemReviewRequesterProvider.overrideWithValue(() async {
              requests++;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('overview-rate'), findsNothing);
      expect(requests, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('review_prompt_shown_count'), 1);
    });

    testWidgets('own card: shown, system dialog never requested', (
      tester,
    ) async {
      var requests = 0;
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: OverviewAskCardView()),
          overrides: [
            overviewAskCardProvider.overrideWithValue(
              const OverviewRateShareCard(),
            ),
            reviewSurfaceProvider.overrideWithValue(ReviewSurface.ownCard),
            systemReviewRequesterProvider.overrideWithValue(() async {
              requests++;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('overview-rate'), findsOneWidget);
      expect(requests, 0);
    });
  });
}
