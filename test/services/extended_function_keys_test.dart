import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/hotkey_key_resolver.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';

void main() {
  for (var n = 13; n <= 24; n++) {
    test('F$n survives storage and reaches each native channel table', () {
      final key = resolveKey('F$n');
      final physical = PhysicalKeyboardKey(0x70068 + n - 13);
      final captured = canonicalRecordableKey(
        KeyDownEvent(
          physicalKey: physical,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
      final restored = HotkeySettings.fromMap(
        HotkeySettings(
          hotkeyKey: labelForKey(captured!)!,
          hotkeyModifiers: '',
        ).toMap(),
      );
      expect(restored.hotkeyKey, 'F$n');
      expect(restored.hotkeyModifiers, isEmpty);
      expect(restored.hotkeyDoubleTapKey, isEmpty);
      final hotKey = HotKey(
        key: resolveKey(restored.hotkeyKey),
        modifiers: resolveModifiers(restored.hotkeyModifiers),
      );
      expect(hotKey.physicalKey, physical);
      expect(kWindowsToLogicalKey[0x7c + n - 13], key);
      expect(kGtkToLogicalKey[0xffca + n - 13], key);
      expect(xdgShortcutTrigger(hotKey), 'F$n');
      expect(kMacOsToPhysicalKey.containsValue(physical), n <= 20);
    });
  }

  test('X11 XF86Tools at the F13 position is stored as F13', () {
    final key = canonicalRecordableKey(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.f13,
        logicalKey: LogicalKeyboardKey(0x1008ff81),
        timeStamp: Duration.zero,
      ),
    );
    expect(key, LogicalKeyboardKey.f13);
    expect(labelForKey(key!), 'F13');
  });

  test('missing native mapping is not reported as another app', () {
    expect(
      hotkeyFailureStatus(PlatformException(code: 'hotkey_unsupported')),
      HotkeyRegistrationStatus.unknownKey,
    );
  });
}
