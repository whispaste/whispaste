/// Channel matrix for the support asks (`internal-notes`,
/// decisions S1, S9 and S10; the matrix table in the codex strategy).
library;

import 'package:flutter_test/flutter_test.dart';
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
      'native one-time tip first, GitHub Sponsors for monthly/free amounts',
      () {
        final asks = supportCapabilities(
          DeployChannel.store,
          SupportPlatform.windows,
        );

        expect(asks.first, SupportAsk.nativeTip);
        expect(asks, contains(SupportAsk.githubSponsors));
        expect(asks, isNot(contains(SupportAsk.kofi)));
        expect(asks, isNot(contains(SupportAsk.paypal)));
        expect(asks, isNot(contains(SupportAsk.storePurchaseUpsell)));
      },
    );
  });

  group('Mac App Store build (guideline 3.1.1)', () {
    test('exactly native tip, rate, star and share, with no payment link', () {
      expect(supportCapabilities(DeployChannel.store, SupportPlatform.macos), [
        SupportAsk.nativeTip,
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

  test('no list repeats an ask, and every list is non-empty', () {
    for (final channel in DeployChannel.values) {
      for (final platform in SupportPlatform.values) {
        final asks = supportCapabilities(channel, platform);
        expect(asks, isNotEmpty);
        expect(asks.toSet(), hasLength(asks.length));
      }
    }
  });
}
