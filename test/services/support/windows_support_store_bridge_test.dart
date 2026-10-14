import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';
import 'package:whispaste/services/support/windows_support_store_bridge.dart';

const _channel = MethodChannel('com.whispaste.support_store');

void _mockNative(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bridge = WindowsSupportStoreBridge(channel: _channel);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('isAvailable', () {
    test('returns the native answer', () async {
      _mockNative((call) async {
        expect(call.method, 'isAvailable');
        return true;
      });
      expect(await bridge.isAvailable(), isTrue);
    });

    test('is false when native answers null', () async {
      _mockNative((_) async => null);
      expect(await bridge.isAvailable(), isFalse);
    });

    test('is false when the channel throws', () async {
      _mockNative((_) async => throw PlatformException(code: 'boom'));
      expect(await bridge.isAvailable(), isFalse);
    });

    test('is false when the native plugin is missing', () async {
      _mockNative((_) async => throw MissingPluginException());
      expect(await bridge.isAvailable(), isFalse);
    });
  });

  group('loadProducts', () {
    test('returns no products without calling native for empty ids', () async {
      var called = false;
      _mockNative((_) async {
        called = true;
        return <Object?>[];
      });
      expect(await bridge.loadProducts(const []), isEmpty);
      expect(called, isFalse);
    });

    test('sends the requested ids and keeps the requested order', () async {
      Object? sentArguments;
      _mockNative((call) async {
        expect(call.method, 'loadProducts');
        sentArguments = call.arguments;
        return <Object?>[
          {
            'productId': 'whispaste.support.once.3',
            'title': 'Three',
            'formattedPrice': '9,99 €',
          },
          {
            'productId': 'whispaste.support.once.1',
            'title': 'One',
            'formattedPrice': '1,99 €',
          },
        ];
      });

      final products = await bridge.loadProducts(const [
        'whispaste.support.once.1',
        'whispaste.support.once.3',
      ]);

      expect(sentArguments, {
        'productIds': ['whispaste.support.once.1', 'whispaste.support.once.3'],
      });
      expect(products.map((p) => p.productId), [
        'whispaste.support.once.3',
        'whispaste.support.once.1',
      ]);
      expect(products.first.formattedPrice, '9,99 €');
      expect(products.first.title, 'Three');
    });

    test('skips malformed, unrequested and unpriced entries', () async {
      _mockNative(
        (_) async => <Object?>[
          'not a map',
          {'productId': 'whispaste.support.once.1', 'title': 'No price'},
          {
            'productId': 'whispaste.support.once.9',
            'title': 'Not requested',
            'formattedPrice': '49,99 €',
          },
          {
            'productId': 'whispaste.support.once.2',
            'title': 'Empty price',
            'formattedPrice': '',
          },
          {
            'productId': 'whispaste.support.once.2',
            'title': 'Two',
            'formattedPrice': '4,99 €',
          },
        ],
      );

      final products = await bridge.loadProducts(const [
        'whispaste.support.once.1',
        'whispaste.support.once.2',
      ]);

      expect(products.map((p) => p.productId), ['whispaste.support.once.2']);
    });

    test('is empty when the channel throws', () async {
      _mockNative((_) async => throw PlatformException(code: 'store_error'));
      expect(
        await bridge.loadProducts(const ['whispaste.support.once.1']),
        isEmpty,
      );
    });

    test('is empty when native answers a non-list payload', () async {
      _mockNative((_) async => 'unexpected');
      expect(
        await bridge.loadProducts(const ['whispaste.support.once.1']),
        isEmpty,
      );
    });
  });

  group('unknown product ids', () {
    test('loadProducts drops unknown ids before calling native', () async {
      Object? sentArguments;
      _mockNative((call) async {
        sentArguments = call.arguments;
        return <Object?>[];
      });
      await bridge.loadProducts(const [
        'whispaste.support.once.9',
        'whispaste.support.once.4',
      ]);
      expect(sentArguments, {
        'productIds': ['whispaste.support.once.4'],
      });
    });

    test('loadProducts makes no call when every id is unknown', () async {
      var called = false;
      _mockNative((_) async {
        called = true;
        return <Object?>[];
      });
      expect(
        await bridge.loadProducts(const ['whispaste.support.once.9']),
        isEmpty,
      );
      expect(called, isFalse);
    });

    test('purchase returns unavailable without calling native', () async {
      var called = false;
      _mockNative((_) async {
        called = true;
        return 'succeeded';
      });
      expect(
        await bridge.purchase('whispaste.support.once.9'),
        SupportPurchaseStatus.unavailable,
      );
      expect(called, isFalse);
      expect(await bridge.hasVerifiedSupportPurchase(), isFalse);
    });
  });

  group('purchase status mapping', () {
    final cases = <String, SupportPurchaseStatus>{
      'succeeded': SupportPurchaseStatus.succeeded,
      'cancelled': SupportPurchaseStatus.cancelled,
      'pending': SupportPurchaseStatus.pending,
      'networkError': SupportPurchaseStatus.networkError,
      'serverError': SupportPurchaseStatus.serverError,
      'unavailable': SupportPurchaseStatus.unavailable,
    };

    for (final entry in cases.entries) {
      test('maps native "${entry.key}"', () async {
        _mockNative((call) async {
          expect(call.method, 'purchase');
          expect(call.arguments, {'productId': 'whispaste.support.once.2'});
          return entry.key;
        });
        expect(await bridge.purchase('whispaste.support.once.2'), entry.value);
      });
    }

    test('unknown native status falls back to serverError', () async {
      _mockNative((_) async => 'alreadyPurchased');
      expect(
        await bridge.purchase('whispaste.support.once.2'),
        SupportPurchaseStatus.serverError,
      );
    });

    test('null native status falls back to serverError', () async {
      _mockNative((_) async => null);
      expect(
        await bridge.purchase('whispaste.support.once.2'),
        SupportPurchaseStatus.serverError,
      );
    });

    test('store_unavailable PlatformException maps to unavailable', () async {
      _mockNative(
        (_) async => throw PlatformException(code: 'store_unavailable'),
      );
      expect(
        await bridge.purchase('whispaste.support.once.2'),
        SupportPurchaseStatus.unavailable,
      );
    });

    test('other PlatformException maps to serverError', () async {
      _mockNative((_) async => throw PlatformException(code: 'store_error'));
      expect(
        await bridge.purchase('whispaste.support.once.2'),
        SupportPurchaseStatus.serverError,
      );
    });

    test('missing native plugin maps to unavailable', () async {
      _mockNative((_) async => throw MissingPluginException());
      expect(
        await bridge.purchase('whispaste.support.once.2'),
        SupportPurchaseStatus.unavailable,
      );
    });

    test('a wrong-typed payload maps to serverError', () async {
      _mockNative((_) async => 42);
      expect(
        await bridge.purchase('whispaste.support.once.2'),
        SupportPurchaseStatus.serverError,
      );
    });
  });

  group('hasVerifiedSupportPurchase', () {
    test('is false before any purchase', () async {
      expect(await bridge.hasVerifiedSupportPurchase(), isFalse);
    });

    test('is true after a succeeded purchase', () async {
      _mockNative((_) async => 'succeeded');
      await bridge.purchase('whispaste.support.once.1');
      expect(await bridge.hasVerifiedSupportPurchase(), isTrue);
    });

    test('stays false after cancelled, failed or pending purchases', () async {
      for (final status in ['cancelled', 'networkError', 'pending']) {
        _mockNative((_) async => status);
        await bridge.purchase('whispaste.support.once.1');
      }
      expect(await bridge.hasVerifiedSupportPurchase(), isFalse);
    });
  });

  group('hasVerifiedAppPurchase', () {
    test('returns the native verdict', () async {
      _mockNative((call) async {
        expect(call.method, 'hasVerifiedAppPurchase');
        return true;
      });
      expect(await bridge.hasVerifiedAppPurchase(), isTrue);
    });

    test('is false when native answers null', () async {
      _mockNative((_) async => null);
      expect(await bridge.hasVerifiedAppPurchase(), isFalse);
    });

    test('is false when the channel throws', () async {
      _mockNative((_) async => throw PlatformException(code: 'store_error'));
      expect(await bridge.hasVerifiedAppPurchase(), isFalse);
    });

    test('is false when the native plugin is missing', () async {
      _mockNative((_) async => throw MissingPluginException());
      expect(await bridge.hasVerifiedAppPurchase(), isFalse);
    });
  });
}
