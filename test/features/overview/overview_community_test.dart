/// Logic and hand-over points of the "Mitmachen" block: which rows a build
/// shows (the channel matrix), the address each row hands to the opener, the
/// close field and the menu entry switching the same stored block, and the
/// default (shown). Layout and wording are judged by eye, not tested.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_community.dart';
import 'package:whispaste/features/overview/overview_customize_menu.dart';
import 'package:whispaste/features/overview/overview_providers.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/test_helpers.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

const _direct = [
  DeployChannel.installer,
  DeployChannel.portable,
  DeployChannel.packageManaged,
];

void main() {
  group('rows per build (channel matrix)', () {
    test('Mac App Store: GitHub, YouTube, support, store rating; no ideas', () {
      final rows = communityRows(
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      expect(rows.project, [
        CommunityEntry.github,
        CommunityEntry.youtube,
        CommunityEntry.support,
        CommunityEntry.rateStore,
      ]);
    });

    test('Microsoft Store: the same rows, rating on Windows', () {
      final rows = communityRows(
        channel: DeployChannel.store,
        platform: SupportPlatform.windows,
      );
      expect(rows.project, [
        CommunityEntry.github,
        CommunityEntry.youtube,
        CommunityEntry.support,
        CommunityEntry.rateStore,
      ]);
    });

    for (final channel in _direct) {
      for (final platform in SupportPlatform.values) {
        test('direct $channel on $platform: support and ideas, no rating', () {
          final rows = communityRows(channel: channel, platform: platform);
          expect(rows.project, [
            CommunityEntry.github,
            CommunityEntry.youtube,
            CommunityEntry.support,
            CommunityEntry.votepit,
          ]);
        });
      }
    }

    test('store builds never get the ideas board', () {
      for (final platform in SupportPlatform.values) {
        final rows = communityRows(
          channel: DeployChannel.store,
          platform: platform,
        );
        expect(rows.project, isNot(contains(CommunityEntry.votepit)));
      }
    });

    test(
      'the support row shows exactly when supportCapabilities is not empty',
      () {
        for (final channel in DeployChannel.values) {
          for (final platform in SupportPlatform.values) {
            final asks = supportCapabilities(channel, platform);
            final rows = communityRows(channel: channel, platform: platform);
            expect(
              rows.project.contains(CommunityEntry.support),
              asks.isNotEmpty,
              reason: '$channel on $platform',
            );
          }
        }
      },
    );

    test('the developer group is shown on every build and kept apart', () {
      for (final channel in DeployChannel.values) {
        for (final platform in SupportPlatform.values) {
          final rows = communityRows(channel: channel, platform: platform);
          expect(rows.developer, [
            CommunityEntry.devX,
            CommunityEntry.devGitHub,
          ]);
          expect(rows.project, isNot(contains(CommunityEntry.devX)));
          expect(rows.developer, isNot(contains(CommunityEntry.github)));
        }
      }
    });
  });

  group('address per row', () {
    test('each row hands the opener its fixed address', () {
      expect(
        communityUrl(CommunityEntry.github, SupportPlatform.linux),
        kGitHubRepoUrl,
      );
      expect(
        communityUrl(CommunityEntry.youtube, SupportPlatform.linux),
        'https://www.youtube.com/@whispaste',
      );
      expect(
        communityUrl(CommunityEntry.votepit, SupportPlatform.windows),
        kVotepitBoardUrl,
      );
      expect(
        communityUrl(CommunityEntry.devX, SupportPlatform.macos),
        kMaintainerXUrl,
      );
      expect(
        communityUrl(CommunityEntry.devGitHub, SupportPlatform.macos),
        'https://github.com/silvio-l',
      );
    });

    test('the rating goes to the store of its platform', () {
      expect(
        communityUrl(CommunityEntry.rateStore, SupportPlatform.macos),
        kMacAppStoreReviewUrl,
      );
      expect(
        communityUrl(CommunityEntry.rateStore, SupportPlatform.windows),
        kWindowsStoreReviewUrl,
      );
    });

    test('support has no web address: it opens the in-app page', () {
      expect(
        communityUrl(CommunityEntry.support, SupportPlatform.linux),
        isNull,
      );
    });
  });

  group('stored switch', () {
    test('the block is shown by default', () {
      expect(
        const OverviewPrefs().hiddenBlocks,
        isNot(contains(OverviewBlock.community)),
      );
      expect(
        overviewHiddenBlocksFromStored('recent,dictation'),
        isNot(contains(OverviewBlock.community)),
      );
    });

    test('the stored id round-trips', () {
      final stored = overviewHiddenBlocksToStored({OverviewBlock.community});
      expect(stored, 'community');
      expect(overviewHiddenBlocksFromStored(stored), {OverviewBlock.community});
    });
  });

  group('hand-over of the rows', () {
    Future<_FakeUrlLauncher> pumpBlock(
      WidgetTester tester, {
      required DeployChannel channel,
      required SupportPlatform platform,
    }) async {
      final launcher = _FakeUrlLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(
            body: SingleChildScrollView(child: OverviewCommunity()),
          ),
          overrides: [
            deployChannelProvider.overrideWithValue(channel),
            supportPlatformProvider.overrideWithValue(platform),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return launcher;
    }

    testWidgets('the GitHub row opens the repository', (tester) async {
      final launcher = await pumpBlock(
        tester,
        channel: DeployChannel.portable,
        platform: SupportPlatform.linux,
      );
      await tester.tap(find.byKey(const ValueKey('overview-community-github')));
      await tester.pumpAndSettle();
      expect(launcher.launched, [kGitHubRepoUrl]);
    });

    testWidgets('the developer rows open the maintainer profiles', (
      tester,
    ) async {
      final launcher = await pumpBlock(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      await tester.tap(find.byKey(const ValueKey('overview-community-x')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('overview-community-dev-github')),
      );
      await tester.pumpAndSettle();
      expect(launcher.launched, [
        kMaintainerXUrl,
        'https://github.com/silvio-l',
      ]);
    });

    testWidgets('the support row opens the support page, not a web address', (
      tester,
    ) async {
      final launcher = await pumpBlock(
        tester,
        channel: DeployChannel.installer,
        platform: SupportPlatform.windows,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewCommunity)),
      );
      await tester.tap(
        find.byKey(const ValueKey('overview-community-support')),
      );
      await tester.pumpAndSettle();
      expect(container.read(activePageProvider), 'help');
      expect(
        container.read(helpTargetProvider),
        const HelpTarget(tab: HelpTab.support),
      );
      expect(launcher.launched, isEmpty);
    });

    testWidgets('store builds show support too, and no ideas board', (
      tester,
    ) async {
      await pumpBlock(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.windows,
      );
      expect(
        find.byKey(const ValueKey('overview-community-support')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('overview-community-votepit')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('overview-community-rate-store')),
        findsOneWidget,
      );
    });
  });

  group('close field and menu entry', () {
    testWidgets('the close field hides the block in the stored state', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(
            body: SingleChildScrollView(child: OverviewCommunity()),
          ),
          overrides: [
            deployChannelProvider.overrideWithValue(DeployChannel.portable),
            supportPlatformProvider.overrideWithValue(SupportPlatform.linux),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewCommunity)),
      );
      await tester.tap(find.byKey(const ValueKey('overview-community-hide')));
      await tester.pumpAndSettle();
      expect(container.read(overviewPrefsProvider).hiddenBlocks, {
        OverviewBlock.community,
      });
    });

    testWidgets('the menu entry switches the same block on and off', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const Scaffold(body: OverviewCustomizeMenu())),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewCustomizeMenu)),
      );

      Future<void> choose() async {
        await tester.tap(find.byKey(const ValueKey('overview-customize')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is CheckboxMenuButton &&
                w.key == const ValueKey('overview-customize-community'),
          ),
        );
        await tester.pumpAndSettle();
      }

      await choose();
      expect(container.read(overviewPrefsProvider).hiddenBlocks, {
        OverviewBlock.community,
      });
      await choose();
      expect(
        container.read(overviewPrefsProvider).hiddenBlocks,
        isNot(contains(OverviewBlock.community)),
      );
    });
  });
}
