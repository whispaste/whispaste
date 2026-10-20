import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show InputDevice;
import 'package:whispaste/services/audio/mic_start_cache.dart';

void main() {
  const mic = InputDevice(id: 'mic-1', label: 'Studio Mic');

  group('permission', () {
    test('a granted permission is not checked again', () async {
      final cache = MicStartCache();
      var checks = 0;
      Future<bool> check() async {
        checks++;
        return true;
      }

      expect(await cache.hasPermission(check), isTrue);
      expect(await cache.hasPermission(check), isTrue);
      expect(checks, 1);
    });

    test('a denied permission is checked on every start', () async {
      final cache = MicStartCache();
      var checks = 0;
      Future<bool> check() async {
        checks++;
        return false;
      }

      expect(await cache.hasPermission(check), isFalse);
      expect(await cache.hasPermission(check), isFalse);
      expect(checks, 2);
    });
  });

  group('input devices', () {
    test('a listing is reused within the max age', () async {
      var now = DateTime(2026, 10, 19, 12);
      final cache = MicStartCache(clock: () => now);
      var listings = 0;
      Future<List<InputDevice>?> list() async {
        listings++;
        return [mic];
      }

      await cache.inputDevices(list);
      now = now.add(const Duration(seconds: 29));
      final again = await cache.inputDevices(list);

      expect(listings, 1);
      expect(again!.single.id, 'mic-1');
    });

    test('a listing older than the max age is fetched again', () async {
      var now = DateTime(2026, 10, 19, 12);
      final cache = MicStartCache(clock: () => now);
      var listings = 0;
      Future<List<InputDevice>?> list() async {
        listings++;
        return [mic];
      }

      await cache.inputDevices(list);
      now = now.add(const Duration(seconds: 31));
      await cache.inputDevices(list);

      expect(listings, 2);
    });

    test('a failed listing (null) is never cached', () async {
      final cache = MicStartCache();
      var listings = 0;
      Future<List<InputDevice>?> list() async {
        listings++;
        return null;
      }

      expect(await cache.inputDevices(list), isNull);
      expect(await cache.inputDevices(list), isNull);
      expect(listings, 2);
    });

    test('invalidate drops the listing and the granted permission', () async {
      final cache = MicStartCache();
      var listings = 0;
      var checks = 0;
      Future<List<InputDevice>?> list() async {
        listings++;
        return [mic];
      }

      Future<bool> check() async {
        checks++;
        return true;
      }

      await cache.inputDevices(list);
      await cache.hasPermission(check);
      cache.invalidate();
      await cache.inputDevices(list);
      await cache.hasPermission(check);

      expect(listings, 2);
      expect(checks, 2);
    });
  });
}
