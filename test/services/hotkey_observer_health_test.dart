/// Tests for the health of the single-key observer (#773): how a native reply
/// reads, when a dead observer is rebuilt or given up, and what the service
/// does about it. The service group drives the Windows/Linux channel path with
/// a mocked keyboard-monitor channel and a simulated clock; the macOS reply
/// goes through the real [ModifierKeyMonitor] on a mocked channel.
library;

import 'dart:async' show unawaited;

import 'package:fake_async/fake_async.dart';
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
import 'package:whispaste/services/hotkey_self_heal.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

class _FakeRegistrar implements HotKeyRegistrar {
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
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('observerHealthFromReply', () {
    test(
      'a withdrawn grant is a revoked permission, whatever else it says',
      () {
        expect(
          observerHealthFromReply({'listenAccess': false, 'tapActive': true}),
          ObserverHealth.permissionRevoked,
        );
      },
    );

    test('a stopped tap or watch is dead', () {
      expect(
        observerHealthFromReply({'listenAccess': true, 'tapActive': false}),
        ObserverHealth.dead,
      );
      expect(observerHealthFromReply({'active': false}), ObserverHealth.dead);
    });

    test('a granted, running observer is healthy', () {
      expect(observerHealthFromReply({'active': true}), ObserverHealth.healthy);
      expect(
        observerHealthFromReply({'listenAccess': true, 'tapActive': true}),
        ObserverHealth.healthy,
      );
      // A host that does not report the tap yet: only the grant is known.
      expect(
        observerHealthFromReply({'listenAccess': true}),
        ObserverHealth.healthy,
      );
    });

    test('no answer, a wrong type or an empty map is never acted upon', () {
      expect(observerHealthFromReply(null), ObserverHealth.unknown);
      expect(observerHealthFromReply(true), ObserverHealth.unknown);
      expect(observerHealthFromReply(const {}), ObserverHealth.unknown);
    });
  });

  group('ObserverHealthTracker', () {
    test('rebuilds a dead observer until the attempts are spent', () {
      final tracker = ObserverHealthTracker(maxAttempts: 2);

      expect(tracker.decide(ObserverHealth.dead), ObserverHealthAction.rebuild);
      expect(tracker.decide(ObserverHealth.dead), ObserverHealthAction.rebuild);
      expect(
        tracker.decide(ObserverHealth.dead),
        ObserverHealthAction.fallbackExhausted,
      );
    });

    test('an unknown answer neither spends nor restores an attempt', () {
      final tracker = ObserverHealthTracker(maxAttempts: 1);
      tracker.decide(ObserverHealth.dead);

      expect(tracker.decide(ObserverHealth.unknown), ObserverHealthAction.none);
      expect(
        tracker.decide(ObserverHealth.dead),
        ObserverHealthAction.fallbackExhausted,
      );
    });

    test('one healthy answer between deaths does not restore the attempts', () {
      final tracker = ObserverHealthTracker(maxAttempts: 2);
      tracker.decide(ObserverHealth.dead);
      tracker.decide(ObserverHealth.healthy);
      tracker.decide(ObserverHealth.dead);
      tracker.decide(ObserverHealth.healthy);

      expect(
        tracker.decide(ObserverHealth.dead),
        ObserverHealthAction.fallbackExhausted,
      );
    });

    test('a stable healthy phase restores the attempts', () {
      final tracker = ObserverHealthTracker(maxAttempts: 1);
      tracker.decide(ObserverHealth.dead);
      for (var i = 0; i < kObserverStableChecks; i++) {
        tracker.decide(ObserverHealth.healthy);
      }

      expect(tracker.decide(ObserverHealth.dead), ObserverHealthAction.rebuild);
    });

    test('a revoked permission skips the rebuilds', () {
      expect(
        ObserverHealthTracker().decide(ObserverHealth.permissionRevoked),
        ObserverHealthAction.fallbackPermission,
      );
    });
  });

