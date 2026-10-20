/// V1 Wayland: session detection, source choice, and how the Linux paste
/// controller combines the compositor's answer with the native X11 one.
library;

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/compositor_ipc_sources.dart';
import 'package:whispaste/services/desktop_paste/focused_target/dbus_focus_sources.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/terminal_targets.dart';

import 'private_bus.dart';

class _Source implements FocusedTargetSource {
  _Source(this.target);
  final FocusedTarget? target;
  var calls = 0;

  @override
  String get name => 'fake';

  @override
  Future<FocusedTarget?> focusedTarget() async {
    calls++;
    return target;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusedTarget.from', () {
    test('drops empty and duplicate names, keeps order', () {
      final t = FocusedTarget.from([
        ' foot ',
        null,
        '',
        'FOOT',
        'footclient',
      ], source: 's');
      expect(t!.identifiers, ['foot', 'footclient']);
      expect(t.id, 'foot');
    });

    test('no usable name means no target', () {
      expect(FocusedTarget.from([null, ' '], source: 's'), isNull);
    });
  });

  group('detectLinuxFocusDesktop', () {
    const wl = {'WAYLAND_DISPLAY': 'wayland-0'};
    test('X11 sessions', () {
      expect(
        detectLinuxFocusDesktop({'XDG_SESSION_TYPE': 'x11'}),
        LinuxFocusDesktop.x11,
      );
      expect(detectLinuxFocusDesktop({}), LinuxFocusDesktop.x11);
    });

    test('compositor sockets win over XDG_CURRENT_DESKTOP', () {
      expect(
        detectLinuxFocusDesktop({
          ...wl,
          'SWAYSOCK': '/run/s',
          'XDG_CURRENT_DESKTOP': 'GNOME',
        }),
        LinuxFocusDesktop.sway,
      );
      expect(
        detectLinuxFocusDesktop({...wl, 'HYPRLAND_INSTANCE_SIGNATURE': 'x'}),
        LinuxFocusDesktop.hyprland,
      );
      expect(
        detectLinuxFocusDesktop({...wl, 'NIRI_SOCKET': '/run/n'}),
        LinuxFocusDesktop.niri,
      );
    });

    test('desktop names', () {
      expect(
        detectLinuxFocusDesktop({...wl, 'XDG_CURRENT_DESKTOP': 'KDE'}),
        LinuxFocusDesktop.kde,
      );
      expect(
        detectLinuxFocusDesktop({...wl, 'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'}),
        LinuxFocusDesktop.gnome,
      );
      expect(
        detectLinuxFocusDesktop({
          'XDG_SESSION_TYPE': 'wayland',
          'XDG_CURRENT_DESKTOP': 'COSMIC',
        }),
        LinuxFocusDesktop.otherWayland,
      );
    });
  });

  test('waylandFocusSourceFor picks one source per desktop', () {
    final env = {
      'SWAYSOCK': '/run/sway.sock',
      'NIRI_SOCKET': '/run/niri.sock',
      'HYPRLAND_INSTANCE_SIGNATURE': 'sig',
    };
    // The D-Bus sources are only stored here, never connected: a lazy client
    // on a path that does not exist keeps the host's session bus out of it.
    DBusClient unusedBus() =>
        privateBusClient(DBusAddress.unix(path: '/nonexistent/bus'));
    expect(
      waylandFocusSourceFor(LinuxFocusDesktop.sway, env),
      isA<SwayFocusSource>(),
    );
    expect(
      waylandFocusSourceFor(LinuxFocusDesktop.hyprland, env),
      isA<HyprlandFocusSource>(),
    );
    expect(
      waylandFocusSourceFor(LinuxFocusDesktop.niri, env),
      isA<NiriFocusSource>(),
    );
    expect(
      waylandFocusSourceFor(LinuxFocusDesktop.kde, env, sessionBus: unusedBus),
      isA<KWinFocusSource>(),
    );
    expect(
      waylandFocusSourceFor(
        LinuxFocusDesktop.gnome,
        env,
        sessionBus: unusedBus,
      ),
      isA<GnomeShellFocusSource>(),
    );
    expect(waylandFocusSourceFor(LinuxFocusDesktop.x11, env), isNull);
    expect(waylandFocusSourceFor(LinuxFocusDesktop.otherWayland, env), isNull);
  });

  test('inside Flatpak the KWin script goes where the host can read it', () {
    expect(
      kwinScriptDirectory({
        'FLATPAK_ID': 'de.whispaste.app',
        'XDG_RUNTIME_DIR': '/run/user/1000',
      })!.path,
      '/run/user/1000/app/de.whispaste.app',
    );
    expect(kwinScriptDirectory({'XDG_RUNTIME_DIR': '/run/user/1000'}), isNull);
  });

  group('terminal detection by Wayland app id', () {
    test('Wayland-only and reverse-DNS terminals count', () {
      for (final id in [
        'foot',
        'com.mitchellh.ghostty',
        'org.gnome.Ptyxis',
        'app.devsuite.Ptyxis',
        'org.gnome.Console',
        'org.kde.konsole',
      ]) {
        expect(
          isLinuxTerminalFocus(FocusedTarget.from([id], source: 's')!),
          isTrue,
          reason: id,
        );
      }
    });

    test('any of the names may match; browsers do not', () {
      expect(
        isLinuxTerminalFocus(
          FocusedTarget.from([
            'Gnome-terminal',
            'gnome-terminal-server',
          ], source: 's')!,
        ),
        isTrue,
      );
      expect(
        isLinuxTerminalFocus(
          FocusedTarget.from(['firefox', 'org.mozilla.firefox'], source: 's')!,
        ),
        isFalse,
      );
    });
  });

  group('LinuxDesktopPasteController with a Wayland source', () {
    const channel = MethodChannel('com.whispaste.desktop_paste');
    late List<MethodCall> calls;

    void host({String? nativeTarget}) {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'captureTarget' => true,
              'getTargetBundleId' => nativeTarget,
              _ => {'status': 'success'},
            };
          });
    }

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test(
      'the compositor answer wins and decides the terminal shortcut',
      () async {
        host(nativeTarget: null);
        final source = _Source(FocusedTarget.from(['foot'], source: 'sway'));
        final controller = LinuxDesktopPasteController(waylandFocus: source);

        await controller.capturePasteTarget();
        expect(await controller.getTargetBundleId(), 'foot');
        await controller.pasteClipboard(delay: Duration.zero);

        expect(source.calls, 1, reason: 'asked once, at capture time');
        final paste = calls.singleWhere((c) => c.method == 'pasteClipboard');
        expect((paste.arguments as Map)['shift'], isTrue);
      },
    );

    test(
      'falls back to the native X11 target when the compositor is silent',
      () async {
        host(nativeTarget: 'firefox');
        final controller = LinuxDesktopPasteController(
          waylandFocus: _Source(null),
        );

        await controller.capturePasteTarget();

        expect(await controller.getTargetBundleId(), 'firefox');
        final target = await controller.capturedTarget();
        expect(target!.source, 'x11');
      },
    );

    test('"always Ctrl+Shift+V" applies without asking anyone', () async {
      host(nativeTarget: 'firefox');
      final source = _Source(FocusedTarget.from(['firefox'], source: 'kwin'));
      var always = true;
      final controller = LinuxDesktopPasteController(
        waylandFocus: source,
        alwaysShift: () => always,
      );

      await controller.pasteClipboard(delay: Duration.zero);
      always = false;
      await controller.pasteClipboard(delay: Duration.zero);

      final pastes = calls.where((c) => c.method == 'pasteClipboard');
      expect(
        [for (final p in pastes) (p.arguments as Map)['shift']],
        [true, false],
      );
    });

    test('no source and no native target: unknown, plain Ctrl+V', () async {
      host(nativeTarget: null);
      final controller = LinuxDesktopPasteController(
        waylandFocus: _Source(null),
      );
      await controller.capturePasteTarget();
      await controller.pasteClipboard(delay: Duration.zero);

      expect(await controller.getTargetBundleId(), isNull);
      final paste = calls.singleWhere((c) => c.method == 'pasteClipboard');
      expect((paste.arguments as Map)['shift'], isFalse);
    });
  });
}
