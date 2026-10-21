/// XP-2-06: the Wayland portal binding outcome drives the main hotkey's
/// registration status, so an unbound hotkey is never shown as working.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';

class _Registrar implements HotKeyRegistrar {
  bool fail = false;

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    if (fail) throw StateError('taken');
  }

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

class _Monitor implements KeyboardUpMonitor {
  _Monitor(this._binding);

  WaylandHotkeyBinding _binding;
  VoidCallback? _onChanged;
  final List<String?> descriptions = [];

  @override
  bool get supportsKeyUp => false;

  @override
  bool get experimental => false;

  @override
  Future<void> start(HotKey hotKey, {String? description}) async =>
      descriptions.add(description);

  @override
  Future<void> armRelease() async {}

  @override
  Future<void> stop() async {}

  @override
  set onKeyUp(VoidCallback? handler) {}

  @override
  set onKeyDown(VoidCallback? handler) {}

  @override
  WaylandHotkeyBinding get waylandBinding => _binding;

  @override
  set onWaylandBindingChanged(VoidCallback? handler) => _onChanged = handler;

  void emit(WaylandHotkeyBinding binding) {
    _binding = binding;
    _onChanged?.call();
  }
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late HotkeyService service;
  late _Registrar registrar;

  _Monitor setUpWith(WaylandHotkeyBinding initial) {
    final monitor = _Monitor(initial);
    container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(_Settings.new)],
    );
    addTearDown(container.dispose);
    service = container.read(hotkeyServiceProvider.notifier);
    registrar = _Registrar();
    service.injectRegistrar(registrar);
    service.injectMonitor(monitor);
    return monitor;
  }

  HotkeyRegistrationStatus status() =>
      container.read(hotkeyRegistrationStatusProvider);

  WaylandHotkeyBinding binding() =>
      container.read(waylandHotkeyBindingProvider);

  Future<void> register() => service.updateHotkey(key: LogicalKeyboardKey.keyD);

  test('X11 / other platforms stay plain success', () async {
    setUpWith(WaylandHotkeyBinding.notApplicable);
    await register();

    expect(status(), HotkeyRegistrationStatus.success);
    expect(binding(), WaylandHotkeyBinding.notApplicable);
  });

  for (final unbound in [
    WaylandHotkeyBinding.noAppId,
    WaylandHotkeyBinding.unavailable,
    WaylandHotkeyBinding.declined,
  ]) {
    test('${unbound.name} at start → waylandUnbound', () async {
      setUpWith(unbound);
      await register();

      expect(status(), HotkeyRegistrationStatus.waylandUnbound);
      expect(binding(), unbound);
    });
  }

  test('pending stays success until the desktop answers', () async {
    final monitor = setUpWith(WaylandHotkeyBinding.pending);
    await register();
    expect(status(), HotkeyRegistrationStatus.success);

    monitor.emit(WaylandHotkeyBinding.declined);
    expect(status(), HotkeyRegistrationStatus.waylandUnbound);
    expect(binding(), WaylandHotkeyBinding.declined);

    monitor.emit(WaylandHotkeyBinding.bound);
    expect(status(), HotkeyRegistrationStatus.success);
  });

  test('a conflict is never masked by a Wayland report', () async {
    final monitor = setUpWith(WaylandHotkeyBinding.notApplicable);
    registrar.fail = true;
    await register();
    expect(status(), HotkeyRegistrationStatus.conflict);

    monitor.emit(WaylandHotkeyBinding.declined);
    expect(status(), HotkeyRegistrationStatus.conflict);
  });

  test('the portal gets a localized, neutral shortcut description', () async {
    final monitor = setUpWith(WaylandHotkeyBinding.pending);
    await register();

    // Every start (also the service's own one from the settings) names it.
    expect(monitor.descriptions, isNotEmpty);
    expect(monitor.descriptions, everyElement('WhisPaste dictation'));
  });

  test('reconnect re-runs the portal binding for the current hotkey', () async {
    final monitor = setUpWith(WaylandHotkeyBinding.declined);
    await register();
    expect(status(), HotkeyRegistrationStatus.waylandUnbound);

    monitor._binding = WaylandHotkeyBinding.pending;
    final startsBefore = monitor.descriptions.length;
    await service.reconnectWaylandHotkey();

    expect(monitor.descriptions, hasLength(startsBefore + 1));
    expect(status(), HotkeyRegistrationStatus.success);
    expect(binding(), WaylandHotkeyBinding.pending);
  });
}
