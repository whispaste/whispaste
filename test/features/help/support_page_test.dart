/// Widget tests for the support page, one group per channel variant.
///
/// The Mac App Store variant offers the same external channels as direct
/// builds (decision 2026-11-09, #1006); its test asserts that by key.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/help/support_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/social_stats/social_stats_logic.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';

import '../../fixtures/support_fakes.dart';
import '../../fixtures/test_helpers.dart';

const _externalKeys = [
  'support-sponsors-button',
  'support-kofi-button',
  'support-buy-me-a-coffee-button',
  'support-paypal-button',
  'support-share-x',
  'support-share-facebook',
  'support-share-whatsapp',
  'support-share-linkedin',
  'support-share-reddit',
  'support-share-telegram',
  'support-share-bluesky',
  'support-share-email',
  'support-star-button',
];

Future<FakeSupportStatusNotifier> _pump(
  WidgetTester tester, {
  required DeployChannel channel,
  required SupportPlatform platform,
  SupportStatus status = const SupportStatus(),
  SocialStatsView socialStats = const SocialStatsView(),
  bool buyMeACoffeeFirst = false,
}) async {
  final notifier = FakeSupportStatusNotifier(status);
  await tester.pumpWidget(
    makeTestable(
      const SupportPage(),
      locale: const Locale('en'),
      overrides: supportOverrides(
        channel: channel,
        platform: platform,
        status: notifier,
        socialStats: socialStats,
        buyMeACoffeeFirst: buyMeACoffeeFirst,
      ),
    ),
  );
  // The coffee order resolves asynchronously.
  await tester.pump();
  await tester.pump();
  return notifier;
}

Key _key(String id) => ValueKey(id);

/// Stored overview switches, already loaded; never reads the database.
class _FakeOverviewPrefs extends OverviewPrefsNotifier {
  _FakeOverviewPrefs(this.hidden);

  final Set<OverviewBlock> hidden;

  @override
  OverviewPrefs build() => OverviewPrefs(loaded: true, hiddenBlocks: hidden);

  @override
  Future<void> get ready async {}
}

