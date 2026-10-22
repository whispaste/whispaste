import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('modifier-only hotkey', () {
    test('defaults to none, so the key combination stays in charge', () {
      expect(HotkeySettings.defaults.hotkeyModifierOnly, '');
    });

    test('roundtrips every choice through the storage map', () {
      for (final choice in ['rightControl', 'rightAlt', 'rightMeta', 'fn']) {
        final restored = HotkeySettings.fromMap(
          HotkeySettings(hotkeyModifierOnly: choice).toMap(),
        );
        expect(restored.hotkeyModifierOnly, choice);
      }
    });

    test('an unknown stored value falls back to none', () {
      final restored = HotkeySettings.fromMap({
        'hotkey_modifier_only': 'leftHyper',
      });
      expect(restored.hotkeyModifierOnly, '');
    });
  });

  group('double-tap action', () {
    test('defaults to none', () {
      expect(AudioInputSettings.defaults.doubleTapAction, DoubleTapAction.none);
    });

    test('roundtrips every action through the storage map', () {
      for (final action in DoubleTapAction.values) {
        final restored = AudioInputSettings.fromMap(
          AudioInputSettings(doubleTapAction: action).toMap(),
        );
        expect(restored.doubleTapAction, action, reason: action.name);
      }
    });

    test('an unknown stored value falls back to none', () {
      final restored = AudioInputSettings.fromMap({
        'double_tap_action': 'launchRockets',
      });
      expect(restored.doubleTapAction, DoubleTapAction.none);
    });

    test('legacy hands-free bool migrates to handsFree', () {
      final restored = AudioInputSettings.fromMap({
        'double_tap_hands_free': 'true',
      });
      expect(restored.doubleTapAction, DoubleTapAction.handsFree);
    });

    test('legacy hands-free bool false migrates to none', () {
      final restored = AudioInputSettings.fromMap({
        'double_tap_hands_free': 'false',
      });
      expect(restored.doubleTapAction, DoubleTapAction.none);
    });

    test('a stored action wins over the legacy bool', () {
      final restored = AudioInputSettings.fromMap({
        'double_tap_hands_free': 'true',
        'double_tap_action': 'quickNote',
      });
      expect(restored.doubleTapAction, DoubleTapAction.quickNote);
    });
  });
}
