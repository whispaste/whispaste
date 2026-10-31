/// V1 Wayland: the hotkey block for desktops without the GlobalShortcuts
/// portal — add to GNOME, remove again, or copy the command by hand.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/linux_desktop_shortcut_block.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';

import '../../fixtures/test_helpers.dart';

/// `gsettings` over a map; only the custom keybinding list matters here.
class _Dconf {
  String list = "['/custom0/']";
  bool fail = false;

  Future<ProcessResult> call(String executable, List<String> args) async {
    if (fail) return ProcessResult(0, 1, '', 'dconf refused');
    if (args[2] == GnomeToggleShortcut.listKey) {
      if (args[0] == 'get') return ProcessResult(0, 0, list, '');
      if (args[0] == 'set') list = args[3];
    }
    return ProcessResult(0, 0, '', '');
  }

  bool get installed =>
      parseGvStringList(list).contains(GnomeToggleShortcut.entryPath);
}

void main() {
  late Directory dir;
  late _Dconf dconf;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_shortcut_block_');
    dconf = _Dconf();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester,
    DesktopShortcutFallback fallback, {
    Locale locale = const Locale('en'),
    Size size = const Size(1280, 800),
  }) async {
    await tester.pumpWidget(
      makeTestable(
        SingleChildScrollView(
          // Pinned to Ctrl+Shift: the default is Cmd on macOS, so the bare
          // defaults would make this test depend on the host.
          child: LinuxDesktopShortcutBlock(
            settings: AppSettings.defaults.copyWith(
              hotkeyModifiers: 'ctrl+shift',
            ),
          ),
        ),
        locale: locale,
        size: size,
        overrides: [
          linuxDesktopShortcutHostProvider.overrideWithValue(true),
          desktopShortcutFallbackProvider.overrideWith((ref) async => fallback),
          gnomeToggleShortcutProvider.overrideWithValue(
            GnomeToggleShortcut(
              run: dconf.call,
              launcherPath: '${dir.path}/toggle.sh',
              signalFile: '/s/focus.signal',
              executable: '/usr/bin/whispaste',
            ),
          ),
          manualToggleCommandProvider.overrideWithValue(
            "'/usr/bin/whispaste' --toggle",
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndWait(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey(id)));
    // The launcher is a real file write: let real time pass for the I/O,
    // then deliver its callbacks in the test zone.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('general-desktop-shortcut-text')))
      .data!;

  testWidgets('GNOME without the portal: add, then remove again', (
    tester,
  ) async {
    await pump(tester, DesktopShortcutFallback.gnome);
    expect(text(tester), contains('GNOME keyboard shortcuts instead'));
    expect(text(tester), contains('Ctrl'));

    await tapAndWait(tester, 'general-desktop-shortcut-add');

    expect(dconf.installed, isTrue);
    expect(text(tester), contains('is set up in the GNOME keyboard'));
    expect(
      find.byKey(const ValueKey('general-desktop-shortcut-add')),
      findsNothing,
    );

    await tapAndWait(tester, 'general-desktop-shortcut-remove');

    expect(dconf.installed, isFalse);
    expect(
      find.byKey(const ValueKey('general-desktop-shortcut-add')),
      findsOneWidget,
    );
  });

  testWidgets('a refused change says so instead of pretending', (tester) async {
    await pump(tester, DesktopShortcutFallback.gnome);
    dconf.fail = true;

    await tapAndWait(tester, 'general-desktop-shortcut-add');

    expect(
      find.byKey(const ValueKey('general-desktop-shortcut-failed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('general-desktop-shortcut-add')),
      findsOneWidget,
    );
  });

  testWidgets('an installed shortcut can be removed even with the portal', (
    tester,
  ) async {
    dconf.list = "['${GnomeToggleShortcut.entryPath}']";
    await pump(tester, DesktopShortcutFallback.notNeeded);

    expect(
      find.byKey(const ValueKey('general-desktop-shortcut-remove')),
      findsOneWidget,
    );
  });

  testWidgets('other desktops get the command and a copy button', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester, DesktopShortcutFallback.manual);

    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('general-desktop-shortcut-command')),
          )
          .data,
      "'/usr/bin/whispaste' --toggle",
    );
    await tester.tap(
      find.byKey(const ValueKey('general-desktop-shortcut-copy')),
    );
    await tester.pumpAndSettle();
    expect(copied, "'/usr/bin/whispaste' --toggle");
    // Let the confirmation toast run out.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('nothing to show where the hotkey works on its own', (
    tester,
  ) async {
    await pump(tester, DesktopShortcutFallback.notNeeded);
    expect(
      find.byKey(const ValueKey('general-desktop-shortcut')),
      findsNothing,
    );
  });
}
