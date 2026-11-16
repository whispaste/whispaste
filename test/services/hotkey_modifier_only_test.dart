/// Tests for the modifier-only global hotkey routing in [HotkeyService].
///
/// [HotkeyService] picks its native observer by host: macOS uses
/// [ModifierKeyMonitor], Windows and Linux use the keyboard-monitor channel
/// through [ChannelKeyboardUpMonitor]. Each group below runs only on the host
/// whose path it covers, so the suite passes on every runner. The combo
/// registrar is [FakeHotKeyRegistrar] so no hotkey channel is touched.
library;

import 'dart:async' show Completer, unawaited;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugDefaultTargetPlatformOverride,
        defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/globe_key_action.dart';
import 'package:whispaste/services/hotkey_observer_health.dart';
import 'package:whispaste/services/hotkey_self_heal.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/services/settings_portability_service.dart';
import 'package:whispaste/services/short_press_hint.dart';

class FakeHotKeyRegistrar implements HotKeyRegistrar {
  final List<HotKey> registered = [];

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }
}

class FakeModifierKeyMonitor implements ModifierKeyMonitor {
  FakeModifierKeyMonitor({this.startResult = true});

  bool startResult;

  /// When set, [start] answers only after this future completes, like a
  /// native reply that is still outstanding.
  Future<void>? startGate;
  final List<ModifierHotkey> started = [];
  int stopCount = 0;

  @override
  ModifierInputHandler? onInput;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<bool?> listenAccess() async => true;

  @override
  Future<GlobeKeyAction> globeKeyAction() async => GlobeKeyAction.none;

  @override
  Future<bool> start(ModifierHotkey key) async {
    started.add(key);
    await startGate;
    return startResult;
  }

  @override
  Future<void> stop() async => stopCount++;

  /// What the host says about its observer (#773).
  ObserverHealth healthNow = ObserverHealth.healthy;

  @override
  Future<ObserverHealth> health() async => healthNow;

  @override
  bool supportsHeld = false;

  /// What the hardware read says; null unknown. [heldKeyCodes] records the
  /// key code each read was given.
  bool? heldNow;
  final List<int?> heldKeyCodes = [];

  @override
  Future<bool?> isHeld({int? keyCode}) async {
    heldKeyCodes.add(keyCode);
    return heldNow;
  }

  @override
  Duration? lastEventAt;

  @override
  Duration? lastPressed;

  @override
  Future<void> handleNativeCall(MethodCall call) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHotKeyRegistrar registrar;
  late HotkeyService service;
  late int pressed;
  late int released;
  late int otherKey;

  void wireCallbacks() {
    pressed = 0;
    released = 0;
    otherKey = 0;
    service.onHotkeyPressed = () {
      pressed++;
    };
    service.onHotkeyReleased = () {
      released++;
    };
    service.onModifierOtherKey = () {
      otherKey++;
    };
  }

