/// XP-2-06: the inline notice for an unbound Linux Wayland hotkey — shown in
/// Settings and onboarding, addressed by testID only.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/features/settings/widgets/wayland_hotkey_notice.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';

import '../../fixtures/test_helpers.dart';

class _Status extends HotkeyRegistrationStatusController {
  _Status(this._status);
  final HotkeyRegistrationStatus _status;
  @override
  HotkeyRegistrationStatus build() => _status;
}

class _Binding extends WaylandHotkeyBindingController {
  _Binding(this._binding);
  final WaylandHotkeyBinding _binding;
  @override
  WaylandHotkeyBinding build() => _binding;
}

class _Trigger extends WaylandBoundTriggerController {
  _Trigger(this._trigger);
  final String? _trigger;
  @override
  String? build() => _trigger;
}

class _Settings extends SettingsNotifier {
  _Settings(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

class _HotkeyService extends HotkeyService {
  int reconnects = 0;
  @override
  void build() {}
  @override
  Future<void> reconnectWaylandHotkey() async => reconnects++;
}

const _command = "'/home/a b/whispaste' --toggle";

void main() {
  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  late _HotkeyService service;
  late List<LinuxFocusDesktop> opened;

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    HotkeyRegistrationStatus status = HotkeyRegistrationStatus.waylandUnbound,
    WaylandHotkeyBinding binding = WaylandHotkeyBinding.declined,
    LinuxFocusDesktop? desktop = LinuxFocusDesktop.gnome,
    bool desktopShortcutPending = true,
    bool hotkeyEnabled = true,
    String? boundTrigger,
  }) async {
    service = _HotkeyService();
    opened = [];
    await tester.pumpWidget(
      makeTestable(
        SingleChildScrollView(child: child),
        locale: const Locale('en'),
        overrides: [
          hotkeyRegistrationStatusProvider.overrideWith(() => _Status(status)),
          waylandHotkeyBindingProvider.overrideWith(() => _Binding(binding)),
          hotkeyServiceProvider.overrideWith(() => service),
          waylandBoundTriggerProvider.overrideWith(
            () => _Trigger(boundTrigger),
          ),
          settingsProvider.overrideWith(
            () => _Settings(
              AppSettings(hotkey: HotkeySettings(hotkeyEnabled: hotkeyEnabled)),
            ),
          ),
          manualToggleCommandProvider.overrideWithValue(_command),
          keyboardShortcutSettingsDesktopProvider.overrideWithValue(desktop),
          keyboardShortcutSettingsOpenerProvider.overrideWithValue((d) async {
            opened.add(d);
            return true;
          }),
          desktopShortcutPendingProvider.overrideWithValue(
            desktopShortcutPending,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder id(String testId) => find.byKey(ValueKey(testId));

  group('waylandHotkeyIssueText', () {
    test('each unbound reason has its own explanation', () {
      expect(
        waylandHotkeyIssueText(l10n, WaylandHotkeyBinding.noAppId),
        l10n.waylandHotkeyNoAppId,
      );
      expect(
        waylandHotkeyIssueText(l10n, WaylandHotkeyBinding.unavailable),
        l10n.waylandHotkeyUnavailable,
      );
      expect(
        waylandHotkeyIssueText(l10n, WaylandHotkeyBinding.declined),
        l10n.waylandHotkeyDeclined,
      );
    });
  });

  group('waylandHotkeyNoticeReasonProvider', () {
    ProviderContainer containerWith({
      required HotkeyRegistrationStatus status,
      required WaylandHotkeyBinding binding,
      required bool pending,
    }) {
      final container = ProviderContainer(
        overrides: [
          hotkeyRegistrationStatusProvider.overrideWith(() => _Status(status)),
          waylandHotkeyBindingProvider.overrideWith(() => _Binding(binding)),
          desktopShortcutPendingProvider.overrideWithValue(pending),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('no notice while the hotkey is bound or not Wayland', () {
      final c = containerWith(
        status: HotkeyRegistrationStatus.success,
        binding: WaylandHotkeyBinding.bound,
        pending: false,
      );
      expect(c.read(waylandHotkeyNoticeReasonProvider), isNull);
    });

    test('an app-ID or declined failure always shows its reason', () {
      for (final binding in [
        WaylandHotkeyBinding.noAppId,
        WaylandHotkeyBinding.declined,
      ]) {
        final c = containerWith(
          status: HotkeyRegistrationStatus.waylandUnbound,
          binding: binding,
          pending: false,
        );
        expect(c.read(waylandHotkeyNoticeReasonProvider), binding);
      }
    });

    test('no portal shows only while the desktop shortcut is still open', () {
      final done = containerWith(
        status: HotkeyRegistrationStatus.waylandUnbound,
        binding: WaylandHotkeyBinding.unavailable,
        pending: false,
      );
      expect(done.read(waylandHotkeyNoticeReasonProvider), isNull);

      final open = containerWith(
        status: HotkeyRegistrationStatus.waylandUnbound,
        binding: WaylandHotkeyBinding.unavailable,
        pending: true,
      );
      expect(
        open.read(waylandHotkeyNoticeReasonProvider),
        WaylandHotkeyBinding.unavailable,
      );
    });
  });

  group('keyboardShortcutSettingsCommand', () {
    test('GNOME and KDE open their own keyboard shortcut settings', () {
      // Records compare their list by identity, so check the parts directly.
      final gnome = keyboardShortcutSettingsCommand(LinuxFocusDesktop.gnome)!;
      expect(gnome.$1, 'gnome-control-center');
      expect(gnome.$2, ['keyboard']);
      final kde = keyboardShortcutSettingsCommand(LinuxFocusDesktop.kde)!;
      expect(kde.$1, 'systemsettings');
      expect(kde.$2, ['kcm_keys']);
    });

    test('other desktops have no settings button', () {
      expect(keyboardShortcutSettingsCommand(LinuxFocusDesktop.sway), isNull);
      expect(
        keyboardShortcutSettingsCommand(LinuxFocusDesktop.otherWayland),
        isNull,
      );
    });
  });

  group('WaylandHotkeyNotice', () {
    testWidgets('bound: names the trigger the desktop set, no issue notice', (
      tester,
    ) async {
      await pump(
        tester,
        const WaylandHotkeyNotice(idPrefix: 'settings'),
        status: HotkeyRegistrationStatus.success,
        binding: WaylandHotkeyBinding.bound,
        desktopShortcutPending: false,
        boundTrigger: 'LOGO+space',
      );
      expect(id('settings-wayland-hotkey-notice'), findsNothing);
      expect(id('settings-wayland-hotkey-bound'), findsOneWidget);
      expect(
        find.text(l10n.waylandHotkeyBoundTrigger('LOGO+space')),
        findsOneWidget,
      );
    });

    testWidgets('bound without a delivered trigger says the desktop sets it', (
      tester,
    ) async {
      await pump(
        tester,
        const WaylandHotkeyNotice(idPrefix: 'settings'),
        status: HotkeyRegistrationStatus.success,
        binding: WaylandHotkeyBinding.bound,
        desktopShortcutPending: false,
      );
      expect(id('settings-wayland-hotkey-bound'), findsOneWidget);
      expect(find.text(l10n.waylandHotkeyBoundNoTrigger), findsOneWidget);
    });

    testWidgets('hidden while the hotkey is switched off', (tester) async {
      await pump(
        tester,
        const WaylandHotkeyNotice(idPrefix: 'settings'),
        status: HotkeyRegistrationStatus.success,
        binding: WaylandHotkeyBinding.bound,
        desktopShortcutPending: false,
        boundTrigger: 'LOGO+space',
        hotkeyEnabled: false,
      );
      expect(id('settings-wayland-hotkey-bound'), findsNothing);
      expect(id('settings-wayland-hotkey-notice'), findsNothing);
    });

    testWidgets('explains why and shows the fallback command', (tester) async {
      await pump(
        tester,
        const WaylandHotkeyNotice(idPrefix: 'settings'),
        binding: WaylandHotkeyBinding.noAppId,
      );
      expect(id('settings-wayland-hotkey-notice'), findsOneWidget);
      expect(find.textContaining(l10n.waylandHotkeyNoAppId), findsOneWidget);
      final command = tester.widget<SelectableText>(
        id('settings-wayland-hotkey-command'),
      );
      expect(command.data, _command);
    });

    testWidgets('reconnect asks the desktop again', (tester) async {
      await pump(tester, const WaylandHotkeyNotice(idPrefix: 'settings'));
      await tester.tap(id('settings-wayland-hotkey-reconnect'));
      await tester.pump();
      expect(service.reconnects, 1);
    });

    testWidgets('no-portal notice has reason and settings only', (
      tester,
    ) async {
      await pump(
        tester,
        const WaylandHotkeyNotice(idPrefix: 'settings'),
        binding: WaylandHotkeyBinding.unavailable,
      );
      expect(
        find.textContaining(l10n.waylandHotkeyUnavailable),
        findsOneWidget,
      );
      expect(id('settings-wayland-hotkey-command'), findsNothing);
      expect(id('settings-wayland-hotkey-reconnect'), findsNothing);
      expect(id('settings-wayland-hotkey-copy-command'), findsNothing);
      expect(
        id('settings-wayland-hotkey-open-keyboard-settings'),
        findsOneWidget,
      );
    });

    testWidgets('copy puts the command on the clipboard', (tester) async {
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
      await pump(tester, const WaylandHotkeyNotice(idPrefix: 'settings'));

      await tester.tap(id('settings-wayland-hotkey-copy-command'));
      await tester.pumpAndSettle();

      expect(copied, _command);
      expect(find.text(l10n.waylandHotkeyCommandCopied), findsOneWidget);
    });

    testWidgets('opens the keyboard settings of a known desktop', (
      tester,
    ) async {
      await pump(tester, const WaylandHotkeyNotice(idPrefix: 'settings'));
      await tester.tap(id('settings-wayland-hotkey-open-keyboard-settings'));
      await tester.pump();
      expect(opened, [LinuxFocusDesktop.gnome]);
    });

    testWidgets('no settings button on an unknown desktop', (tester) async {
      await pump(
        tester,
        const WaylandHotkeyNotice(idPrefix: 'settings'),
        desktop: null,
      );
      expect(
        id('settings-wayland-hotkey-open-keyboard-settings'),
        findsNothing,
      );
    });
  });

  group('placement', () {
    testWidgets('Settings › hotkey section carries the notice', (tester) async {
      await pump(tester, const KeyboardShortcutSection());
      expect(id('settings-wayland-hotkey-notice'), findsOneWidget);
    });

    testWidgets('onboarding hotkey step carries the notice', (tester) async {
      await pump(tester, const TriggerStep());
      expect(id('onboarding-wayland-hotkey-notice'), findsOneWidget);
    });
  });
}
