/// The whole Input Monitoring path on macOS in one chain (#1180), with the
/// system grant simulated by a mocked host channel: a double tap is chosen,
/// the grant is missing, it is granted while the app runs, the double tap
/// starts a dictation, the grant is withdrawn and one notice follows.
///
/// The single steps have their own tests (`input_monitoring_status_test`,
/// `trigger_step_test`, `hotkey_observer_health_test`); this one checks that
/// they hand over to each other. Real here: [ModifierKeyMonitor] (reading the
/// host's replies), [HotkeyService], [InputMonitoringAccessNotifier], the row
/// status and [RecordingTriggerHandler]. Simulated: the macOS host behind
/// `com.whispaste.modifier_monitor`. What macOS itself does with a real grant
/// (does a running event tap see it without a restart) no test here can show;
/// the maintainer decided against a VM for that (2026-11-23).
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/hotkey_heal_notice.dart';
import 'package:whispaste/services/hotkey_observer_health.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/input_monitoring_offer.dart'
    show inputMonitoringMonitorProvider;
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/services/permissions/input_monitoring_status.dart';
import 'package:whispaste/services/permissions/permissions_overview_provider.dart'
    show PermissionOverviewStatus;
import 'package:whispaste/services/recording_trigger_handler.dart';

class _Registrar implements HotKeyRegistrar {
  final List<HotKey> registered = [];

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async => registered.add(hotKey);

  @override
  Future<void> unregister(HotKey hotKey) async =>
      registered.removeWhere((k) => k.identifier == hotKey.identifier);
}