/// Opens the page with "Mitmachen" hidden or shown and returns how often it
/// asked for the project numbers.
Future<int> _statsRefreshes(
  WidgetTester tester, {
  required bool communityHidden,
}) async {
  final stats = FakeSocialStatsNotifier();
  await tester.pumpWidget(
    makeTestable(
      const SupportPage(),
      locale: const Locale('en'),
      overrides: [
        ...supportOverrides(
          channel: DeployChannel.portable,
          platform: SupportPlatform.linux,
          status: FakeSupportStatusNotifier(const SupportStatus()),
          socialStatsNotifier: stats,
        ),
        overviewPrefsProvider.overrideWith(
          () => _FakeOverviewPrefs(
            communityHidden ? {OverviewBlock.community} : const {},
          ),
        ),
      ],
    ),
  );
  await tester.pump();
  await tester.pump();
  return stats.refreshes;
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('macOS direct build shows the Mac App Store card', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.macos,
    );

    expect(find.text(l10n.supportStoreTitleMac), findsOneWidget);
    expect(find.byKey(_key('support-store-cta')), findsOneWidget);
    expect(find.byKey(_key('support-sponsors-button')), findsOneWidget);
    expect(find.byKey(_key('support-native-tip-button')), findsNothing);
  });

  testWidgets('Linux build offers sponsoring only, no store card', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );

    expect(find.byKey(_key('support-store-card')), findsNothing);
    expect(find.byKey(_key('support-sponsors-button')), findsOneWidget);
    expect(find.byKey(_key('support-kofi-button')), findsOneWidget);
    expect(find.byKey(_key('support-buy-me-a-coffee-button')), findsOneWidget);
    expect(find.byKey(_key('support-paypal-button')), findsOneWidget);
    expect(find.byKey(_key('support-star-button')), findsOneWidget);
    expect(find.byKey(_key('support-self-declare-button')), findsOneWidget);
  });

  testWidgets('Windows Store build offers native tip and all external routes', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.windows,
    );

    expect(find.text(l10n.supportStoreThankYouLine), findsOneWidget);
    expect(find.byKey(_key('support-native-tip-button')), findsOneWidget);
    expect(find.byKey(_key('support-sponsors-button')), findsOneWidget);
    expect(find.byKey(_key('support-kofi-button')), findsOneWidget);
    expect(find.byKey(_key('support-buy-me-a-coffee-button')), findsOneWidget);
    expect(find.byKey(_key('support-paypal-button')), findsOneWidget);
    expect(find.byKey(_key('support-store-card')), findsNothing);
    expect(find.byKey(_key('support-self-declare-button')), findsNothing);
    expect(find.byKey(_key('support-rate-button')), findsOneWidget);
  });

  testWidgets(
    'Mac App Store build offers the native tip first, then every external channel',
    (tester) async {
      await _pump(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );

      expect(find.byKey(_key('support-native-tip-button')), findsOneWidget);
      expect(find.byKey(_key('support-share-link')), findsOneWidget);
      expect(find.byKey(_key('support-rate-button')), findsOneWidget);
      for (final id in _externalKeys) {
        expect(
          find.byKey(_key(id)),
          findsOneWidget,
          reason: '$id must exist in the MAS build',
        );
      }
      expect(find.byKey(_key('support-store-card')), findsNothing);
      expect(find.byKey(_key('support-self-declare-button')), findsNothing);
    },
  );

  testWidgets('dismissing the store card hides it and restore brings it back', (
    tester,
  ) async {
    final notifier = await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
    );

    await tester.tap(find.byKey(_key('support-store-offer-dismiss')));
    await tester.pump();
    expect(notifier.calls, contains('dismissStoreOffer'));
    expect(find.byKey(_key('support-store-card')), findsNothing);
    expect(find.byKey(_key('support-store-offer-restore')), findsOneWidget);

    await tester.tap(find.byKey(_key('support-store-offer-restore')));
    await tester.pump();
    expect(notifier.calls, contains('restoreStoreOffer'));
    expect(find.byKey(_key('support-store-card')), findsOneWidget);
  });

  testWidgets('supporter sees the thank-you line and the badge when verified', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.installer,
      platform: SupportPlatform.windows,
      status: const SupportStatus(verifiedSupporter: true),
    );

    expect(find.text(l10n.supportSupporterLine), findsOneWidget);
    expect(find.byKey(_key('support-supporter-badge')), findsOneWidget);
    expect(find.byKey(_key('support-self-declare-button')), findsNothing);
  });

  testWidgets('verified store buyer can still tip natively', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.store,
      platform: SupportPlatform.windows,
      status: const SupportStatus(verifiedSupporter: true),
    );

    expect(find.byKey(_key('support-supporter-badge')), findsOneWidget);
    expect(find.byKey(_key('support-native-card')), findsOneWidget);
    expect(find.byKey(_key('support-native-tip-button')), findsOneWidget);
  });

  testWidgets('self-declared supporter gets the line but no badge', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      status: const SupportStatus(selfDeclaredSupporter: true),
    );

    expect(find.text(l10n.supportSupporterLine), findsOneWidget);
    expect(find.byKey(_key('support-supporter-badge')), findsNothing);
  });

  testWidgets('before declaring: neutral hint and CTA, no confirmation', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );

    expect(find.text(l10n.supportSelfDeclareHint), findsOneWidget);
    expect(find.byKey(_key('support-self-declare-button')), findsOneWidget);
    expect(find.text(l10n.supportSelfDeclareNote), findsNothing);
  });

  testWidgets('after declaring: confirmation replaces the CTA', (tester) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      status: const SupportStatus(selfDeclaredSupporter: true),
    );

    expect(find.text(l10n.supportSelfDeclareNote), findsOneWidget);
    expect(find.text(l10n.supportSelfDeclareHint), findsNothing);
    expect(find.byKey(_key('support-self-declare-button')), findsNothing);
  });

  testWidgets('the confirmation sits in a live region with its testID (#618)', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      status: const SupportStatus(selfDeclaredSupporter: true),
    );

    final region = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.identifier == 'support-self-declare-confirmation',
    );
    expect(region, findsOneWidget);
    expect(tester.widget<Semantics>(region).properties.liveRegion, isTrue);
    expect(
      find.descendant(
        of: region,
        matching: find.text(l10n.supportSelfDeclareNote),
      ),
      findsOneWidget,
    );
  });

  group('provider tiles open their page (#395)', () {
    late List<String> opened;
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      opened = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            final url = (call.arguments as Map)['url'] as String?;
            if (call.method == 'launch' && url != null) opened.add(url);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null);
    });

    for (final platform in SupportPlatform.values) {
      for (final channel in DeployChannel.values) {
        testWidgets(
          '$platform / $channel renders and opens providers in matrix order',
          (tester) async {
            await _pump(tester, channel: channel, platform: platform);
            final expected = <(String, String?)>[
              for (final ask in supportCapabilities(channel, platform))
                ...switch (ask) {
                  SupportAsk.storePurchaseUpsell => [
                    (
                      'support-store-cta',
                      platform == SupportPlatform.macos
                          ? kMacAppStoreListingUrl
                          : kMicrosoftStoreListingUrl,
                    ),
                  ],
                  SupportAsk.nativeTip => [('support-native-tip-button', null)],
                  SupportAsk.githubSponsors => [
                    ('support-sponsors-button', kGitHubSponsorsUrl),
                  ],
                  SupportAsk.kofi => [
                    ('support-kofi-button', kKofiUrl),
                    ('support-buy-me-a-coffee-button', kBuyMeACoffeeUrl),
                  ],
                  SupportAsk.paypal => [('support-paypal-button', kPayPalUrl)],
                  _ => <(String, String?)>[],
                },
            ];
            const providerIds = {
              'support-store-cta',
              'support-native-tip-button',
              'support-sponsors-button',
              'support-kofi-button',
              'support-buy-me-a-coffee-button',
              'support-paypal-button',
            };
            final rendered = find
                .byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      providerIds.contains(
                        (widget.key! as ValueKey<String>).value,
                      ),
                )
                .evaluate()
                .map(
                  (element) => (element.widget.key! as ValueKey<String>).value,
                );
            expect(rendered, expected.map((entry) => entry.$1));
            final expectedUrls = <String>[];
            for (final (id, url) in expected) {
              final button = find.byKey(_key(id));
              await tester.ensureVisible(button);
              await tester.tap(button);
              await tester.pumpAndSettle();
              if (url == null) {
                expect(
                  find.byKey(_key('support-purchase-sheet')),
                  findsOneWidget,
                );
                await tester.tap(find.byKey(_key('support-purchase-close')));
                await tester.pumpAndSettle();
              } else {
                expectedUrls.add(url);
              }
              expect(opened, expectedUrls);
            }
          },
        );
      }
    }

    for (final (id, url) in [
      ('support-paypal-button', kPayPalUrl),
      ('support-kofi-button', kKofiUrl),
      ('support-buy-me-a-coffee-button', kBuyMeACoffeeUrl),
      ('support-sponsors-button', kGitHubSponsorsUrl),
      ('support-star-button', kGitHubRepoUrl),
    ]) {
      testWidgets('$id opens $url', (tester) async {
        await _pump(
          tester,
          channel: DeployChannel.portable,
          platform: SupportPlatform.linux,
        );
        await tester.ensureVisible(find.byKey(_key(id)));
        await tester.tap(find.byKey(_key(id)));
        await tester.pumpAndSettle();
        expect(opened, [url]);
      });
    }
  });

  group('rate row hand-over', () {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');

    Future<List<String>> mockLauncher({String? failing}) async {
      SharedPreferences.setMockInitialValues({});
      final opened = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            final url = (call.arguments as Map)['url'] as String?;
            if (call.method == 'canLaunch') return url != failing;
            if (call.method == 'launch' && url != null) opened.add(url);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, null),
      );
      return opened;
    }

    Future<void> tapRate(WidgetTester tester) async {
      final rate = find.byKey(_key('support-rate-button'));
      await tester.ensureVisible(rate);
      await tester.tap(rate);
      await tester.pumpAndSettle();
    }

    testWidgets('the Mac App Store build opens its own review page', (
      tester,
    ) async {
      final opened = await mockLauncher();
      await _pump(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      await tapRate(tester);
      expect(opened, [kMacAppStoreReviewUrl]);
    });

    testWidgets('a store page that cannot open falls back to GitHub', (
      tester,
    ) async {
      final opened = await mockLauncher(failing: kWindowsStoreReviewUrl);
      await _pump(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.windows,
      );
      await tapRate(tester);
      expect(opened, [kGitHubRepoUrl]);
    });

    testWidgets('the Mac App Store build never falls back to GitHub', (
      tester,
    ) async {
      final opened = await mockLauncher(failing: kMacAppStoreReviewUrl);
      await _pump(
        tester,
        channel: DeployChannel.store,
        platform: SupportPlatform.macos,
      );
      await tapRate(tester);
      expect(opened, isEmpty);
    });
  });

  testWidgets('the coffee tiles follow the drawn order', (tester) async {
    Iterable<String> order() => find
        .byWidgetPredicate(
          (w) =>
              w.key == _key('support-kofi-button') ||
              w.key == _key('support-buy-me-a-coffee-button'),
        )
        .evaluate()
        .map((e) => (e.widget.key! as ValueKey<String>).value);

    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );
    expect(order(), ['support-kofi-button', 'support-buy-me-a-coffee-button']);

    await tester.pumpWidget(const SizedBox());
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      buyMeACoffeeFirst: true,
    );
    expect(order(), ['support-buy-me-a-coffee-button', 'support-kofi-button']);
  });

  // UX-082/UX-083: the coffee slots stand from the first frame on, so neither
  // the order nor the tiles around them move once the draw has loaded.
  testWidgets('the coffee slots are held from the first frame while the '
      'order loads', (tester) async {
    final draw = Completer<bool>();
    await tester.pumpWidget(
      makeTestable(
        const SupportPage(),
        locale: const Locale('en'),
        overrides: supportOverrides(
          channel: DeployChannel.portable,
          platform: SupportPlatform.linux,
          status: FakeSupportStatusNotifier(const SupportStatus()),
          pendingCoffeeOrder: draw.future,
        ),
      ),
    );

    // First frame: both slots are held, but no order is shown yet.
    const pending = [
      'support-coffee-pending',
      'support-coffee-pending-buy-me-a-coffee',
    ];
    for (final id in pending) {
      expect(find.byKey(_key(id)), findsOneWidget);
    }
    expect(find.byKey(_key('support-kofi-button')), findsNothing);
    expect(find.byKey(_key('support-buy-me-a-coffee-button')), findsNothing);

    draw.complete(true);
    await tester.pump();
    await tester.pump();

    for (final id in pending) {
      expect(find.byKey(_key(id)), findsNothing);
    }
    expect(find.byKey(_key('support-buy-me-a-coffee-button')), findsOneWidget);
    expect(find.byKey(_key('support-kofi-button')), findsOneWidget);
  });

  testWidgets('a known star count is shown, an unknown one is not', (
    tester,
  ) async {
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
      socialStats: const SocialStatsView(stars: 66),
    );
    expect(find.textContaining(l10n.supportStarCount(66)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(
      tester,
      channel: DeployChannel.portable,
      platform: SupportPlatform.linux,
    );
    expect(find.textContaining(l10n.supportStarCount(66)), findsNothing);
  });

  testWidgets('hidden "Mitmachen" stops the project numbers request (#735)', (
    tester,
  ) async {
    expect(await _statsRefreshes(tester, communityHidden: true), 0);
    await tester.pumpWidget(const SizedBox());
    expect(await _statsRefreshes(tester, communityHidden: false), 1);
  });

  group('supportRateUrl', () {
    test('macOS uses the Mac App Store review link, never a Windows URL', () {
      final url = supportRateUrl(SupportPlatform.macos);
      expect(url, kMacAppStoreReviewUrl);
      expect(url, isNot(contains('ms-windows-store')));
    });

    test('Windows uses the Microsoft Store review link', () {
      expect(supportRateUrl(SupportPlatform.windows), kWindowsStoreReviewUrl);
    });

    test('Linux, without a store, rates on GitHub', () {
      expect(supportRateUrl(SupportPlatform.linux), kGitHubRepoUrl);
    });
  });
}
