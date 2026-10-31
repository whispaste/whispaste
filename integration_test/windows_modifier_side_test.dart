/// Windows check that a single-key trigger tells the left and the right key
/// apart (core review F13-1).
///
/// The keyboard host reads the side from Raw Input: the E0 flag for Ctrl and
/// Alt, the scan code for Shift (`keyboard_monitor_host.cpp`,
/// `SideSpecificVk`). This test watches one side through the real channel,
/// presses both sides with `SendInput` scan codes and expects only the
/// watched side as `onModifierDown`/`onModifierUp`; the other side must
/// arrive as `onOtherKey` only (AltGr layouts add a synthetic left Ctrl to
/// the right Alt, which is one more `onOtherKey`, before the right Alt's
/// own down; seen on the German lab VM, run 1031-051335). The Win keys are left
/// out: a tap would open the start menu of the test session.
///
/// Needs an interactive desktop session (SendInput):
///   flutter test integration_test/windows_modifier_side_test.dart -d windows
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

const _inputKeyboard = 1;
const _keyeventfExtendedKey = 0x0001;
const _keyeventfKeyUp = 0x0002;
const _keyeventfScanCode = 0x0008;

/// `sizeof(INPUT)` on x64: type (4) + padding (4) + the union (32, the size
/// of MOUSEINPUT). KEYBDINPUT starts at offset 8.
const _inputSize = 40;

typedef _SendInputC = Uint32 Function(Uint32, Pointer<Uint8>, Int32);
typedef _SendInputDart = int Function(int, Pointer<Uint8>, int);

/// One physical key by scan code; [extended] sets the E0 prefix.
typedef _Key = ({int scan, bool extended});

const _leftShift = (scan: 0x2A, extended: false);
const _rightShift = (scan: 0x36, extended: false);
const _leftControl = (scan: 0x1D, extended: false);
const _rightControl = (scan: 0x1D, extended: true);
const _leftAlt = (scan: 0x38, extended: false);
const _rightAlt = (scan: 0x38, extended: true);

final _sendInput = DynamicLibrary.open(
  'user32.dll',
).lookupFunction<_SendInputC, _SendInputDart>('SendInput');

void _send(_Key key, {required bool up}) {
  final input = calloc<Uint8>(_inputSize);
  try {
    final data = ByteData.sublistView(input.asTypedList(_inputSize));
    data.setUint32(0, _inputKeyboard, Endian.little);
    data.setUint16(10, key.scan, Endian.little);
    data.setUint32(
      12,
      _keyeventfScanCode |
          (key.extended ? _keyeventfExtendedKey : 0) |
          (up ? _keyeventfKeyUp : 0),
      Endian.little,
    );
    expect(_sendInput(1, input, _inputSize), 1, reason: 'SendInput refused');
  } finally {
    calloc.free(input);
  }
}

Future<void> _tap(_Key key) async {
  _send(key, up: false);
  await Future<void>.delayed(const Duration(milliseconds: 60));
  _send(key, up: true);
  // Raw Input arrives through the runner's message loop.
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final cases = <(ModifierHotkey, _Key, _Key)>[
    (ModifierHotkey.leftShift, _leftShift, _rightShift),
    (ModifierHotkey.rightShift, _rightShift, _leftShift),
    (ModifierHotkey.leftControl, _leftControl, _rightControl),
    (ModifierHotkey.rightControl, _rightControl, _leftControl),
    (ModifierHotkey.leftAlt, _leftAlt, _rightAlt),
    (ModifierHotkey.rightAlt, _rightAlt, _leftAlt),
  ];

  for (final (watched, same, other) in cases) {
    testWidgets('${watched.name}: only the watched side is the trigger', (
      tester,
    ) async {
      final inputs = <ModifierInput>[];
      final monitor = ChannelKeyboardUpMonitor()..onModifierInput = inputs.add;
      addTearDown(monitor.stop);

      expect(await monitor.watchModifier(watched), isTrue);

      await tester.runAsync(() => _tap(same));
      // AltGr layouts send their synthetic left Ctrl just before the right
      // Alt. It arrives while the trigger is not held yet, so the gesture
      // machine ignores it; only the watched side may follow.
      final leading = inputs.takeWhile((i) => i == ModifierInput.other);
      expect(inputs.skip(leading.length), [
        ModifierInput.down,
        ModifierInput.up,
      ]);
      if (watched != ModifierHotkey.rightAlt) expect(leading, isEmpty);

      inputs.clear();
      await tester.runAsync(() => _tap(other));
      expect(inputs, isNotEmpty);
      expect(inputs.toSet(), {ModifierInput.other});
    }, skip: !Platform.isWindows);
  }
}
