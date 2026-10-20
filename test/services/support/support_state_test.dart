/// Persisted support status (decisions S2, S4, S5 and S7): verified and
/// self-declared supporters, chip visibility, the retired store thank-you
/// flag, and the purchase path.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';
import 'package:whispaste/services/telemetry_service.dart';

/// Bridge double. Flags answer the verification queries; [purchaseResult]
/// answers the purchase call.
class _FakeBridge implements SupportStoreBridge {
  _FakeBridge({
    this.appPurchase = false,
    this.supportPurchase = false,
    this.purchaseResult = SupportPurchaseStatus.succeeded,
    this.products = const [],
  });

  final bool appPurchase;
  final bool supportPurchase;
  final SupportPurchaseStatus purchaseResult;
  final List<SupportProduct> products;
  final purchased = <String>[];
  final catalogueRequests = <List<String>>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<SupportProduct>> loadProducts(List<String> productIds) async {
    catalogueRequests.add(productIds);
    return products;
  }

  @override
  Future<SupportPurchaseStatus> purchase(String productId) async {
    purchased.add(productId);
    return purchaseResult;
  }

  @override
  Future<bool> hasVerifiedAppPurchase() async => appPurchase;

  @override
  Future<bool> hasVerifiedSupportPurchase() async => supportPurchase;
}

TelemetryService _silentTelemetry() => TelemetryService(
  client: MockClient((_) async => http.Response('', 200)),
  endpointUrl: '',
  siteId: 0,
  consentGranted: false,
  dntActive: false,
);

