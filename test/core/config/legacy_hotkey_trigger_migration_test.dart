import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

/// Map of the entries a load has to write back: exactly the keys whose value
/// changed. Same diff the settings provider persists.
Map<String, String> _writes(
  Map<String, String> raw,
  bool Function(String) observable,
) {
  final migrated = migrateLegacyHotkeyTriggers(
    raw,
    doubleTapObservable: observable,
  );
  return {
    for (final e in migrated.entries)
      if (raw[e.key] != e.value) e.key: e.value,
  };
}

void main() {
  group('legacy hold key becomes the double-tap trigger', () {
    test('a supported hold key moves to the double-tap trigger', () {
      final raw = {'hotkey_modifier_only': 'rightAlt'};
      final migrated = migrateLegacyHotkeyTriggers(
        raw,
        doubleTapObservable: (_) => true,
      );
      expect(migrated['hotkey_double_tap_key'], 'rightAlt');
      expect(migrated['hotkey_modifier_only'], '');
    });

    test(
      'an unsupported hold key keeps the combination and drops the hold',
      () {
        final raw = {
          'hotkey_modifier_only': 'fn',
          'hotkey_key': 'D',
          'hotkey_modifiers': 'ctrl+shift',
        };
        final migrated = migrateLegacyHotkeyTriggers(
          raw,
          doubleTapObservable: (choice) => choice != 'fn',
        );
        expect(migrated['hotkey_double_tap_key'] ?? '', '');
        expect(migrated['hotkey_modifier_only'], '');
        expect(migrated['hotkey_key'], 'D');
        expect(migrated['hotkey_modifiers'], 'ctrl+shift');
      },
    );

    test('an existing double-tap trigger wins over the legacy hold key', () {
      final raw = {
        'hotkey_modifier_only': 'rightAlt',
        'hotkey_double_tap_key': 'fn',
      };
      final migrated = migrateLegacyHotkeyTriggers(
        raw,
        doubleTapObservable: (_) => true,
      );
      expect(migrated['hotkey_double_tap_key'], 'fn');
      expect(migrated['hotkey_modifier_only'], '');
    });

    test('an unknown stored hold key is cleared and creates no trigger', () {
      final raw = {'hotkey_modifier_only': 'leftHyper'};
      final migrated = migrateLegacyHotkeyTriggers(
        raw,
        doubleTapObservable: (_) => true,
      );
      expect(migrated['hotkey_double_tap_key'] ?? '', '');
      expect(migrated['hotkey_modifier_only'], '');
    });
  });

  group('legacy double-tap action is dropped', () {
    test('a quick-note action on the dictation key is cleared', () {
      final raw = {'double_tap_action': 'quickNote'};
      final migrated = migrateLegacyHotkeyTriggers(
        raw,
        doubleTapObservable: (_) => true,
      );
      expect(migrated['double_tap_action'], '');
      expect(migrated['hotkey_double_tap_key'] ?? '', '');
    });

    test('a snippet-picker action creates no double-tap trigger', () {
      final raw = {
        'double_tap_action': 'snippetPicker',
        'hotkey_modifier_only': 'rightAlt',
      };
      final migrated = migrateLegacyHotkeyTriggers(
        raw,
        doubleTapObservable: (_) => true,
      );
      expect(migrated['double_tap_action'], '');
      expect(migrated['hotkey_double_tap_key'], 'rightAlt');
    });

    test('the retired hands-free bool is cleared', () {
      final migrated = migrateLegacyHotkeyTriggers({
        'double_tap_hands_free': 'true',
      }, doubleTapObservable: (_) => true);
      expect(migrated['double_tap_hands_free'], '');
    });
  });

  group('once only', () {
    test('inactive legacy values write nothing', () {
      expect(
        _writes({
          'hotkey_modifier_only': '',
          'double_tap_action': 'none',
          'double_tap_hands_free': 'false',
        }, (_) => true),
        isEmpty,
      );
    });

    test('a second load after migration writes nothing', () {
      final raw = {'hotkey_modifier_only': 'rightAlt'};
      final first = _writes(raw, (_) => true);
      expect(first, {
        'hotkey_double_tap_key': 'rightAlt',
        'hotkey_modifier_only': '',
      });

      final stored = {...raw, ...first};
      expect(_writes(stored, (_) => true), isEmpty);
    });

    test('clearing the trigger later is not undone by the legacy hold', () {
      // The first load moved the legacy hold key to the double-tap trigger and
      // cleared the hold. A user who later clears the trigger must not get the
      // old hold key back on the next load.
      final stored = {'hotkey_modifier_only': '', 'hotkey_double_tap_key': ''};
      expect(_writes(stored, (_) => true), isEmpty);
    });
  });

  test('the migrated values read back through the settings model', () {
    final migrated = migrateLegacyHotkeyTriggers({
      'hotkey_modifier_only': 'rightMeta',
    }, doubleTapObservable: (_) => true);
    expect(HotkeySettings.fromMap(migrated).hotkeyDoubleTapKey, 'rightMeta');
  });
}