  group('macOS observer (fake ModifierKeyMonitor)', () {
    late FakeModifierKeyMonitor monitor;

    setUp(() {
      registrar = FakeHotKeyRegistrar();
      monitor = FakeModifierKeyMonitor();
      service = HotkeyService()
        ..injectRegistrar(registrar)
        ..injectMonitor(NoopKeyboardUpMonitor())
        ..injectModifierMonitor(monitor);
      wireCallbacks();
    });

    test('the service hands out the observer stamp, none outside an event', () {
      expect(service.nativeEventAt, isNull);
      expect(service.nativePressed, isNull);

      monitor.lastEventAt = const Duration(milliseconds: 5300);
      monitor.lastPressed = const Duration(milliseconds: 300);
      expect(service.nativeEventAt, const Duration(milliseconds: 5300));
      expect(service.nativePressed, const Duration(milliseconds: 300));
    });

    test('starts the observer and registers no key combination', () async {
      _pin(TargetPlatform.macOS);
      final started = await service.registerModifierOnly(
        ModifierHotkey.rightControl,
      );

      expect(started, isTrue);
      expect(monitor.started, [ModifierHotkey.rightControl]);
      expect(registrar.registered, isEmpty);
    });

    test(
      'a modifier press starts and its release stops the global action',
      () async {
        _pin(TargetPlatform.macOS);
        await service.registerModifierOnly(ModifierHotkey.rightAlt);

        monitor.onInput!(ModifierInput.down, null);
        monitor.onInput!(ModifierInput.up, null);

        expect(pressed, 1);
        expect(released, 1);
      },
    );

    test('a held modifier whose release was lost ends the press from the real '
        'key state, read without a key code (#791)', () {
      _pin(TargetPlatform.macOS);
      fakeAsync((async) {
        monitor.supportsHeld = true;
        unawaited(service.registerModifierOnly(ModifierHotkey.fn));
        async.flushMicrotasks();

        monitor.onInput!(ModifierInput.down, null);
        monitor.heldNow = true;
        async.elapse(kHotkeyHeldProbeInterval * 2);
        expect(released, 0);

        monitor.heldNow = false;
        async.elapse(kHotkeyHeldProbeInterval);
        expect(released, 1);
        expect(monitor.heldKeyCodes, everyElement(isNull));
      });
    });

    test(
      'another key while the modifier is held is routed as other, not as a press',
      () async {
        _pin(TargetPlatform.macOS);
        await service.registerModifierOnly(ModifierHotkey.rightMeta);

        monitor.onInput!(ModifierInput.down, null);
        monitor.onInput!(ModifierInput.other, null);

        expect(pressed, 1);
        expect(otherKey, 1);
        expect(released, 0);
      },
    );

    test(
      'reports false and keeps the combination when the platform cannot observe the key',
      () async {
        _pin(TargetPlatform.macOS);
        monitor.startResult = false;

        final started = await service.registerModifierOnly(ModifierHotkey.fn);

        expect(started, isFalse);
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'switching back to a combination stops the modifier observer',
      () async {
        _pin(TargetPlatform.macOS);
        await service.registerModifierOnly(ModifierHotkey.rightControl);

        await service.updateHotkey(key: LogicalKeyboardKey.keyR);

        expect(monitor.stopCount, greaterThanOrEqualTo(1));
      },
    );
  });

  group('Windows/Linux channel (mocked keyboard-monitor channel)', () {
    const channel = MethodChannel('com.whispaste.keyboard_monitor');
    late List<Object?> watchCalls;
    late bool watchReply;
    late FakeModifierKeyMonitor macMonitor;
    var channelStops = 0;

    Future<void> nativeCall(String method) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method)),
            (_) {},
          );
    }

    setUp(() {
      registrar = FakeHotKeyRegistrar();
      watchCalls = [];
      watchReply = true;
      channelStops = 0;
      macMonitor = FakeModifierKeyMonitor();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'watchModifier':
                watchCalls.add(call.arguments);
                return watchReply;
              case 'stop':
                channelStops++;
                return null;
              default:
                return null;
            }
          });
      service = HotkeyService()
        ..injectRegistrar(registrar)
        ..injectMonitor(
          ChannelKeyboardUpMonitor(isWindows: true, isLinux: false),
        )
        ..injectModifierMonitor(macMonitor);
      wireCallbacks();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'asks the host to watch the key and registers no key combination',
      () async {
        _pin(TargetPlatform.windows);
        final started = await service.registerModifierOnly(
          ModifierHotkey.rightControl,
        );

        expect(started, isTrue);
        expect(watchCalls, [
          {'key': ModifierHotkey.rightControl.name},
        ]);
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a modifier press from the host starts and its release stops the global action',
      () async {
        _pin(TargetPlatform.windows);
        await service.registerModifierOnly(ModifierHotkey.rightAlt);

        await nativeCall('onModifierDown');
        await nativeCall('onModifierUp');

        expect(pressed, 1);
        expect(released, 1);
      },
    );

    test(
      'another key while the modifier is held is routed as other, not as a press',
      () async {
        _pin(TargetPlatform.windows);
        await service.registerModifierOnly(ModifierHotkey.rightMeta);

        await nativeCall('onModifierDown');
        await nativeCall('onOtherKey');

        expect(pressed, 1);
        expect(otherKey, 1);
        expect(released, 0);
      },
    );

    test('reports false when the host refuses the key', () async {
      _pin(TargetPlatform.windows);
      watchReply = false;

      final started = await service.registerModifierOnly(
        ModifierHotkey.rightControl,
      );

      expect(started, isFalse);
      expect(registrar.registered, isEmpty);
    });

    test(
      'replacing a channel watch stops the channel, not the macOS observer',
      () async {
        _pin(TargetPlatform.windows);
        await service.registerModifierOnly(ModifierHotkey.rightControl);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(channelStops, greaterThanOrEqualTo(1));
        expect(macMonitor.stopCount, 0);
      },
    );

    test(
      'Fn is refused without asking the host, since only macOS can observe it',
      () async {
        _pin(TargetPlatform.windows);
        final started = await service.registerModifierOnly(ModifierHotkey.fn);

        expect(started, isFalse);
        expect(watchCalls, isEmpty);
      },
    );
  });

  group('short-press hint from a modifier release (F15-4)', () {
    const channel = MethodChannel('com.whispaste.keyboard_monitor');
    late FakeModifierKeyMonitor macMonitor;

    setUp(() {
      registrar = FakeHotKeyRegistrar();
      macMonitor = FakeModifierKeyMonitor();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'watchModifier' ? true : null,
          );
      service = HotkeyService()
        ..injectRegistrar(registrar)
        ..injectMonitor(
          ChannelKeyboardUpMonitor(isWindows: true, isLinux: false),
        )
        ..injectModifierMonitor(macMonitor);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    /// Delivers one input the way this platform's host does.
    Future<void> emit(ModifierInput input, {int? pressMs}) async {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        macMonitor.onInput!(
          input,
          pressMs == null ? null : Duration(milliseconds: pressMs),
        );
        return;
      }
      final method = input == ModifierInput.down
          ? 'onModifierDown'
          : 'onModifierUp';
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall(method, pressMs == null ? null : {'pressMs': pressMs}),
            ),
            (_) {},
          );
    }

    /// Hold-to-talk on a modifier key. Down and up reach Dart at the same
    /// instant, as after a stalled UI thread; only the host's [pressMs] says
    /// how long the key was really held.
    Future<bool> hintAfterRelease(int? pressMs) async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _MutableSettings(
              const AppSettings(
                audioInput: AudioInputSettings(pushToTalk: true),
              ),
            ),
          ),
          hotkeyServiceProvider.overrideWith(() => service),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      expect(await service.registerModifierOnly(ModifierHotkey.rightAlt), true);

      await emit(ModifierInput.down);
      await emit(ModifierInput.up, pressMs: pressMs);
      return container.read(shortPressHintProvider);
    }

    test('a hold the host timed as long shows no hint', () async {
      expect(await hintAfterRelease(400), isFalse);
    });

    test('a click the host timed as short shows the hint', () async {
      expect(await hintAfterRelease(20), isTrue);
    });

    test('a release without a length shows no hint', () async {
      expect(await hintAfterRelease(null), isFalse);
    });
  });

  group('double-tap trigger key from settings', () {
    const channel = MethodChannel('com.whispaste.keyboard_monitor');
    late List<Object?> watchCalls;
    late FakeModifierKeyMonitor macMonitor;
    // Whether the host reports the double-tap key as observable (the native
    // observer starts). Flipped by [setObservable] in a test.
    late bool observable;

    void setObservable(bool value) {
      observable = value;
      macMonitor.startResult = value;
    }

    /// Keys the host observes, whichever path this platform uses.
    List<ModifierHotkey> observedKeys() =>
        defaultTargetPlatform == TargetPlatform.macOS
        ? macMonitor.started
        : [
            for (final call in watchCalls)
              ModifierHotkey.values.byName((call as Map)['key'] as String),
          ];

    ProviderContainer makeContainer(AppSettings settings) {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _MutableSettings(settings)),
          hotkeyServiceProvider.overrideWith(() => service),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    AppSettings withDoubleTapKey(String key, {bool enabled = true}) {
      return AppSettings(
        hotkey: HotkeySettings(hotkeyEnabled: enabled, hotkeyDoubleTapKey: key),
      );
    }

    setUp(() {
      registrar = FakeHotKeyRegistrar();
      watchCalls = [];
      observable = true;
      macMonitor = FakeModifierKeyMonitor();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'watchModifier') {
              watchCalls.add(call.arguments);
              return observable;
            }
            return null;
          });
      service = HotkeyService()
        ..injectRegistrar(registrar)
        ..injectMonitor(
          ChannelKeyboardUpMonitor(isWindows: true, isLinux: false),
        )
        ..injectModifierMonitor(macMonitor)
        // An X11 session observes the key; a Wayland test host would not.
        ..injectEnvironment(const {'XDG_SESSION_TYPE': 'x11'});
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'a double-tap key is observed and no key combination is registered',
      () async {
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();

        expect(observedKeys(), [ModifierHotkey.rightControl]);
        expect(registrar.registered, isEmpty);
        expect(
          container.read(hotkeyRegistrationStatusProvider),
          HotkeyRegistrationStatus.success,
        );
      },
    );

    test('an empty double-tap key keeps the key combination', () async {
      final container = makeContainer(AppSettings.defaults);
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();

      expect(observedKeys(), isEmpty);
      expect(registrar.registered, hasLength(1));
    });

    test(
      'setting a double-tap key at runtime replaces the combination',
      () async {
        final container = makeContainer(AppSettings.defaults);
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();
        expect(registrar.registered, hasLength(1));

        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => AppSettings(
                hotkey: s.hotkey.copyWith(
                  hotkeyDoubleTapKey: ModifierHotkey.rightControl.name,
                ),
              ),
            );
        await pumpEventQueue();

        expect(observedKeys(), [ModifierHotkey.rightControl]);
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a disable that arrives while the macOS observer is still starting stops it',
      () async {
        _pin(TargetPlatform.macOS);
        final gate = Completer<void>();
        macMonitor.startGate = gate.future;
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();
        expect(observedKeys(), [ModifierHotkey.rightControl]);

        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                hotkey: s.hotkey.copyWith(hotkeyEnabled: false),
              ),
            );
        await pumpEventQueue();
        gate.complete();
        await pumpEventQueue();

        // The disabled hotkey must not stay observed once the start returns.
        expect(macMonitor.stopCount, 1);
        expect(macMonitor.onInput, isNull);
      },
    );

    test(
      'Fn from a macOS export reads as unavailable here, stays saved, and the '
      'combination listens',
      () async {
        _pin(TargetPlatform.windows);
        final imported = mergeImportedSettings(AppSettings.defaults, {
          'hotkey_double_tap_key': ModifierHotkey.fn.name,
        });
        final container = makeContainer(imported);
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();

        expect(container.read(doubleTapUnavailableProvider), isTrue);
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);
        expect(
          container.read(hotkeyRegistrationStatusProvider),
          HotkeyRegistrationStatus.success,
        );
        expect(observedKeys(), isEmpty);
        expect(registrar.registered, hasLength(1));
        expect(
          container.read(settingsProvider).value!.hotkey.hotkeyDoubleTapKey,
          ModifierHotkey.fn.name,
        );
      },
    );

    test('a key observable under X11 registers unchanged', () async {
      final container = makeContainer(
        withDoubleTapKey(ModifierHotkey.rightControl.name),
      );
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();

      expect(observedKeys(), [ModifierHotkey.rightControl]);
      expect(registrar.registered, isEmpty);
      expect(container.read(doubleTapFallbackActiveProvider), isFalse);
      expect(container.read(doubleTapUnavailableProvider), isFalse);
    });

    test(
      'an unobservable double-tap key falls back to the stored combination',
      () async {
        setObservable(false);
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();

        expect(registrar.registered, hasLength(1));
        expect(
          container.read(hotkeyRegistrationStatusProvider),
          HotkeyRegistrationStatus.success,
        );
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);
        // A refusal can pass, so it does not read as unavailable.
        expect(container.read(doubleTapUnavailableProvider), isFalse);
        // The choice stays saved; only the listening hotkey differs.
        expect(
          container.read(settingsProvider).value!.hotkey.hotkeyDoubleTapKey,
          ModifierHotkey.rightControl.name,
        );
      },
    );

    test(
      'the double tap takes over again once the key is observable',
      () async {
        setObservable(false);
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);

        setObservable(true);
        final settings = container.read(settingsProvider.notifier);
        await settings.updateSettings(
          (s) => s.copyWithSections(
            hotkey: s.hotkey.copyWith(hotkeyEnabled: false),
          ),
        );
        await settings.updateSettings(
          (s) => s.copyWithSections(
            hotkey: s.hotkey.copyWith(hotkeyEnabled: true),
          ),
        );
        await pumpEventQueue();

        expect(observedKeys().last, ModifierHotkey.rightControl);
        expect(registrar.registered, isEmpty);
        expect(container.read(doubleTapFallbackActiveProvider), isFalse);
      },
    );

    test(
      'a Wayland session takes the stored combination instead of a double tap',
      () async {
        _pin(TargetPlatform.linux);
        service.injectEnvironment(const {'XDG_SESSION_TYPE': 'wayland'});
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();

        expect(observedKeys(), isEmpty);
        expect(registrar.registered, hasLength(1));
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);
        expect(container.read(doubleTapUnavailableProvider), isTrue);
      },
    );

    test(
      'a fallback lifts on app resume once the key is observable, with one registration',
      () async {
        setObservable(false);
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);
        expect(observedKeys(), hasLength(1));

        // The permission is granted in the system settings while the app runs.
        setObservable(true);
        await _bringToForeground();

        expect(container.read(doubleTapFallbackActiveProvider), isFalse);
        expect(observedKeys(), hasLength(2));
        expect(observedKeys().last, ModifierHotkey.rightControl);
        expect(registrar.registered, isEmpty);
      },
    );

    test('a resume without an active fallback starts nothing new', () async {
      final container = makeContainer(
        withDoubleTapKey(ModifierHotkey.rightControl.name),
      );
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      expect(container.read(doubleTapFallbackActiveProvider), isFalse);
      expect(observedKeys(), hasLength(1));

      await _bringToForeground();

      expect(observedKeys(), hasLength(1));
      expect(registrar.registered, isEmpty);
    });

    test(
      'a fallback that is still refused on resume keeps the combination',
      () async {
        setObservable(false);
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.rightControl.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();

        await _bringToForeground();

        expect(container.read(doubleTapFallbackActiveProvider), isTrue);
        expect(observedKeys(), hasLength(2));
        expect(registrar.registered, hasLength(1));
      },
    );

    test(
      'a key the platform never observes is not retried on resume',
      () async {
        _pin(TargetPlatform.windows);
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.fn.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);

        await _bringToForeground();

        expect(observedKeys(), isEmpty);
        expect(registrar.registered, hasLength(1));
      },
    );
  });
}

/// Simulates the window losing and regaining focus, the desktop transition
/// the lifecycle listener of [HotkeyService] reacts to (inactive, then resumed).
Future<void> _bringToForeground() async {
  final binding = TestWidgetsFlutterBinding.instance;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await pumpEventQueue();
}

class _MutableSettings extends SettingsNotifier {
  _MutableSettings(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Pins the platform seam for the rest of the test (#198): the macOS observer
/// path and the Windows/Linux channel path both run on every host.
void _pin(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}
