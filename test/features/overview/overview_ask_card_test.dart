import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_ask_card.dart';
import 'package:whispaste/features/overview/overview_providers.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/prompt_display_arbiter.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/support_fakes.dart';
import '../../fixtures/test_helpers.dart';

/// Hand-off test: each action of the milestone and support card records its
/// choice where the next visit reads it. The rating ask is a dialog since
/// #2185 (test/features/review/review_ask_dialog_test.dart). Actions are found by testID.
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

    Future<void> pumpOn(
      WidgetTester tester,
      DeployChannel channel,
      SupportPlatform platform, {
      bool storeOfferDismissed = false,
    }) async {
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: OverviewAskCardView()),
          locale: const Locale('en'),
          overrides: [
            overviewAskCardProvider.overrideWithValue(card),
            ...supportOverrides(
              channel: channel,
              platform: platform,
              status: FakeSupportStatusNotifier(
                SupportStatus(storeOfferDismissed: storeOfferDismissed),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Windows direct builds name the store reasons (#1941)', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await pumpOn(tester, DeployChannel.installer, SupportPlatform.windows);
      expect(find.text(l10n.overviewSupportBodyStoreWindows), findsOneWidget);
    });

    testWidgets('macOS portable builds name the App Store reasons', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await pumpOn(tester, DeployChannel.portable, SupportPlatform.macos);
      expect(find.text(l10n.overviewSupportBodyStoreMac), findsOneWidget);
    });

    testWidgets('Linux keeps the general text', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await pumpOn(tester, DeployChannel.portable, SupportPlatform.linux);
      expect(find.text(l10n.overviewSupportBody), findsOneWidget);
    });

    testWidgets('a hidden store offer keeps the general text', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await pumpOn(
        tester,
        DeployChannel.installer,
        SupportPlatform.windows,
        storeOfferDismissed: true,
      );
      expect(find.text(l10n.overviewSupportBody), findsOneWidget);
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
}
