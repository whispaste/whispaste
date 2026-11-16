import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/services/hotkey_trigger.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

void main() {
  const ctrlShiftD = HotkeyComboTrigger(
    key: LogicalKeyboardKey.keyD,
    modifiers: {HotKeyModifier.control, HotKeyModifier.shift},
  );
  const shiftCtrlD = HotkeyComboTrigger(
    key: LogicalKeyboardKey.keyD,
    modifiers: {HotKeyModifier.shift, HotKeyModifier.control},
  );
  const ctrlShiftN = HotkeyComboTrigger(
    key: LogicalKeyboardKey.keyN,
    modifiers: {HotKeyModifier.control, HotKeyModifier.shift},
  );
  const fnDoubleTap = HotkeyDoubleTapTrigger(ModifierHotkey.fn);
  const rightAltDoubleTap = HotkeyDoubleTapTrigger(ModifierHotkey.rightAlt);

  group('signatures', () {
    test('a combination signature does not depend on modifier order', () {
      expect(ctrlShiftD.signature, shiftCtrlD.signature);
    });

    test('different keys or modifiers give different signatures', () {
      expect(ctrlShiftD.signature, isNot(ctrlShiftN.signature));
      expect(
        ctrlShiftD.signature,
        isNot(
          const HotkeyComboTrigger(
            key: LogicalKeyboardKey.keyD,
            modifiers: {HotKeyModifier.control},
          ).signature,
        ),
      );
    });

    test('a double tap never equals a combination', () {
      expect(fnDoubleTap.signature, isNot(ctrlShiftD.signature));
      expect(fnDoubleTap.signature, isNot(rightAltDoubleTap.signature));
    });
  });

  group('findTriggerConflicts', () {
    test('every trigger on exactly one action gives no conflict', () {
      expect(
        findTriggerConflicts({
          'dictation': ctrlShiftD,
          'quickNote': ctrlShiftN,
          'snippetPicker': fnDoubleTap,
        }),
        isEmpty,
      );
    });

    test('two actions on the same combination are reported together', () {
      final conflicts = findTriggerConflicts({
        'dictation': ctrlShiftD,
        'quickNote': shiftCtrlD,
        'snippetPicker': ctrlShiftN,
      });

      expect(conflicts, hasLength(1));
      expect(
        conflicts.single.actionIds,
        unorderedEquals(['dictation', 'quickNote']),
      );
    });

    test('a double tap and a combination on the same key do not collide', () {
      expect(
        findTriggerConflicts({
          'dictation': fnDoubleTap,
          'quickNote': const HotkeyComboTrigger(key: LogicalKeyboardKey.keyD),
        }),
        isEmpty,
      );
    });

    test('two actions on the same double tap are reported', () {
      final conflicts = findTriggerConflicts({
        'dictation': fnDoubleTap,
        'snippetPicker': fnDoubleTap,
      });

      expect(conflicts.single.trigger, fnDoubleTap);
      expect(
        conflicts.single.actionIds,
        unorderedEquals(['dictation', 'snippetPicker']),
      );
    });
  });

  group('triggerHolder (live check in the dialog)', () {
    final assignments = <String, HotkeyTrigger>{
      'dictation': ctrlShiftD,
      'quickNote': fnDoubleTap,
    };

    test('names the action that already holds the candidate', () {
      expect(
        triggerHolder(
          shiftCtrlD,
          forAction: 'snippetPicker',
          assignments: assignments,
        ),
        'dictation',
      );
    });

    test('is null for a free trigger', () {
      expect(
        triggerHolder(
          ctrlShiftN,
          forAction: 'snippetPicker',
          assignments: assignments,
        ),
        isNull,
      );
    });

    test('an action does not conflict with its own current trigger', () {
      expect(
        triggerHolder(
          ctrlShiftD,
          forAction: 'dictation',
          assignments: assignments,
        ),
        isNull,
      );
    });
  });

  group('doubleTapSupported', () {
    test('Fn is available on macOS only', () {
      expect(
        doubleTapSupported(ModifierHotkey.fn, isMacOS: true, isWayland: false),
        isTrue,
      );
      expect(
        doubleTapSupported(ModifierHotkey.fn, isMacOS: false, isWayland: false),
        isFalse,
      );
    });

    test('right-side keys work on Windows and Linux X11', () {
      for (final key in [
        ModifierHotkey.rightControl,
        ModifierHotkey.rightAlt,
        ModifierHotkey.rightMeta,
      ]) {
        expect(
          doubleTapSupported(key, isMacOS: false, isWayland: false),
          isTrue,
          reason: key.name,
        );
      }
    });

    test('no double tap under Wayland, where no key-up arrives', () {
      for (final key in ModifierHotkey.values) {
        expect(
          doubleTapSupported(key, isMacOS: false, isWayland: true),
          isFalse,
          reason: key.name,
        );
      }
    });
  });
}