class _Settings extends SettingsNotifier {
  _Settings(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// The macOS host as the app sees it: the grant, and what was asked of it.
class _Host {
  bool granted = false;
  int prompts = 0;
  final List<String> started = [];
}

const _channel = MethodChannel('com.whispaste.modifier_monitor');
const _key = ModifierHotkey.rightAlt;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Host host;
  late _Registrar registrar;
  late HotkeyService service;
  late ProviderContainer container;
  late int dictations;
  var now = DateTime(2026, 11, 23, 12);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    host = _Host();
    registrar = _Registrar();
    dictations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'status':
              return {'listenAccess': host.granted, 'tapActive': true};
            case 'requestListenAccess':
              // macOS shows its prompt; the answer comes later, in System
              // Settings, so the grant stays as it is for now.
              host.prompts++;
              return host.granted;
            case 'start':
              host.started.add((call.arguments as Map)['key'] as String);
              return host.granted;
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  });

  /// Starts the app parts with [settings], wired like `service_bootstrap`:
  /// the hotkey's presses feed the trigger handler, which counts dictations.
  Future<void> start(AppSettings settings) async {
    final monitor = ModifierKeyMonitor(isMacOS: true, channel: _channel);
    service = HotkeyService()
      ..injectRegistrar(registrar)
      ..injectMonitor(NoopKeyboardUpMonitor())
      ..injectModifierMonitor(monitor)
      ..injectHealEnvironment(
        hotkeyEnabled: () => true,
        dictationBusy: () => false,
      );
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(settings)),
        hotkeyServiceProvider.overrideWith(() => service),
        inputMonitoringMonitorProvider.overrideWithValue(
          ModifierKeyMonitor(isMacOS: true, channel: _channel),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Keep the status provider alive, as the open permissions overview does.
    container.listen(inputMonitoringStatusProvider, (_, _) {});
    await container.read(settingsProvider.future);
    container.read(hotkeyServiceProvider);
    final handler = RecordingTriggerHandler(
      startRecording: () async => dictations++,
      stopRecording: () async {},
      toggleRecording: () async => dictations++,
      pushToTalkEnabled: () => false,
      registrarSupportsKeyUp: () => true,
      doubleTapEnabled: () => true,
      doubleTapLatches: () => true,
      singleKey: () => true,
      clock: () => now,
    );
    service
      ..onHotkeyPressed = handler.onKeyDown
      ..onHotkeyReleased = handler.onKeyUp;
    await pumpEventQueue();
  }

  /// One key event from the host's event tap, as the real tap sends it.
  Future<void> tapEvent(String type) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _channel.codec.encodeMethodCall(
            MethodCall('event', {'type': type, 'key': _key.name}),
          ),
          (_) {},
        );
  }

  /// Two short taps of the single key, 50 ms each, 150 ms apart.
  Future<void> doubleTap() async {
    for (var i = 0; i < 2; i++) {
      await tapEvent('down');
      now = now.add(const Duration(milliseconds: 50));
      await tapEvent('up');
      now = now.add(const Duration(milliseconds: 150));
    }
    await pumpEventQueue();
  }

  PermissionOverviewStatus row() =>
      container.read(inputMonitoringStatusProvider);
  bool fallback() => container.read(doubleTapFallbackActiveProvider);
  HotkeyObserverLoss? notice() =>
      container.read(hotkeyObserverLostNoticeProvider);
  InputMonitoringAccessNotifier access() =>
      container.read(inputMonitoringAccessProvider.notifier);

  test('fresh install: choose the double tap, grant while running, dictate, '
      'then a withdrawn grant raises one notice', () async {
    // Fresh install with the default combination: nothing is needed, nothing
    // is asked.
    await start(AppSettings.defaults);
    await access().check();
    expect(row(), PermissionOverviewStatus.notNeeded);
    expect(host.prompts, 0);

    // The onboarding sets the double tap of one key.
    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            hotkey: s.hotkey.copyWith(
              hotkeyEnabled: true,
              hotkeyDoubleTapKey: _key.name,
            ),
          ),
        );
    await pumpEventQueue();
    // Without the grant the tap is not even started (the monitor reads the
    // grant first): the stored combination listens, the row names the gap.
    expect(host.started, isEmpty);
    expect(fallback(), isTrue);
    expect(registrar.registered, hasLength(1));
    expect(row(), PermissionOverviewStatus.missing);

    // "Grant access": the system prompt, the grant still missing.
    await access().request();
    expect(host.prompts, 1);
    expect(row(), PermissionOverviewStatus.missing);

    // Granted in System Settings; the next read (the overview's poll or the
    // wait after "Grant access") brings it in without a restart.
    host.granted = true;
    await access().check();
    await pumpEventQueue();
    expect(row(), PermissionOverviewStatus.granted);
    expect(host.started, [_key.name]);
    expect(fallback(), isFalse);
    expect(registrar.registered, isEmpty);

    // The double tap starts a dictation.
    await doubleTap();
    expect(dictations, 1);

    // The grant is withdrawn: the next health check finds it.
    host.granted = false;
    await service.checkObserverHealth();
    await pumpEventQueue();
    expect(row(), PermissionOverviewStatus.missing);
    expect(notice()?.reason, ObserverLossReason.permissionRevoked);
    expect(fallback(), isTrue);
    expect(registrar.registered, hasLength(1));

    // One notice only: later checks add none.
    final first = notice();
    await service.checkObserverHealth();
    await service.checkObserverHealth();
    expect(identical(notice(), first), isTrue);

    // Granted again: the double tap takes over without a restart.
    host.granted = true;
    await access().check();
    await pumpEventQueue();
    expect(row(), PermissionOverviewStatus.granted);
    expect(fallback(), isFalse);
    expect(registrar.registered, isEmpty);
    now = now.add(const Duration(seconds: 2));
    await doubleTap();
    expect(dictations, 2);
  });

  test(
    'an existing user with the grant sees no prompt after the update',
    () async {
      host.granted = true;
      await start(
        AppSettings(
          hotkey: HotkeySettings(
            hotkeyEnabled: true,
            hotkeyDoubleTapKey: _key.name,
          ),
        ),
      );
      await access().check();

      expect(host.prompts, 0);
      expect(row(), PermissionOverviewStatus.granted);
      expect(host.started, [_key.name]);
      expect(fallback(), isFalse);
      expect(notice(), isNull);
      await doubleTap();
      expect(dictations, 1);
    },
  );
}
