/// XP-2-06: the Wayland portal binding outcome drives the main hotkey's
/// registration status, so an unbound hotkey is never shown as working.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hotkey_self_heal.dart';
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
  Future<bool> armRelease({
    Iterable<HotKeyModifier> modifiers = const [],
  }) async => true;

  @override
  Future<void> stop() async {}

  @override
  set onKeyUp(ValueChanged<Duration?>? handler) {}

  @override
  set onKeyDown(VoidCallback? handler) {}

  @override
  WaylandHotkeyBinding get waylandBinding => _binding;

  @override
  String? get waylandTrigger => null;

  @override
  set onWaylandBindingChanged(VoidCallback? handler) => _onChanged = handler;

  void emit(WaylandHotkeyBinding binding) {
    _binding = binding;
    _onChanged?.call();
  }
}

class _Settings extends SettingsNotifier {
  _Settings({this.onboardingCompleted = false});

  final bool onboardingCompleted;

  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    onboarding: AppSettings.defaults.onboarding.copyWith(
      onboardingCompleted: onboardingCompleted,
    ),
  );

  @override
  Future<void> updateSettings(
    AppSettings Function(AppSettings) updater,
  ) async => state = AsyncData(updater(state.requireValue));
}

const _wayland = {'XDG_SESSION_TYPE': 'wayland'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late HotkeyService service;
  late _Registrar registrar;

  _Monitor setUpWith(
    WaylandHotkeyBinding initial, {
    Map<String, String> environment = const {},
    bool onboardingCompleted = false,
  }) {
    final monitor = _Monitor(initial);
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _Settings(onboardingCompleted: onboardingCompleted),
        ),
      ],
    );
    addTearDown(container.dispose);
    service = container.read(hotkeyServiceProvider.notifier);
    registrar = _Registrar();
    service.injectRegistrar(registrar);
    service.injectMonitor(monitor);
    service.injectEnvironment(environment);
    return monitor;
  }

  HotkeyRegistrationStatus status() =>
      container.read(hotkeyRegistrationStatusProvider);

  WaylandHotkeyBinding binding() =>
      container.read(waylandHotkeyBindingProvider);

  // The startup registration from the settings runs concurrently with the
  // test's own; let it settle so the test sees one final, deterministic state.
  Future<void> register() async {
    await service.updateHotkey(key: LogicalKeyboardKey.keyD);
    await pumpEventQueue();
  }

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

  group(
    'first run on Wayland: the desktop dialog waits for the hotkey page',
    () {
      Future<void> registerLoaded() async {
        await container.read(settingsProvider.future);
        await register();
      }

      test(
        'no binding request while the onboarding has not explained it',
        () async {
          final monitor = setUpWith(
            WaylandHotkeyBinding.pending,
            environment: _wayland,
          );
          await registerLoaded();

          expect(monitor.descriptions, isEmpty);
        },
      );

      test('the hotkey page lets the held-back request through once', () async {
        final monitor = setUpWith(
          WaylandHotkeyBinding.pending,
          environment: _wayland,
        );
        await registerLoaded();

        await service.allowDesktopHotkeyBinding();
        await service.allowDesktopHotkeyBinding();

        expect(monitor.descriptions, hasLength(1));
      });

      test('completing or closing the onboarding sends the request', () async {
        final monitor = setUpWith(
          WaylandHotkeyBinding.pending,
          environment: _wayland,
        );
        await registerLoaded();

        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                onboarding: s.onboarding.copyWith(onboardingCompleted: true),
              ),
            );
        await pumpEventQueue();

        expect(monitor.descriptions, hasLength(1));
      });

      test('a completed onboarding binds at startup as before', () async {
        final monitor = setUpWith(
          WaylandHotkeyBinding.pending,
          environment: _wayland,
          onboardingCompleted: true,
        );
        await registerLoaded();

        expect(monitor.descriptions, isNotEmpty);
      });

      test('outside Wayland the monitor starts right away', () async {
        final monitor = setUpWith(WaylandHotkeyBinding.notApplicable);
        await registerLoaded();

        expect(monitor.descriptions, isNotEmpty);
      });
    },
  );

  for (final state in [
    WaylandHotkeyBinding.pending,
    WaylandHotkeyBinding.bound,
    WaylandHotkeyBinding.declined,
  ]) {
    test('a self-heal never asks the desktop again (${state.name})', () async {
      final monitor = setUpWith(state);
      await register();
      final startsBefore = monitor.descriptions.length;

      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);

      expect(monitor.descriptions, hasLength(startsBefore));
      expect(
        status(),
        state.isUnbound
            ? HotkeyRegistrationStatus.waylandUnbound
            : HotkeyRegistrationStatus.success,
      );
    });
  }

  test('a declined binding is asked again only by an explicit click', () {
    fakeAsync((async) {
      final monitor = setUpWith(WaylandHotkeyBinding.declined);
      service.injectHealClock(async.getClock(DateTime(2026, 10, 30)).now);
      unawaited(register());
      async.elapse(const Duration(milliseconds: 1));
      final startsBefore = monitor.descriptions.length;

      // Several timer heals pass; none of them may open a system dialog.
      async.elapse(kHotkeyHealInterval * 3);
      expect(monitor.descriptions, hasLength(startsBefore));
      expect(status(), HotkeyRegistrationStatus.waylandUnbound);

      // "Neu verbinden" is the only way back to the desktop's dialog.
      unawaited(service.reconnectWaylandHotkey());
      async.elapse(const Duration(milliseconds: 1));
      expect(monitor.descriptions, hasLength(startsBefore + 1));
    });
  });
}
