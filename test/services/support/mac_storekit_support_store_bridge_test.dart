import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/support/mac_storekit_support_store_bridge.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kMacStoreKitChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockNative(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('purchase status parsing', () {
    test('maps every native status name to its enum value', () {
      for (final status in SupportPurchaseStatus.values) {
        expect(parseStoreKitPurchaseStatus(status.name), status);
      }
    });

    test('null and unknown names fall back to serverError', () {
      expect(
        parseStoreKitPurchaseStatus(null),
        SupportPurchaseStatus.serverError,
      );
      expect(
        parseStoreKitPurchaseStatus('SKError42'),
        SupportPurchaseStatus.serverError,
      );
    });
  });

  group('product parsing', () {
    test('returns products in requested order and skips unknown ids', () {
      final products = parseStoreKitProducts(
        [
          {'id': 'b', 'displayName': 'B', 'displayPrice': '4,99 €'},
          {'id': 'a', 'displayName': 'A', 'displayPrice': '1,99 €'},
        ],
        ['a', 'missing', 'b'],
      );

      expect(products.map((p) => p.productId), ['a', 'b']);
      expect(products.first.title, 'A');
      expect(products.first.formattedPrice, '1,99 €');
    });

    test('skips malformed entries and null lists', () {
      expect(parseStoreKitProducts(null, ['a']), isEmpty);
      expect(
        parseStoreKitProducts(
          [
            'not a map',
            {'id': 'a', 'displayName': 1, 'displayPrice': '1,99 €'},
            {'id': 'a', 'displayName': 'A'},
          ],
          ['a'],
        ),
        isEmpty,
      );
    });
  });

  group('MacStoreKitSupportStoreBridge', () {
    test('isAvailable forwards the native answer', () async {
      mockNative((call) async => call.method == 'isAvailable' ? true : null);
      expect(await MacStoreKitSupportStoreBridge().isAvailable(), isTrue);
    });

    test('loadProducts sends the ids and parses the native list', () async {
      Object? sentArgs;
      mockNative((call) async {
        sentArgs = call.arguments;
        return [
          {
            'id': 'whispaste.support.once.2',
            'displayName': 'Two',
            'displayPrice': '4,99 €',
          },
        ];
      });

      final products = await MacStoreKitSupportStoreBridge().loadProducts([
        'whispaste.support.once.2',
      ]);

      expect(sentArgs, {
        'ids': ['whispaste.support.once.2'],
      });
      expect(products.single.formattedPrice, '4,99 €');
    });

    test('loadProducts returns an empty list on PlatformException', () async {
      mockNative((call) async => throw PlatformException(code: 'load_failed'));
      expect(
        await MacStoreKitSupportStoreBridge().loadProducts(['a']),
        isEmpty,
      );
    });

    test('loadProducts does not call native for an empty id list', () async {
      var called = false;
      mockNative((call) async {
        called = true;
        return const [];
      });
      expect(await MacStoreKitSupportStoreBridge().loadProducts([]), isEmpty);
      expect(called, isFalse);
    });

    test(
      'purchase rejects an id outside the catalogue without a native call',
      () async {
        var called = false;
        mockNative((call) async {
          called = true;
          return 'succeeded';
        });
        expect(
          await MacStoreKitSupportStoreBridge().purchase(
            'whispaste.support.once.9',
          ),
          SupportPurchaseStatus.unavailable,
        );
        expect(called, isFalse);
      },
    );

    test(
      'loadProducts drops ids outside the catalogue before the native call',
      () async {
        Object? sentArgs;
        mockNative((call) async {
          sentArgs = call.arguments;
          return const [];
        });
        await MacStoreKitSupportStoreBridge().loadProducts([
          'whispaste.support.once.9',
          'whispaste.support.once.1',
        ]);
        expect(sentArgs, {
          'ids': ['whispaste.support.once.1'],
        });
      },
    );

    test('loadProducts makes no native call when no id is known', () async {
      var called = false;
      mockNative((call) async {
        called = true;
        return const [];
      });
      expect(
        await MacStoreKitSupportStoreBridge().loadProducts(['unknown']),
        isEmpty,
      );
      expect(called, isFalse);
    });

    test('purchase maps the native status', () async {
      mockNative((call) async => 'cancelled');
      expect(
        await MacStoreKitSupportStoreBridge().purchase(
          'whispaste.support.once.1',
        ),
        SupportPurchaseStatus.cancelled,
      );
    });

    test('purchase maps PlatformException to serverError', () async {
      mockNative((call) async => throw PlatformException(code: 'INVALID_ARGS'));
      expect(
        await MacStoreKitSupportStoreBridge().purchase(
          'whispaste.support.once.1',
        ),
        SupportPurchaseStatus.serverError,
      );
    });

    test('purchase maps a missing native handler to unavailable', () async {
      // No handler registered: the channel throws MissingPluginException.
      expect(
        await MacStoreKitSupportStoreBridge().purchase(
          'whispaste.support.once.1',
        ),
        SupportPurchaseStatus.unavailable,
      );
    });

    test(
      'verification queries fall back to false on PlatformException',
      () async {
        mockNative((call) async => throw PlatformException(code: 'boom'));
        final bridge = MacStoreKitSupportStoreBridge();
        expect(await bridge.isAvailable(), isFalse);
        expect(await bridge.hasVerifiedAppPurchase(), isFalse);
        expect(await bridge.hasVerifiedSupportPurchase(), isFalse);
      },
    );

    test('verification queries pass through native true', () async {
      mockNative((call) async => true);
      final bridge = MacStoreKitSupportStoreBridge();
      expect(await bridge.hasVerifiedAppPurchase(), isTrue);
      expect(await bridge.hasVerifiedSupportPurchase(), isTrue);
    });
  });
}
