/// V1 Wayland: the Linux setups the user starts by hand, desktop permission
/// for the paste keyboard and the WhisPaste GNOME extension.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/linux_input_setup.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';
import 'package:whispaste/services/desktop_paste/focused_target/gnome_focus_extension.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_portal_input.dart';

import '../../fixtures/test_helpers.dart';

class _FakePortal extends LinuxPortalInput {
  _FakePortal({this.available = true});

  final bool available;
  String answer = 'connected';
  var connects = 0;
  var revoked = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<PortalInputConnectResult> connect() async {
    connects++;
    return PortalInputConnectResult(
      status: PortalInputConnectStatus.fromCode(answer),
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> forgetConsent() async => revoked = true;
}

class _NoFocus implements FocusedTargetSource {
  @override
  String get name => 'none';

  @override
  Future<FocusedTarget?> focusedTarget() async => null;
}

void main() {
  late _FakePortal portal;
  late List<bool> gnomeCalls;
  late bool gnomeAnswer;

  setUp(() {
    portal = _FakePortal();
    gnomeCalls = [];
    gnomeAnswer = true;
  });

  Future<void> pump(
    WidgetTester tester, {
    GnomeExtensionSetup gnome = GnomeExtensionSetup.none,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        SingleChildScrollView(
          child: LinuxInputSetup(
            idPrefix: 'text',
            setGnomeExtension: (on) async {
              gnomeCalls.add(on);
              return gnomeAnswer;
            },
          ),
        ),
        locale: const Locale('en'),
        overrides: [
          desktopPasteControllerProvider.overrideWithValue(
            LinuxDesktopPasteController(
              waylandFocus: _NoFocus(),
              portal: portal,
            ),
          ),
          linuxFocusStatusProvider.overrideWith(
            (ref) async => LinuxFocusStatus.unsupported,
          ),
          gnomeExtensionSetupProvider.overrideWith((ref) async => gnome),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(LinuxInputSetup)));

  String statusOf(WidgetTester tester, String id) =>
      tester.widget<SelectableText>(find.byKey(ValueKey('$id-status'))).data!;

  group('desktop permission (portal)', () {
    testWidgets('asks only on the button and then offers to withdraw', (
      tester,
    ) async {
      await pump(tester);
      expect(portal.connects, 0, reason: 'never asks on its own');

      await tester.tap(
        find.byKey(const ValueKey('text-linux-portal-input-connect')),
      );
      await tester.pumpAndSettle();

      expect(portal.connects, 1);
      expect(
        statusOf(tester, 'text-linux-portal-input'),
        l10n(tester).settingsLinuxPortalInputConnected,
      );
      await tester.tap(
        find.byKey(const ValueKey('text-linux-portal-input-revoke')),
      );
      await tester.pumpAndSettle();
      expect(portal.revoked, isTrue);
      expect(
        find.byKey(const ValueKey('text-linux-portal-input-connect')),
        findsOneWidget,
      );
    });

    testWidgets('a closed dialog says so and keeps the button', (tester) async {
      portal.answer = 'cancelled';
      await pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('text-linux-portal-input-connect')),
      );
      await tester.pumpAndSettle();
      expect(
        statusOf(tester, 'text-linux-portal-input'),
        l10n(tester).settingsLinuxPortalInputCancelled,
      );
      expect(
        find.byKey(const ValueKey('text-linux-portal-input-connect')),
        findsOneWidget,
      );
    });

    testWidgets('hidden where the desktop has no portal keyboard', (
      tester,
    ) async {
      portal = _FakePortal(available: false);
      await pump(tester);
      expect(
        find.byKey(const ValueKey('text-linux-portal-input')),
        findsNothing,
      );
    });
  });

  group('GNOME extension', () {
    testWidgets('installed but off: the button turns it on', (tester) async {
      await pump(tester, gnome: GnomeExtensionSetup.canEnable);
      await tester.tap(
        find.byKey(const ValueKey('text-linux-gnome-extension-enable')),
      );
      await tester.pumpAndSettle();
      expect(gnomeCalls, [true]);
      expect(
        statusOf(tester, 'text-linux-gnome-extension'),
        l10n(tester).settingsLinuxGnomeExtensionRelogin,
      );
      expect(
        find.byKey(const ValueKey('text-linux-gnome-extension-disable')),
        findsOneWidget,
      );
    });

    testWidgets('a failed switch shows the command to run', (tester) async {
      gnomeAnswer = false;
      await pump(tester, gnome: GnomeExtensionSetup.canEnable);
      await tester.tap(
        find.byKey(const ValueKey('text-linux-gnome-extension-enable')),
      );
      await tester.pumpAndSettle();
      expect(
        statusOf(tester, 'text-linux-gnome-extension'),
        contains(gnomeFocusExtensionEnableCommand),
      );
    });

    testWidgets('not installed: a pointer to the manual, no button', (
      tester,
    ) async {
      await pump(tester, gnome: GnomeExtensionSetup.notInstalled);
      expect(
        statusOf(tester, 'text-linux-gnome-extension'),
        l10n(tester).settingsLinuxGnomeExtensionNotInstalled,
      );
      expect(
        find.byKey(const ValueKey('text-linux-gnome-extension-enable')),
        findsNothing,
      );
    });

    testWidgets('running: the consent can be withdrawn', (tester) async {
      await pump(tester, gnome: GnomeExtensionSetup.enabled);
      await tester.tap(
        find.byKey(const ValueKey('text-linux-gnome-extension-disable')),
      );
      await tester.pumpAndSettle();
      expect(gnomeCalls, [false]);
    });

    testWidgets('not GNOME: no row', (tester) async {
      await pump(tester);
      expect(
        find.byKey(const ValueKey('text-linux-gnome-extension')),
        findsNothing,
      );
    });
  });

  group('extension files and switch', () {
    test('finds the per-user and the system-wide copy', () {
      final seen = <String>[];
      bool has(String p) {
        seen.add(p);
        return p ==
            '/usr/share/gnome-shell/extensions/$gnomeFocusExtensionUuid';
      }

      expect(gnomeFocusExtensionInstalled({'HOME': '/h'}, exists: has), isTrue);
      expect(
        seen.first,
        '/h/.local/share/gnome-shell/extensions/$gnomeFocusExtensionUuid',
      );
      expect(
        gnomeFocusExtensionInstalled({
          'HOME': '/h',
          'XDG_DATA_DIRS': '/opt/x',
        }, exists: has),
        isFalse,
      );
    });

    test('a Flatpak cannot see host extensions', () {
      expect(
        gnomeFocusExtensionInstalled({
          'FLATPAK_ID': 'de.whispaste.app',
        }, exists: (_) => true),
        isFalse,
      );
    });

    test('calls gnome-extensions with the UUID; failures are false', () async {
      final args = <List<String>>[];
      Future<ProcessResult> ok(String exe, List<String> a) async {
        args.add([exe, ...a]);
        return ProcessResult(0, 0, '', '');
      }

      expect(await setGnomeFocusExtensionEnabled(true, run: ok), isTrue);
      expect(await setGnomeFocusExtensionEnabled(false, run: ok), isTrue);
      expect(args, [
        ['gnome-extensions', 'enable', gnomeFocusExtensionUuid],
        ['gnome-extensions', 'disable', gnomeFocusExtensionUuid],
      ]);
      expect(
        await setGnomeFocusExtensionEnabled(
          true,
          run: (_, _) async => ProcessResult(0, 2, '', 'no such extension'),
        ),
        isFalse,
      );
      expect(
        await setGnomeFocusExtensionEnabled(
          true,
          run: (_, _) => throw const ProcessException('gnome-extensions', []),
        ),
        isFalse,
      );
    });
  });
}
