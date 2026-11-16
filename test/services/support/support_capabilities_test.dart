/// Channel matrix for the support asks (decisions S1, S9 and S10; the matrix table in the codex strategy).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';

void main() {
  group('Windows direct builds lead with the store purchase (S1)', () {
    for (final channel in [DeployChannel.installer, DeployChannel.portable]) {
      test(
        '$channel: store upsell first, then GitHub Sponsors, Ko-fi, PayPal',
        () {
          final asks = supportCapabilities(channel, SupportPlatform.windows);

          expect(asks.first, SupportAsk.storePurchaseUpsell);
          expect(
            asks.indexOf(SupportAsk.githubSponsors),
            lessThan(asks.indexOf(SupportAsk.kofi)),
          );
          expect(
            asks.indexOf(SupportAsk.kofi),
            lessThan(asks.indexOf(SupportAsk.paypal)),
          );
          expect(asks, isNot(contains(SupportAsk.nativeTip)));
        },
      );
    }
  });

  test(
    'Windows package-managed (Scoop) reverses the order: sponsoring first',
    () {
      final asks = supportCapabilities(
        DeployChannel.packageManaged,
        SupportPlatform.windows,
      );

      expect(asks.first, SupportAsk.githubSponsors);
      expect(
        asks.indexOf(SupportAsk.githubSponsors),
        lessThan(asks.indexOf(SupportAsk.storePurchaseUpsell)),
      );
    },
  );

  group('Windows Store build', () {
    test(
      'native tip first, external support without digital rewards (#1036)',
      () {
        final asks = supportCapabilities(
          DeployChannel.store,
          SupportPlatform.windows,
        );

        expect(asks.first, SupportAsk.nativeTip);
        expect(asks, contains(SupportAsk.githubSponsors));
        expect(asks, contains(SupportAsk.kofi));
        expect(asks, contains(SupportAsk.paypal));
        expect(asks, isNot(contains(SupportAsk.storePurchaseUpsell)));
      },
    );
  });

  group('Windows external payment routes (#1036)', () {
    for (final channel in DeployChannel.values) {
      test('$channel offers PayPal and both configured coffee providers', () {
        final asks = supportCapabilities(channel, SupportPlatform.windows);
        expect(asks, contains(SupportAsk.paypal));
        expect(asks, contains(SupportAsk.kofi));
        expect(kBuyMeACoffeeUrl, isNotNull);
        expect(coffeeExternalLinks().map((link) => link.url), [
          kKofiUrl,
          kBuyMeACoffeeUrl,
        ]);
        expect(
          coffeeSupportTarget(channel, SupportPlatform.windows),
          channel == DeployChannel.store
              ? CoffeeSupportTarget.storePurchase
              : CoffeeSupportTarget.externalLinks,
        );
      });
    }
  });

  group('Mac App Store build (decision 2026-11-09, #1006)', () {
    test('native tip first, then sponsoring, Ko-fi and PayPal, then reach', () {
      expect(supportCapabilities(DeployChannel.store, SupportPlatform.macos), [
        SupportAsk.nativeTip,
        SupportAsk.githubSponsors,
        SupportAsk.kofi,
        SupportAsk.paypal,
        SupportAsk.rate,
        SupportAsk.star,
        SupportAsk.share,
      ]);
    });
  });

  group('macOS direct builds', () {
    test(
      'portable: store purchase first, then sponsoring, PayPal included',
      () {
        final asks = supportCapabilities(
          DeployChannel.portable,
          SupportPlatform.macos,
        );

        expect(asks.first, SupportAsk.storePurchaseUpsell);
        expect(asks, contains(SupportAsk.paypal));
        expect(asks, isNot(contains(SupportAsk.nativeTip)));
      },
    );

    test('Homebrew (package-managed): sponsoring first, store second', () {
      final asks = supportCapabilities(
        DeployChannel.packageManaged,
        SupportPlatform.macos,
      );

      expect(asks.first, SupportAsk.githubSponsors);
      expect(
        asks.indexOf(SupportAsk.githubSponsors),
        lessThan(asks.indexOf(SupportAsk.storePurchaseUpsell)),
      );
    });
  });

  group('Linux gets sponsoring and reach only', () {
    for (final channel in [
      DeployChannel.portable,
      DeployChannel.packageManaged,
    ]) {
      test('$channel: sponsoring first, never a store ask', () {
        final asks = supportCapabilities(channel, SupportPlatform.linux);

        expect(asks.first, SupportAsk.githubSponsors);
        expect(asks, isNot(contains(SupportAsk.storePurchaseUpsell)));
        expect(asks, isNot(contains(SupportAsk.nativeTip)));
        expect(asks, isNot(contains(SupportAsk.rate)));
      });
    }
  });

  group('unknown channel and platform combinations fail closed', () {
    for (final (channel, platform) in [
      (DeployChannel.store, SupportPlatform.linux),
      (DeployChannel.installer, SupportPlatform.linux),
      (DeployChannel.installer, SupportPlatform.macos),
    ]) {
      test('$channel on $platform offers reach only', () {
        expect(supportCapabilities(channel, platform), [
          SupportAsk.star,
          SupportAsk.share,
        ]);
      });
    }
  });

  group('complete payment priority matrix (S1, #1035)', () {
    const external = [
      SupportAsk.githubSponsors,
      SupportAsk.kofi,
      SupportAsk.paypal,
    ];
    for (final platform in SupportPlatform.values) {
      for (final channel in DeployChannel.values) {
        test('$platform / $channel preserves the complete provider order', () {
          final expected = switch ((platform, channel)) {
            (SupportPlatform.macos, DeployChannel.store) => [
              SupportAsk.nativeTip,
              ...external,
            ],
            (SupportPlatform.windows, DeployChannel.store) => [
              SupportAsk.nativeTip,
              ...external,
            ],
            (SupportPlatform.windows, DeployChannel.installer) ||
            (SupportPlatform.windows, DeployChannel.portable) ||
            (
              SupportPlatform.macos,
              DeployChannel.portable,
            ) => [SupportAsk.storePurchaseUpsell, ...external],
            (SupportPlatform.windows, DeployChannel.packageManaged) ||
            (
              SupportPlatform.macos,
              DeployChannel.packageManaged,
            ) => [...external, SupportAsk.storePurchaseUpsell],
            (SupportPlatform.linux, DeployChannel.portable) ||
            (SupportPlatform.linux, DeployChannel.packageManaged) => external,
            _ => <SupportAsk>[],
          };
          expect(
            supportCapabilities(channel, platform).where(
              (ask) => ![
                SupportAsk.rate,
                SupportAsk.star,
                SupportAsk.share,
              ].contains(ask),
            ),
            expected,
          );
        });
      }
    }
  });

  test('no list repeats an ask, and every list is non-empty', () {
    for (final channel in DeployChannel.values) {
      for (final platform in SupportPlatform.values) {
        final asks = supportCapabilities(channel, platform);
        expect(asks, isNotEmpty);
        expect(asks.toSet(), hasLength(asks.length));
      }
    }
  });

  group('"Other amount" ways follow the channel matrix (#1034)', () {
    const all = [
      OtherAmountWay.githubSponsors,
      OtherAmountWay.kofi,
      OtherAmountWay.buyMeACoffee,
      OtherAmountWay.paypal,
    ];

    test('direct, package-managed and both stores offer every way', () {
      for (final (channel, platform) in [
        (DeployChannel.installer, SupportPlatform.windows),
        (DeployChannel.portable, SupportPlatform.windows),
        (DeployChannel.packageManaged, SupportPlatform.windows),
        (DeployChannel.store, SupportPlatform.windows),
        (DeployChannel.portable, SupportPlatform.macos),
        (DeployChannel.packageManaged, SupportPlatform.macos),
        (DeployChannel.store, SupportPlatform.macos),
        (DeployChannel.portable, SupportPlatform.linux),
        (DeployChannel.packageManaged, SupportPlatform.linux),
      ]) {
        expect(
          otherAmountWays(channel, platform).toSet(),
          all.toSet(),
          reason: '$channel on $platform',
        );
      }
    });

    test('follows the matrix order, Sponsors before Ko-fi before PayPal', () {
      expect(
        otherAmountWays(DeployChannel.store, SupportPlatform.windows),
        all,
      );
    });

    test('Buy Me a Coffee is dropped when its link is not configured', () {
      expect(
        otherAmountWays(
          DeployChannel.store,
          SupportPlatform.macos,
          buyMeACoffeeUrl: null,
        ),
        isNot(contains(OtherAmountWay.buyMeACoffee)),
      );
    });

    test('reach-only rows get no payment way (fail closed)', () {
      expect(
        otherAmountWays(DeployChannel.installer, SupportPlatform.linux),
        isEmpty,
      );
      expect(
        otherAmountWays(DeployChannel.store, SupportPlatform.linux),
        isEmpty,
      );
    });

    test('every way has an https address', () {
      for (final way in OtherAmountWay.values) {
        expect(otherAmountUrl(way), startsWith('https://'));
      }
    });
  });
}