  group('ModifierKeyMonitor.health (macOS host reply)', () {
    const channel = MethodChannel('com.whispaste.modifier_monitor');
    Object? reply;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method != 'status') return null;
            if (reply is PlatformException) throw reply! as PlatformException;
            return reply;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reads the status reply into a health', () async {
      final monitor = ModifierKeyMonitor(isMacOS: true, channel: channel);

      reply = {'listenAccess': false};
      expect(await monitor.health(), ObserverHealth.permissionRevoked);
      reply = {'listenAccess': true, 'tapActive': false};
      expect(await monitor.health(), ObserverHealth.dead);
      reply = {'listenAccess': true};
      expect(await monitor.health(), ObserverHealth.healthy);
    });

    test('a failing host is unknown, and other systems never ask', () async {
      reply = PlatformException(code: 'boom');
      expect(
        await ModifierKeyMonitor(isMacOS: true, channel: channel).health(),
        ObserverHealth.unknown,
      );
      reply = {'listenAccess': false};
      expect(
        await ModifierKeyMonitor(isMacOS: false, channel: channel).health(),
        ObserverHealth.unknown,
      );
    });
  });

  group('HotkeyService single-key observer (Windows/Linux channel)', () {
    const channel = MethodChannel('com.whispaste.keyboard_monitor');
    late _FakeRegistrar registrar;
    late HotkeyService service;
    late ProviderContainer container;
    late int watchCalls;
    late int stopCalls;
    // What the host answers to `modifierHealth`; null = no answer.
    Object? healthReply;
    var dictationBusy = false;

    setUp(() {
      // The channel path is chosen through the platform seam; pin it so the
      // group runs the same on every host.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      registrar = _FakeRegistrar();
      watchCalls = 0;
      stopCalls = 0;
      healthReply = {'active': true};
      dictationBusy = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'watchModifier':
                watchCalls++;
                return true;
              case 'stop':
                stopCalls++;
                return null;
              case 'modifierHealth':
                return healthReply;
              default:
                return null;
            }
          });
      service = HotkeyService()
        ..injectRegistrar(registrar)
        ..injectMonitor(
          ChannelKeyboardUpMonitor(isWindows: true, isLinux: false),
        )
        ..injectModifierMonitor(ModifierKeyMonitor(isMacOS: false))
        ..injectHealEnvironment(
          hotkeyEnabled: () => true,
          dictationBusy: () => dictationBusy,
        )
        ..injectEnvironment(const {'XDG_SESSION_TYPE': 'x11'});
      container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _Settings(
              AppSettings(
                hotkey: HotkeySettings(
                  hotkeyEnabled: true,
                  hotkeyDoubleTapKey: ModifierHotkey.rightControl.name,
                ),
              ),
            ),
          ),
          hotkeyServiceProvider.overrideWith(() => service),
        ],
      );
      addTearDown(container.dispose);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> nativeCall(String method) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method)),
            (_) {},
          );
    }

    Future<void> startObserver() async {
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      expect(watchCalls, 1, reason: 'the observer is up before the check');
    }

    bool fallbackActive() => container.read(doubleTapFallbackActiveProvider);

    HotkeyObserverLoss? notice() =>
        container.read(hotkeyObserverLostNoticeProvider);

    test('a healthy observer is left alone', () async {
      await startObserver();
      final stopsAfterStart = stopCalls;

      await service.checkObserverHealth();
      await service.checkObserverHealth();

      expect(watchCalls, 1);
      expect(stopCalls, stopsAfterStart);
      expect(fallbackActive(), isFalse);
      expect(notice(), isNull);
    });

    test('a dead observer is rebuilt and the combination stays off', () async {
      await startObserver();
      healthReply = {'active': false};

      await service.checkObserverHealth();
      healthReply = {'active': true};
      await service.checkObserverHealth();

      expect(watchCalls, 2, reason: 'one rebuild, none for the healthy check');
      expect(registrar.registered, isEmpty);
      expect(fallbackActive(), isFalse);
      expect(notice(), isNull);
    });

    test('an observer that keeps dying is given up for the combination, '
        'with a notice', () async {
      await startObserver();
      healthReply = {'active': false};

      for (var i = 0; i < kObserverRebuildMaxAttempts; i++) {
        await service.checkObserverHealth();
      }
      expect(watchCalls, 1 + kObserverRebuildMaxAttempts);
      expect(notice(), isNull, reason: 'still trying');

      await service.checkObserverHealth();

      expect(
        watchCalls,
        1 + kObserverRebuildMaxAttempts,
        reason: 'no further rebuild after giving up',
      );
      expect(registrar.registered, hasLength(1));
      expect(fallbackActive(), isTrue);
      expect(notice()?.reason, ObserverLossReason.repeatedFailure);

      // Nothing is wanted any more: later checks stay silent.
      await service.checkObserverHealth();
      expect(watchCalls, 1 + kObserverRebuildMaxAttempts);
    });

    test('a withdrawn permission falls back at once, no rebuild', () async {
      await startObserver();
      healthReply = {'listenAccess': false};

      await service.checkObserverHealth();

      expect(watchCalls, 1);
      expect(registrar.registered, hasLength(1));
      expect(fallbackActive(), isTrue);
      expect(notice()?.reason, ObserverLossReason.permissionRevoked);
    });

    test('a host that cannot tell is never acted upon', () async {
      await startObserver();
      healthReply = null;

      await service.checkObserverHealth();

      expect(watchCalls, 1);
      expect(notice(), isNull);
    });

    test('no check while a dictation is busy, so no press is lost', () async {
      await startObserver();
      healthReply = {'active': false};
      dictationBusy = true;

      await service.checkObserverHealth();
      expect(watchCalls, 1);

      dictationBusy = false;
      await service.checkObserverHealth();
      expect(watchCalls, 2);
    });

    test('the check runs on its own every interval, with simulated time', () {
      fakeAsync((async) {
        unawaited(service.registerModifierOnly(ModifierHotkey.rightControl));
        async.flushMicrotasks();
        expect(watchCalls, 1);
        healthReply = {'active': false};

        async.elapse(kObserverHealthInterval - const Duration(seconds: 1));
        expect(watchCalls, 1, reason: 'not before the interval');

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(watchCalls, 2);
      });
    });

    test(
      'no rebuild while the key is held, so its release is not lost',
      () async {
        await startObserver();
        healthReply = {'active': false};

        await nativeCall('onModifierDown');
        await service.checkObserverHealth();
        expect(watchCalls, 1);

        await nativeCall('onModifierUp');
        await service.checkObserverHealth();
        expect(watchCalls, 2);
      },
    );

    test('a switch to a combination ends the watch', () async {
      await startObserver();

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      healthReply = {'active': false};
      await service.checkObserverHealth();

      expect(watchCalls, 1, reason: 'nothing is wanted any more');
    });

    test(
      'a wake heal rebuilds the single key instead of skipping it',
      () async {
        await startObserver();
        var now = DateTime(2026, 11, 6, 12);
        service.injectHealClock(() => now);

        await service.requestHotkeyHeal(HotkeyHealTrigger.wake);

        expect(watchCalls, 2);
        expect(registrar.registered, isEmpty);
        now = now.add(kHotkeyHealMinInterval);
      },
    );
  });
}
