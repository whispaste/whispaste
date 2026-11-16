import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('double-tap trigger key', () {
    test('defaults to none, so the key combination stays the trigger', () {
      expect(HotkeySettings.defaults.hotkeyDoubleTapKey, '');
    });

    test('roundtrips every choice through the storage map', () {
      for (final choice in modifierOnlyHotkeyChoices) {
        final restored = HotkeySettings.fromMap(
          HotkeySettings(hotkeyDoubleTapKey: choice).toMap(),
        );
        expect(restored.hotkeyDoubleTapKey, choice);
      }
    });

    test('an older store without the key reads as none', () {
      final restored = HotkeySettings.fromMap({'hotkey_key': 'D'});
      expect(restored.hotkeyDoubleTapKey, '');
      expect(restored.hotkeyKey, 'D');
    });

    test('an unknown stored value falls back to none', () {
      final restored = HotkeySettings.fromMap({
        'hotkey_double_tap_key': 'leftHyper',
      });
      expect(restored.hotkeyDoubleTapKey, '');
    });
  });
}
