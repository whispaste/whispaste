/// Tests for the modifier-only global hotkey routing in [HotkeyService].
///
/// [HotkeyService] picks its native observer by host: macOS uses
/// [ModifierKeyMonitor], Windows and Linux use the keyboard-monitor channel
/// through [ChannelKeyboardUpMonitor]. Each group below runs only on the host
/// whose path it covers, so the suite passes on every runner. The combo
/// registrar is [FakeHotKeyRegistrar] so no hotkey channel is touched.
library;

import 'dart:async' show Completer;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

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
  ValueChanged<ModifierInput>? onInput;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<bool> start(ModifierHotkey key) async {
    started.add(key);
    await startGate;
    return startResult;
  }

  @override
  Future<void> stop() async => stopCount++;

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

    test('starts the observer and registers no key combination', () async {
      final started = await service.registerModifierOnly(
        ModifierHotkey.rightControl,
      );

      expect(started, isTrue);
      expect(monitor.started, [ModifierHotkey.rightControl]);
      expect(registrar.registered, isEmpty);
    }, skip: _skipUnlessMacOS);

    test(
      'a modifier press starts and its release stops the global action',
      () async {
        await service.registerModifierOnly(ModifierHotkey.rightAlt);

        monitor.onInput!(ModifierInput.down);
        monitor.onInput!(ModifierInput.up);

        expect(pressed, 1);
        expect(released, 1);
      },
      skip: _skipUnlessMacOS,
    );

    test(
      'another key while the modifier is held is routed as other, not as a press',
      () async {
        await service.registerModifierOnly(ModifierHotkey.rightMeta);

        monitor.onInput!(ModifierInput.down);
        monitor.onInput!(ModifierInput.other);

        expect(pressed, 1);
        expect(otherKey, 1);
        expect(released, 0);
      },
      skip: _skipUnlessMacOS,
    );

    test(
      'reports false and keeps the combination when the platform cannot observe the key',
      () async {
        monitor.startResult = false;

        final started = await service.registerModifierOnly(ModifierHotkey.fn);

        expect(started, isFalse);
        expect(registrar.registered, isEmpty);
      },
      skip: _skipUnlessMacOS,
    );

    test(
      'switching back to a combination stops the modifier observer',
      () async {
        await service.registerModifierOnly(ModifierHotkey.rightControl);

        await service.updateHotkey(key: LogicalKeyboardKey.keyR);

        expect(monitor.stopCount, greaterThanOrEqualTo(1));
      },
      skip: _skipUnlessMacOS,
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
        final started = await service.registerModifierOnly(
          ModifierHotkey.rightControl,
        );

        expect(started, isTrue);
        expect(watchCalls, [
          {'key': ModifierHotkey.rightControl.name},
        ]);
        expect(registrar.registered, isEmpty);
      },
      skip: _skipUnlessNotMacOS,
    );

    test(
      'a modifier press from the host starts and its release stops the global action',
      () async {
        await service.registerModifierOnly(ModifierHotkey.rightAlt);

        await nativeCall('onModifierDown');
        await nativeCall('onModifierUp');

        expect(pressed, 1);
        expect(released, 1);
      },
      skip: _skipUnlessNotMacOS,
    );

    test(
      'another key while the modifier is held is routed as other, not as a press',
      () async {
        await service.registerModifierOnly(ModifierHotkey.rightMeta);

        await nativeCall('onModifierDown');
        await nativeCall('onOtherKey');

        expect(pressed, 1);
        expect(otherKey, 1);
        expect(released, 0);
      },
      skip: _skipUnlessNotMacOS,
    );

    test('reports false when the host refuses the key', () async {
      watchReply = false;

      final started = await service.registerModifierOnly(
        ModifierHotkey.rightControl,
      );

      expect(started, isFalse);
      expect(registrar.registered, isEmpty);
    }, skip: _skipUnlessNotMacOS);

    test(
      'replacing a channel watch stops the channel, not the macOS observer',
      () async {
        await service.registerModifierOnly(ModifierHotkey.rightControl);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(channelStops, greaterThanOrEqualTo(1));
        expect(macMonitor.stopCount, 0);
      },
      skip: _skipUnlessNotMacOS,
    );

    test(
      'Fn is refused without asking the host, since only macOS can observe it',
      () async {
        final started = await service.registerModifierOnly(ModifierHotkey.fn);

        expect(started, isFalse);
        expect(watchCalls, isEmpty);
      },
      skip: _skipUnlessNotMacOS,
    );
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
    List<ModifierHotkey> observedKeys() => Platform.isMacOS
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
      skip: _skipUnlessMacOS,
    );

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
      'Fn falls back to the stored combination off macOS, nothing is watched',
      () async {
        final container = makeContainer(
          withDoubleTapKey(ModifierHotkey.fn.name),
        );
        await container.read(settingsProvider.future);
        container.read(hotkeyServiceProvider);
        await pumpEventQueue();

        expect(observedKeys(), isEmpty);
        expect(registrar.registered, hasLength(1));
        expect(container.read(doubleTapFallbackActiveProvider), isTrue);
      },
      skip: _skipOnMacOS,
    );

    test(
      'a Wayland session takes the stored combination instead of a double tap',
      () async {
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
      },
      skip: Platform.isLinux ? null : 'the session type matters on Linux only',
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
      skip: _skipOnMacOS,
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

final String? _skipOnMacOS = Platform.isMacOS
    ? 'Fn is observable on macOS only, so the refusal path runs elsewhere'
    : null;

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

final String? _skipUnlessMacOS = Platform.isMacOS
    ? null
    : 'uses the macOS ModifierKeyMonitor path, which only runs on macOS';

final String? _skipUnlessNotMacOS = Platform.isMacOS
    ? 'uses the Windows/Linux channel path, which does not run on macOS'
    : null;
