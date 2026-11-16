import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/legacy_update_channel_migration.dart';

void main() {
  group('migrateLegacyUpdateChannel', () {
    test(
      'a stored beta choice is dropped, other settings stay untouched',
      () async {
        SharedPreferences.setMockInitialValues({
          legacyUpdateChannelKey: 'beta',
          'last_page': 'settings',
        });
        final prefs = await SharedPreferences.getInstance();

        await migrateLegacyUpdateChannel(prefs);

        expect(prefs.containsKey(legacyUpdateChannelKey), isFalse);
        expect(prefs.getString('last_page'), 'settings');
      },
    );

    test('a stored stable choice is dropped as well', () async {
      SharedPreferences.setMockInitialValues({
        legacyUpdateChannelKey: 'stable',
      });
      final prefs = await SharedPreferences.getInstance();

      await migrateLegacyUpdateChannel(prefs);

      expect(prefs.containsKey(legacyUpdateChannelKey), isFalse);
    });

    test('without a stored value nothing changes and nothing throws', () async {
      SharedPreferences.setMockInitialValues({'last_page': 'home'});
      final prefs = await SharedPreferences.getInstance();

      await migrateLegacyUpdateChannel(prefs);

      expect(prefs.getKeys(), {'last_page'});
    });
  });
}
