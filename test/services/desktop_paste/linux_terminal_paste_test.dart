/// V1: terminals on Linux paste with Ctrl+Shift+V and copy with
/// Ctrl+Shift+C. Plain Ctrl+V inserts a literal ^V there, and Ctrl+C sends
/// SIGINT to the running program. The target is the X11 WM_CLASS instance
/// name the native host reports (getTargetBundleId).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/terminal_targets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.whispaste.desktop_paste');

  List<MethodCall> fakeHost({Object? target, bool targetThrows = false}) {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getTargetBundleId') {
            if (targetThrows) throw PlatformException(code: 'X');
            return target;
          }
          return {'status': 'success'};
        });
    return calls;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<Object?, Object?> argsOf(List<MethodCall> calls, String method) =>
      calls.singleWhere((c) => c.method == method).arguments as Map;

  group('isLinuxTerminalTarget', () {
    test('knows the common terminals by WM_CLASS instance name', () {
      for (final id in [
        'gnome-terminal-server',
        'konsole',
        'ptyxis',
        'kgx',
        'kitty',
        'Alacritty',
        'org.wezfurlong.wezterm',
        'tilix',
        'xfce4-terminal',
        'terminator',
      ]) {
        expect(isLinuxTerminalTarget(id), isTrue, reason: id);
      }
    });

    test('ignores case and treats other or unknown targets as no terminal', () {
      expect(isLinuxTerminalTarget('KONSOLE'), isTrue);
      expect(isLinuxTerminalTarget('firefox'), isFalse);
      expect(isLinuxTerminalTarget('code'), isFalse);
      expect(isLinuxTerminalTarget(''), isFalse);
      expect(isLinuxTerminalTarget(null), isFalse);
    });
  });

  group('LinuxDesktopPasteController', () {
    // A compositor whose socket connect hangs never answers, and the source's
    // own IPC timeout does not cover the connect. The paste must not wait for
    // it: the Wayland answer is given up and the native lookup decides.
    test(
      'does not wait for a Wayland focus lookup that never answers',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return switch (call.method) {
                'captureTarget' => true,
                'getTargetBundleId' => 'gedit',
                _ => {'status': 'success'},
              };
            });
        final controller = LinuxDesktopPasteController(
          waylandFocus: _NeverAnsweringFocusSource(),
        );

        await controller.capturePasteTarget();
        await controller
            .pasteClipboard(delay: Duration.zero)
            .timeout(const Duration(seconds: 5));

        expect(argsOf(calls, 'pasteClipboard')['shift'], isFalse);
      },
    );

    test('pastes into a terminal with Ctrl+Shift+V', () async {
      final calls = fakeHost(target: 'gnome-terminal-server');

      await LinuxDesktopPasteController().pasteClipboard(delay: Duration.zero);

      expect(argsOf(calls, 'pasteClipboard')['shift'], isTrue);
    });

    test('pastes into other apps with plain Ctrl+V', () async {
      final calls = fakeHost(target: 'gedit');

      await LinuxDesktopPasteController().pasteClipboard(delay: Duration.zero);

      expect(argsOf(calls, 'pasteClipboard')['shift'], isFalse);
    });

    test(
      'an unknown target (Wayland) or a failed lookup keeps Ctrl+V',
      () async {
        for (final throws in [false, true]) {
          final calls = fakeHost(targetThrows: throws);
          final result = await LinuxDesktopPasteController().pasteClipboard(
            delay: Duration.zero,
          );

          expect(argsOf(calls, 'pasteClipboard')['shift'], isFalse);
          expect(result.status.name, 'success');
        }
      },
    );

    test(
      'copies a terminal selection with Ctrl+Shift+C, never Ctrl+C',
      () async {
        final calls = fakeHost(target: 'konsole');

        await LinuxDesktopPasteController().copySelection(delay: Duration.zero);

        expect(argsOf(calls, 'copySelection')['shift'], isTrue);
      },
    );

    test('typeText pastes into a terminal with Ctrl+Shift+V', () async {
      final calls = fakeHost(target: 'kitty');

      await LinuxDesktopPasteController().typeText('hi', delay: Duration.zero);

      expect(argsOf(calls, 'typeText'), {
        'text': 'hi',
        'delayMs': 0,
        'shift': true,
      });
    });
  });

  test('the Linux host reads the shift flag on every shortcut method', () {
    // Parity guard: the flag Dart sends must reach the uinput keyboard,
    // which in turn must be allowed to emit Shift. macOS (Cmd+V in
    // Terminal) and Windows (Ctrl+V in Windows Terminal and conhost) paste
    // into terminals with their normal shortcut and need no flag.
    final host = File('linux/runner/desktop_paste_host.cc').readAsStringSync();
    // The paste is answered later from the paste tick (StartPaste, XP-7-14).
    for (final method in ['StartPaste', 'CopySelection', 'TypeText']) {
      expect(
        host,
        matches(RegExp('$method\\([^;]*GetBool\\(args, "shift"\\)\\)')),
        reason: method,
      );
    }
    expect(host, contains('paste_shift_ = shift;'));
    expect(host, contains('UI_SET_KEYBIT, KEY_LEFTSHIFT'));
  });

  test('macOS sends no shift flag and does not look up the target', () async {
    final calls = fakeHost(target: 'com.apple.Terminal');

    await MacOSDesktopPasteController().pasteClipboard(delay: Duration.zero);

    expect(calls.map((c) => c.method), ['pasteClipboard']);
    expect(argsOf(calls, 'pasteClipboard'), {'delayMs': 0});
  });
}

class _NeverAnsweringFocusSource implements FocusedTargetSource {
  @override
  String get name => 'never-answering';

  @override
  Future<FocusedTarget?> focusedTarget() => Completer<FocusedTarget?>().future;
}
