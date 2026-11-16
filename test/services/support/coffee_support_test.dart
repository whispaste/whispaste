/// Coffee support button: the channel matrix of the coffee route, the store
/// guard (a store build never reaches an external link), the Buy Me a Coffee
/// switch and the store-availability provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';

/// Store bridge that only answers the availability question.
class _FakeBridge implements SupportStoreBridge {
  const _FakeBridge({required this.available});

  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<SupportProduct>> loadProducts(List<String> productIds) async =>
      const [];

  @override
  Future<SupportPurchaseStatus> purchase(String productId) async =>
      SupportPurchaseStatus.unavailable;

  @override
  Future<bool> hasVerifiedAppPurchase() async => false;

  @override
  Future<bool> hasVerifiedSupportPurchase() async => false;
}

void main() {
  group('coffeeSupportTarget per channel and platform', () {
    test('Mac App Store build gets the native purchase, no link', () {
      expect(
        coffeeSupportTarget(DeployChannel.store, SupportPlatform.macos),
        CoffeeSupportTarget.storePurchase,
      );
    });

    test('Microsoft Store build gets the native purchase, no link', () {
      expect(
        coffeeSupportTarget(DeployChannel.store, SupportPlatform.windows),
        CoffeeSupportTarget.storePurchase,
      );
    });

    test('Linux has no store build, so the coffee button stays hidden', () {
      expect(
        coffeeSupportTarget(DeployChannel.store, SupportPlatform.linux),
        CoffeeSupportTarget.hidden,
      );
    });

    test('Windows direct builds open the external coffee pages', () {
      for (final channel in [
        DeployChannel.installer,
        DeployChannel.portable,
        DeployChannel.packageManaged,
      ]) {
        expect(
          coffeeSupportTarget(channel, SupportPlatform.windows),
          CoffeeSupportTarget.externalLinks,
          reason: '$channel on Windows',
        );
      }
    });

    test('Linux portable and package builds open the external pages', () {
      expect(
        coffeeSupportTarget(DeployChannel.portable, SupportPlatform.linux),
        CoffeeSupportTarget.externalLinks,
      );
      expect(
        coffeeSupportTarget(
          DeployChannel.packageManaged,
          SupportPlatform.linux,
        ),
        CoffeeSupportTarget.externalLinks,
      );
    });

    test('Mac direct installer keeps the matrix: no payment route, so no '
        'coffee button', () {
      expect(
        coffeeSupportTarget(DeployChannel.installer, SupportPlatform.macos),
        CoffeeSupportTarget.hidden,
      );
    });

    test(
      'a store build never resolves to an external link, on any platform',
      () {
        for (final platform in SupportPlatform.values) {
          final target = coffeeSupportTarget(DeployChannel.store, platform);
          expect(
            target,
            isNot(CoffeeSupportTarget.externalLinks),
            reason: 'store build on $platform',
          );
        }
      },
    );

    test('external links appear only in non-store builds', () {
      for (final channel in DeployChannel.values) {
        for (final platform in SupportPlatform.values) {
          final target = coffeeSupportTarget(channel, platform);
          if (target == CoffeeSupportTarget.externalLinks) {
            expect(
              channel,
              isNot(DeployChannel.store),
              reason: '$channel on $platform',
            );
          }
        }
      }
    });
  });

  group('external coffee pages', () {
    test('the Buy Me a Coffee constant is the maintainer page', () {
      expect(kBuyMeACoffeeUrl, 'https://buymeacoffee.com/silvio.lindstedt');
    });

    test('direct builds list Ko-fi first, then Buy Me a Coffee', () {
      final links = coffeeExternalLinks();
      expect(links.map((l) => l.url), [kKofiUrl, kBuyMeACoffeeUrl]);
      expect(links.first.idSuffix, isEmpty);
      expect(links.last.idSuffix, '-buy-me-a-coffee');
    });

    test('without a Buy Me a Coffee URL only Ko-fi is listed', () {
      final links = coffeeExternalLinks(buyMeACoffeeUrl: null);
      expect(links.map((l) => l.url), [kKofiUrl]);
      expect(links.single.idSuffix, isEmpty);
    });

    test('every external coffee page is https', () {
      for (final link in coffeeExternalLinks(
        buyMeACoffeeUrl: 'https://buymeacoffee.com/example',
      )) {
        expect(Uri.parse(link.url).scheme, 'https');
      }
    });
  });

  group('coffeeSupportTargetProvider', () {
    test(
      'store build hides the button while the store cannot sell it',
      () async {
        final container = ProviderContainer(
          overrides: [
            deployChannelProvider.overrideWithValue(DeployChannel.store),
            supportPlatformProvider.overrideWithValue(SupportPlatform.macos),
            supportStoreBridgeProvider.overrideWithValue(
              const _FakeBridge(available: false),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(supportStoreTipAvailableProvider.future);
        expect(
          container.read(coffeeSupportTargetProvider),
          CoffeeSupportTarget.hidden,
        );
      },
    );

    test(
      'store build shows the native purchase once the store can sell it',
      () async {
        final container = ProviderContainer(
          overrides: [
            deployChannelProvider.overrideWithValue(DeployChannel.store),
            supportPlatformProvider.overrideWithValue(SupportPlatform.windows),
            supportStoreBridgeProvider.overrideWithValue(
              const _FakeBridge(available: true),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(supportStoreTipAvailableProvider.future);
        expect(
          container.read(coffeeSupportTargetProvider),
          CoffeeSupportTarget.storePurchase,
        );
      },
    );

    test('direct build never waits on the store and shows Ko-fi', () async {
      final container = ProviderContainer(
        overrides: [
          deployChannelProvider.overrideWithValue(DeployChannel.installer),
          supportPlatformProvider.overrideWithValue(SupportPlatform.windows),
          supportStoreBridgeProvider.overrideWithValue(
            const _FakeBridge(available: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(coffeeSupportTargetProvider),
        CoffeeSupportTarget.externalLinks,
      );
    });
  });
}
