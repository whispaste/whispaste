/// Native check that the hotkey recorder sees a combination the app has
/// registered system-wide (ticket hotkey-rerecord-same, fix 68da2fd72).
///
/// A system-wide registration (Windows RegisterHotKey, X11 grab through
/// keybinder) takes the press before Flutter does, so re-recording the saved
/// combination left only the modifier in the recorder. While a recorder
/// listens, the hotkey service takes its registrations off the system and
/// puts them back afterwards. This test registers Ctrl+Shift+F9 through the
/// real plugin, injects the press with the system's own input path (SendInput
/// on Windows, XTest on X11) and checks three states: registered without a
/// recorder (the hotkey fires, Flutter sees no F9), recorder open (Flutter
/// sees F9, the recorder submits Ctrl+Shift+F9, the hotkey does not fire),
/// recorder closed (the hotkey fires again).
///
/// Needs an interactive desktop session on Windows (SendInput). On Linux it
/// runs on a private Xvfb display, like test/scripts/keybinder_raw_test.sh:
/// inside a GNOME Wayland session the XTest press on Xwayland never reached
/// the grab, so even the registered hotkey did not fire (lab run
/// 1101-161855). The Wayland portal path is not covered here.
///   flutter test integration_test/hotkey_rerecord_native_test.dart -d windows
///   env -u WAYLAND_DISPLAY GDK_BACKEND=x11 xvfb-run -a \
///     flutter test integration_test/hotkey_rerecord_native_test.dart -d linux
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/hotkey_self_heal.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

/// The three keys of the combination, pressed in this order and released in
/// reverse.
enum _Key { control, shift, f9 }

/// Injects key presses through the platform's own input path.
abstract class _Injector {
  factory _Injector() => Platform.isWindows ? _SendInput() : _XTest();

  void send(_Key key, {required bool down});
}

class _SendInput implements _Injector {
  static const _inputKeyboard = 1;
  static const _keyeventfKeyUp = 0x0002;
  static const _keyeventfScanCode = 0x0008;

  /// `sizeof(INPUT)` on x64; KEYBDINPUT starts at offset 8.
  static const _inputSize = 40;

  static const _scan = {_Key.control: 0x1D, _Key.shift: 0x2A, _Key.f9: 0x43};

  final _sendInput = DynamicLibrary.open('user32.dll')
      .lookupFunction<
        Uint32 Function(Uint32, Pointer<Uint8>, Int32),
        int Function(int, Pointer<Uint8>, int)
      >('SendInput');

  @override
  void send(_Key key, {required bool down}) {
    final input = calloc<Uint8>(_inputSize);
    try {
      final data = ByteData.sublistView(input.asTypedList(_inputSize));
      data.setUint32(0, _inputKeyboard, Endian.little);
      data.setUint16(10, _scan[key]!, Endian.little);
      data.setUint32(
        12,
        _keyeventfScanCode | (down ? 0 : _keyeventfKeyUp),
        Endian.little,
      );
      expect(_sendInput(1, input, _inputSize), 1, reason: 'SendInput refused');
    } finally {
      calloc.free(input);
    }
  }
}

class _XTest implements _Injector {
  _XTest() {
    final x11 = DynamicLibrary.open('libX11.so.6');
    final xtst = DynamicLibrary.open('libXtst.so.6');
    _display = x11
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>),
          Pointer<Void> Function(Pointer<Utf8>)
        >('XOpenDisplay')(nullptr);
    expect(_display, isNot(nullptr), reason: 'no X11 display (DISPLAY)');
    _keysymToKeycode = x11
        .lookupFunction<
          Uint8 Function(Pointer<Void>, UnsignedLong),
          int Function(Pointer<Void>, int)
        >('XKeysymToKeycode');
    _flush = x11
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('XFlush');
    _fakeKey = xtst
        .lookupFunction<
          Int32 Function(Pointer<Void>, UnsignedInt, Int32, UnsignedLong),
          int Function(Pointer<Void>, int, int, int)
        >('XTestFakeKeyEvent');
  }

  static const _keysym = {
    _Key.control: 0xffe3, // Control_L
    _Key.shift: 0xffe1, // Shift_L
    _Key.f9: 0xffc6, // F9
  };

  late final Pointer<Void> _display;
  late final int Function(Pointer<Void>, int) _keysymToKeycode;
  late final int Function(Pointer<Void>) _flush;
  late final int Function(Pointer<Void>, int, int, int) _fakeKey;

  @override
  void send(_Key key, {required bool down}) {
    final code = _keysymToKeycode(_display, _keysym[key]!);
    expect(code, isNonZero, reason: 'no keycode for $key');
    expect(_fakeKey(_display, code, down ? 1 : 0, 0), isNonZero);
    _flush(_display);
  }
}

/// Presses and releases Ctrl+Shift+F9 like a person would.
Future<void> _pressCombo(_Injector injector) async {
  for (final key in _Key.values) {
    injector.send(key, down: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  for (final key in _Key.values.reversed) {
    injector.send(key, down: false);
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  // The press arrives through the runner's message loop.
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(hotkeyEnabled: false);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the recorder sees the registered combination, the hotkey '
      'comes back after it', (tester) async {
    addTearDown(HotkeyCaptureGuard.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        hotkeyServiceProvider.overrideWith(
          () => HotkeyService()..injectMonitor(NoopKeyboardUpMonitor()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(hotkeyServiceProvider.notifier);
    var fired = 0;
    service.onHotkeyPressed = () => fired++;

    var f9Seen = 0;
    bool watch(KeyEvent event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f9) {
        f9Seen++;
      }
      return false;
    }

    HardwareKeyboard.instance.addHandler(watch);
    addTearDown(() => HardwareKeyboard.instance.removeHandler(watch));

    final injector = _Injector();
    await tester.runAsync(
      () => service.updateHotkey(
        key: LogicalKeyboardKey.f9,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
      ),
    );
    addTearDown(hotKeyManager.unregisterAll);

    // Registered, no recorder: the system takes the press.
    await tester.runAsync(() => _pressCombo(injector));
    await tester.pump();
    expect(fired, 1, reason: 'the registered hotkey must fire');
    expect(f9Seen, 0, reason: 'a registered combination never reaches Flutter');

    // Recorder open: the registration is off, the recorder gets the press.
    final submitted = <WpHotkeyResult>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: wpDarkTheme(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: WpHotkeyRecorderDialog(
              initialKey: 'F9',
              initialModifiers: 'ctrl+shift',
              onSubmit: submitted.add,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => service.captureSuspensionSettled);
    await tester.runAsync(() => _pressCombo(injector));
    await tester.pumpAndSettle();
    expect(f9Seen, 1, reason: 'the recorder must see the saved combination');
    expect(fired, 1, reason: 'recording must not trigger the hotkey');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(submitted.map((r) => (r.modifiers, r.key)), [('ctrl+shift', 'F9')]);

    // Recorder closed: the registration is back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => service.captureSuspensionSettled);
    await tester.runAsync(() => _pressCombo(injector));
    await tester.pump();
    expect(fired, 2, reason: 'the hotkey must work again after recording');
    expect(f9Seen, 1);
    // The native key injector in this harness supports Windows and Linux only.
  }, skip: !(Platform.isWindows || Platform.isLinux));
}