Future<ProviderContainer> _container({
  required Map<String, Object> prefs,
  required DeployChannel channel,
  SupportStoreBridge bridge = const UnavailableSupportStoreBridge(),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(
    overrides: [
      deployChannelProvider.overrideWithValue(channel),
      supportStoreBridgeProvider.overrideWithValue(bridge),
      telemetryProvider.overrideWithValue(_silentTelemetry()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(supportStatusProvider.notifier).loaded;
  return container;
}

void main() {
  group('verified supporter (S4)', () {
    test('an app purchase verifies and is stored', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
        bridge: _FakeBridge(appPurchase: true),
      );

      final status = container.read(supportStatusProvider);
      expect(status.verifiedSupporter, isTrue);
      expect(status.showsBadge, isTrue);
      expect(status.suppressesPrompts, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('support_verified_supporter'), isTrue);
    });

    test('a verified support add-on purchase counts as verified', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
        bridge: _FakeBridge(supportPurchase: true),
      );

      expect(container.read(supportStatusProvider).verifiedSupporter, isTrue);
    });

    test('a stored verification survives an offline start where the bridge '
        'reports nothing', () async {
      final container = await _container(
        prefs: const {'support_verified_supporter': true},
        channel: DeployChannel.store,
      );

      expect(container.read(supportStatusProvider).verifiedSupporter, isTrue);
    });

    test('a bare store channel is not proof of payment (no badge)', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
      );

      final status = container.read(supportStatusProvider);
      expect(status.verifiedSupporter, isFalse);
      expect(status.showsBadge, isFalse);
    });
  });

  group('self-declared supporter (S2)', () {
    test('declaring on a direct build hides the chip and stops prompts, but '
        'earns no badge', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.portable,
      );

      await container
          .read(supportStatusProvider.notifier)
          .declareSelfSupporter();

      final status = container.read(supportStatusProvider);
      expect(status.selfDeclaredSupporter, isTrue);
      expect(status.chipHidden, isTrue);
      expect(status.suppressesPrompts, isTrue);
      expect(status.showsBadge, isFalse);
    });

    test('the store channel refuses the declaration', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
      );

      await container
          .read(supportStatusProvider.notifier)
          .declareSelfSupporter();

      expect(
        container.read(supportStatusProvider).selfDeclaredSupporter,
        isFalse,
      );
    });
  });

  group('chip visibility', () {
    test(
      'any user can hide the chip, and the choice survives a restart',
      () async {
        final container = await _container(
          prefs: const {},
          channel: DeployChannel.portable,
        );

        await container.read(supportStatusProvider.notifier).hideChip();
        expect(container.read(supportStatusProvider).showsSponsorChip, isFalse);

        final restarted = await _container(
          prefs: const {'support_chip_hidden': true},
          channel: DeployChannel.portable,
        );
        expect(restarted.read(supportStatusProvider).showsSponsorChip, isFalse);
        expect(
          restarted.read(supportStatusProvider).suppressesPrompts,
          isFalse,
        );
      },
    );

    test('a verified supporter can hide the chip, and restoring shows it '
        'again', () async {
      final container = await _container(
        prefs: const {'support_verified_supporter': true},
        channel: DeployChannel.store,
      );
      final notifier = container.read(supportStatusProvider.notifier);

      await notifier.hideChip();
      expect(container.read(supportStatusProvider).showsSponsorChip, isFalse);

      await notifier.restoreChip();
      expect(container.read(supportStatusProvider).showsSponsorChip, isTrue);
    });

    test('restoring the chip does not lift the prompt suppression of a '
        'self-declared supporter', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.portable,
      );
      final notifier = container.read(supportStatusProvider.notifier);
      await notifier.declareSelfSupporter();

      await notifier.restoreChip();

      final status = container.read(supportStatusProvider);
      expect(status.showsSponsorChip, isTrue);
      expect(status.suppressesPrompts, isTrue);
    });
  });

  group('store thank-you migration (S5)', () {
    test('the retired modal flag is dropped and grants no badge', () async {
      final container = await _container(
        prefs: const {'store_thank_you_shown': true},
        channel: DeployChannel.store,
      );

      expect(container.read(supportStatusProvider).verifiedSupporter, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('store_thank_you_shown'), isFalse);
    });

    test('the passive line is exposed for store installs only', () async {
      final store = await _container(
        prefs: const {},
        channel: DeployChannel.store,
      );
      final portable = await _container(
        prefs: const {},
        channel: DeployChannel.portable,
      );

      expect(store.read(supportStoreThankYouLineProvider), isTrue);
      expect(portable.read(supportStoreThankYouLineProvider), isFalse);
    });
  });

  group('native tip products', () {
    Future<ProviderContainer> containerWith(
      List<SupportAsk> asks,
      _FakeBridge bridge,
    ) async {
      final container = ProviderContainer(
        overrides: [
          supportCapabilitiesProvider.overrideWithValue(asks),
          supportStoreBridgeProvider.overrideWithValue(bridge),
          telemetryProvider.overrideWithValue(_silentTelemetry()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the catalogue is requested for the shared product ids', () async {
      SharedPreferences.setMockInitialValues(const {});
      final bridge = _FakeBridge(
        products: const [
          SupportProduct(
            productId: 'whispaste.support.once.1',
            title: 'Small tip',
            formattedPrice: '1,99 €',
          ),
        ],
      );
      final container = await containerWith([SupportAsk.nativeTip], bridge);

      final products = await container.read(supportTipProductsProvider.future);

      expect(bridge.catalogueRequests, [kSupportProductIds]);
      expect(products.single.productId, 'whispaste.support.once.1');
      expect(products.single.title, 'Small tip');
    });

    test('no store call is made where the native tip is not offered', () async {
      SharedPreferences.setMockInitialValues(const {});
      final bridge = _FakeBridge();
      final container = await containerWith([SupportAsk.kofi], bridge);

      final products = await container.read(supportTipProductsProvider.future);

      expect(products, isEmpty);
      expect(bridge.catalogueRequests, isEmpty);
    });
  });

  group('purchase', () {
    test('an unknown product id is refused without a store call', () async {
      final bridge = _FakeBridge();
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
        bridge: bridge,
      );

      final result = await container
          .read(supportStatusProvider.notifier)
          .purchase('whispaste.support.once.9');

      expect(result, SupportPurchaseStatus.unavailable);
      expect(bridge.purchased, isEmpty);
    });

    test('without an id the preselected tip is purchased', () async {
      final bridge = _FakeBridge();
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
        bridge: bridge,
      );

      await container.read(supportStatusProvider.notifier).purchase();

      expect(bridge.purchased, [kDefaultSupportProductId]);
    });

    test(
      'a succeeded purchase persists the verified supporter status',
      () async {
        final bridge = _FakeBridge();
        final container = await _container(
          prefs: const {},
          channel: DeployChannel.store,
          bridge: bridge,
        );

        final result = await container
            .read(supportStatusProvider.notifier)
            .purchase('whispaste.support.once.2');

        expect(result, SupportPurchaseStatus.succeeded);
        expect(bridge.purchased, ['whispaste.support.once.2']);
        expect(container.read(supportStatusProvider).verifiedSupporter, isTrue);
      },
    );

    test('a cancelled purchase leaves the status unchanged', () async {
      final container = await _container(
        prefs: const {},
        channel: DeployChannel.store,
        bridge: _FakeBridge(purchaseResult: SupportPurchaseStatus.cancelled),
      );

      final result = await container
          .read(supportStatusProvider.notifier)
          .purchase('whispaste.support.once.1');

      expect(result, SupportPurchaseStatus.cancelled);
      expect(container.read(supportStatusProvider).verifiedSupporter, isFalse);
    });
  });
}
