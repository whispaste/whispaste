import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/bundle_id_migration_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.whispaste.bundle_id_migration');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('OldPreferencesAdapter', () {
    test('read() returns the native bridge value', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return 'legacy-value';
          });

      final result = await const OldPreferencesAdapter().read('some_key');

      expect(result, 'legacy-value');
      expect(captured?.method, 'readOldPreference');
      expect(captured?.arguments, {
        'oldBundleId': kOldBundleId,
        'key': 'some_key',
      });
    });

    test(
      'read() returns null when no handler is registered (non-macOS)',
      () async {
        final result = await const OldPreferencesAdapter().read('some_key');
        expect(result, isNull);
      },
    );

    test('read() returns null on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'ERR');
          });

      final result = await const OldPreferencesAdapter().read('some_key');
      expect(result, isNull);
    });

    test('write()/readAll() are unsupported', () {
      const adapter = OldPreferencesAdapter();
      expect(() => adapter.write('k', 'v'), throwsUnsupportedError);
      expect(() => adapter.readAll(), throwsUnsupportedError);
    });
  });

  group('OldKeychainAdapter', () {
    test('read() returns the native bridge value', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return 'sk-legacy';
          });

      final result = await const OldKeychainAdapter().read('wp_openai_api_key');

      expect(result, 'sk-legacy');
      expect(captured?.method, 'readOldKeychainValue');
      expect(captured?.arguments, {
        'service': kSecureStorageDefaultService,
        'account': 'wp_openai_api_key',
      });
    });

    test(
      'read() returns null when no handler is registered (non-macOS)',
      () async {
        final result = await const OldKeychainAdapter().read(
          'wp_openai_api_key',
        );
        expect(result, isNull);
      },
    );

    test(
      'read() returns null on PlatformException (denied cross-identity access)',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(code: 'ERR');
            });

        final result = await const OldKeychainAdapter().read(
          'wp_openai_api_key',
        );
        expect(result, isNull);
      },
    );

    test('write()/readAll() are unsupported', () {
      const adapter = OldKeychainAdapter();
      expect(() => adapter.write('k', 'v'), throwsUnsupportedError);
      expect(() => adapter.readAll(), throwsUnsupportedError);
    });
  });
}
