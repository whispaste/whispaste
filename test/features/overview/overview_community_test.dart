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
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_community.dart';
import 'package:whispaste/features/overview/overview_customize_menu.dart';
import 'package:whispaste/features/overview/overview_providers.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/social_stats/social_stats_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/support_fakes.dart';
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

/// A switch the test flips: stands for "the onboarding covers the block".
class _CoverNotifier extends Notifier<bool> {
  _CoverNotifier([this._initial = true]);

  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

const _direct = [
  DeployChannel.installer,
  DeployChannel.portable,
  DeployChannel.packageManaged,
];

void main() {
  group('rows per build (channel matrix)', () {
    test(
      'Mac App Store: GitHub, YouTube, support, store rating, ideas board',
      () {
        final rows = communityRows(
          channel: DeployChannel.store,
          platform: SupportPlatform.macos,
        );
        expect(rows.project, [
          CommunityEntry.github,
          CommunityEntry.youtube,
          CommunityEntry.support,
          CommunityEntry.rateStore,
          CommunityEntry.votepit,
        ]);
      },
    );

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
        CommunityEntry.votepit,
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

    test(
      'every build offers the ideas board, the preferred way to send an idea',
      () {
        for (final platform in SupportPlatform.values) {
          for (final channel in [DeployChannel.store, ..._direct]) {
            final rows = communityRows(channel: channel, platform: platform);
            expect(rows.project, contains(CommunityEntry.votepit));
          }
        }
      },
    );

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

    testWidgets('the idea pill on a store build opens the ideas board', (
      tester,
    ) async {
      final launcher = await pumpBlock(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      final pill = find.byKey(const ValueKey('overview-idea-pill'));
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      // Nothing opens before the user confirms the redirect.
      expect(launcher.launched, isEmpty);
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
      await tester.pumpAndSettle();
      expect(launcher.launched, [kVotepitBoardUrl]);
    });

    testWidgets('cancelling the redirect dialog opens nothing', (tester) async {
      final launcher = await pumpBlock(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      final pill = find.byKey(const ValueKey('overview-idea-pill'));
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
      await tester.pumpAndSettle();
      expect(launcher.launched, isEmpty);
      expect(
        find.byKey(const ValueKey('confirm-dialog-confirm')),
        findsNothing,
      );
    });

    testWidgets('the developer rows open the maintainer profiles', (
      tester,
    ) async {
      final launcher = await pumpBlock(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      // The newsletter group sits above these rows: scroll them in first.
      final x = find.byKey(const ValueKey('overview-community-x'));
      await tester.ensureVisible(x);
      await tester.tap(x);
      await tester.pumpAndSettle();
      final devGitHub = find.byKey(
        const ValueKey('overview-community-dev-github'),
      );
      await tester.ensureVisible(devGitHub);
      await tester.tap(devGitHub);
      await tester.pumpAndSettle();
      expect(launcher.launched, [
        kMaintainerXUrl,
        'https://github.com/silvio-l',
      ]);
    });

    testWidgets('each community link is named exactly once (#1498)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBlock(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      for (final id in [
        'overview-community-x',
        'overview-community-dev-github',
        'overview-community-github',
      ]) {
        final node = tester.getSemantics(find.byKey(ValueKey(id)));
        expect(node.label, isNotEmpty, reason: id);
        expect(node.flagsCollection.isLink, isTrue, reason: id);
        // No second node repeats the name, and the name is not doubled.
        var children = 0;
        node.visitChildren((_) {
          children++;
          return true;
        });
        expect(children, 0, reason: id);
        final lines = node.label.split('\n');
        expect(
          lines.toSet().length,
          lines.length,
          reason: '$id: ${node.label}',
        );
      }
      handle.dispose();
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

    testWidgets('store builds show support, the ideas board and the rating', (
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
      expect(find.byKey(const ValueKey('overview-idea-pill')), findsOneWidget);
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

  group('live numbers are asked for only when the block is shown', () {
    final covered = NotifierProvider<_CoverNotifier, bool>(_CoverNotifier.new);

    Future<FakeSocialStatsNotifier> pumpWith(
      WidgetTester tester, {
      required bool coveredAtStart,
    }) async {
      final fake = FakeSocialStatsNotifier();
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(
            body: SingleChildScrollView(child: OverviewCommunity()),
          ),
          overrides: [
            deployChannelProvider.overrideWithValue(DeployChannel.portable),
            supportPlatformProvider.overrideWithValue(SupportPlatform.linux),
            socialStatsProvider.overrideWith(() => fake),
            onboardingSurfaceActiveProvider.overrideWith(
              (ref) => ref.watch(covered),
            ),
            covered.overrideWith(() => _CoverNotifier(coveredAtStart)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('no request while the onboarding covers the block', (
      tester,
    ) async {
      final fake = await pumpWith(tester, coveredAtStart: true);
      expect(fake.refreshes, 0);
    });

    testWidgets('one request when the onboarding goes away', (tester) async {
      final fake = await pumpWith(tester, coveredAtStart: true);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewCommunity)),
      );
      container.read(covered.notifier).set(false);
      await tester.pumpAndSettle();
      expect(fake.refreshes, 1);
    });

    testWidgets('an uncovered block asks once at its first frame', (
      tester,
    ) async {
      final fake = await pumpWith(tester, coveredAtStart: false);
      expect(fake.refreshes, 1);
    });

    testWidgets('no request while the window is hidden, one when it returns', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final fake = await pumpWith(tester, coveredAtStart: false);
      expect(fake.refreshes, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fake.refreshes, 1);
    });
  });
}
