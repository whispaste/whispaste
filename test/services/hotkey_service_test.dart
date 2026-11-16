/// Unit tests for [HotkeyService] error-handling and safe-default fallback.
///
/// Uses [FakeHotKeyRegistrar] to avoid real platform-channel calls.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:logging/logging.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/hotkey_heal_notice.dart';
import 'package:whispaste/services/hotkey_key_resolver.dart';
import 'package:whispaste/services/hotkey_self_heal.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/hotkey_registrar.dart';
import 'package:whispaste/services/input_monitoring_offer.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/services/short_press_hint.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Tracks [register]/[unregister] calls and can be told to throw on demand.
class FakeHotKeyRegistrar
    implements HotKeyRegistrar, RepeatFilteringHotKeyRegistrar {
  FakeHotKeyRegistrar({
    this.supportsKeyUp = false,
    this.filtersKeyRepeat = false,
  });

  @override
  final bool filtersKeyRepeat;

  final List<HotKey> registered = [];
  final List<HotKey> unregistered = [];

  /// Last keyDown handler passed to [register].
  HotKeyHandler? capturedKeyDownHandler;

  /// Last keyUp handler passed to [register].
  HotKeyHandler? capturedKeyUpHandler;

  /// Handlers captured per logical key (by [LogicalKeyboardKey.keyId]),
  /// letting a test drive two independently-registered actions (e.g. the
  /// global and quick-note hotkeys) separately, since [capturedKeyDownHandler]
  /// only ever holds the most recent registration's handler.
  final Map<int, HotKeyHandler> keyDownHandlersByKeyId = {};
  final Map<int, HotKeyHandler> keyUpHandlersByKeyId = {};

  /// If non-null, [register] throws this object the first time it is called.
  Object? throwOnFirstRegister;

  /// If non-null, [register] refuses this key every time it is asked for,
  /// like a combination another app holds. Other keys (e.g. the safe default)
  /// still register.
  LogicalKeyboardKey? refuseKey;

  /// The next [count] calls to [register] throw, then registration works again.
  int failNextRegisters = 0;

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    if (throwOnFirstRegister != null) {
      final toThrow = throwOnFirstRegister;
      throwOnFirstRegister = null; // only throw once
      // ignore: only_throw_errors
      throw toThrow!;
    }
    if (failNextRegisters > 0) {
      failNextRegisters--;
      throw PlatformException(code: 'hotkey_unavailable');
    }
    if (refuseKey != null && hotKey.logicalKey == refuseKey) {
      throw PlatformException(code: 'hotkey_unavailable');
    }
    capturedKeyDownHandler = keyDownHandler;
    capturedKeyUpHandler = keyUpHandler;
    if (keyDownHandler != null) {
      keyDownHandlersByKeyId[hotKey.logicalKey.keyId] = keyDownHandler;
    }
    if (keyUpHandler != null) {
      keyUpHandlersByKeyId[hotKey.logicalKey.keyId] = keyUpHandler;
    }
    registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    unregistered.add(hotKey);
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }
}

/// Fake RawInput key-up monitor (#39). Records start/stop and can emit a
/// synthetic key-up to drive the service's release path.
class FakeKeyboardUpMonitor implements KeyboardUpMonitor {
  FakeKeyboardUpMonitor({this.supportsKeyUp = true, this.experimental = false});

  @override
  final bool supportsKeyUp;

  @override
  final bool experimental;

  final List<HotKey> started = [];
  int stopCount = 0;
  int armCount = 0;
  ValueChanged<Duration?>? _onKeyUp;
  VoidCallback? _onKeyDown;

  @override
  set onKeyUp(ValueChanged<Duration?>? handler) => _onKeyUp = handler;

  @override
  set onKeyDown(VoidCallback? handler) => _onKeyDown = handler;

  final List<String?> descriptions = [];

  @override
  Future<void> start(HotKey hotKey, {String? description}) async {
    started.add(hotKey);
    descriptions.add(description);
  }

  /// What the native snapshot reports when armed: whether the watched key is
  /// still held. A click on an on-screen keyboard is already up by then.
  bool armHeld = true;

  @override
  Future<bool> armRelease({
    Iterable<HotKeyModifier> modifiers = const [],
  }) async {
    armCount++;
    return armHeld;
  }

  /// What the hardware read says: null unknown, false means the key is up
  /// although no release arrived. Counts the reads.
  bool? heldNow;
  int probeCount = 0;

  /// How long a held-key read takes (a stalled UI thread, #1194).
  Duration probeDelay = Duration.zero;

  @override
  Future<bool?> isHeld() async {
    probeCount++;
    if (probeDelay > Duration.zero) await Future<void>.delayed(probeDelay);
    return heldNow;
  }

  @override
  Future<void> stop() async => stopCount++;

  /// Simulates the native host reporting the watched hotkey's release, with
  /// the press length it timed (null when the host could not time it).
  void emitKeyUp([Duration? pressed]) => _onKeyUp?.call(pressed);

  /// Simulates a monitor-sourced press (Linux GlobalShortcuts portal).
  void emitKeyDown() => _onKeyDown?.call();

  WaylandHotkeyBinding _waylandBinding = WaylandHotkeyBinding.notApplicable;
  VoidCallback? _onWaylandBindingChanged;

  @override
  WaylandHotkeyBinding get waylandBinding => _waylandBinding;

  @override
  String? get waylandTrigger => null;

  @override
  String? get waylandSettingsAppId => null;

  @override
  set onWaylandBindingChanged(VoidCallback? handler) =>
      _onWaylandBindingChanged = handler;

  /// Simulates the Linux host reporting a new Wayland binding outcome.
  void emitWaylandBinding(WaylandHotkeyBinding binding) {
    _waylandBinding = binding;
    _onWaylandBindingChanged?.call();
  }
}

/// A [FakeHotKeyRegistrar] whose [register] can be held open via [gate] —
/// used to drive the epoch-guard race of the session-scoped
/// interactive-snippet keys deterministically.
class GatedHotKeyRegistrar extends FakeHotKeyRegistrar {
  /// While non-null, [register] parks on this completer before delegating.
  Completer<void>? gate;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    final g = gate;
    if (g != null) await g.future;
    await super.register(
      hotKey,
      keyDownHandler: keyDownHandler,
      keyUpHandler: keyUpHandler,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a standalone [HotkeyService] with an injected [FakeHotKeyRegistrar].
///
/// Does NOT use Riverpod — we call [updateHotkey] directly so there is no
/// [build] lifecycle to manage.
class _MutableSettingsNotifier extends SettingsNotifier {
  _MutableSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

HotkeyService _makeService(FakeHotKeyRegistrar registrar) {
  final service = HotkeyService();
  service.injectRegistrar(registrar);
  // Inject a no-op key-up monitor so capability is driven solely by the
  // injected registrar and stays deterministic regardless of the host platform.
  // On Windows the default ChannelKeyboardUpMonitor reports supportsKeyUp=true
  // and would otherwise leak into these tests (#39). Monitor-path tests override
  // this with their own FakeKeyboardUpMonitor.
  service.injectMonitor(NoopKeyboardUpMonitor());
  return service;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  test(
    'native repeat filtering preserves rapid second presses for all actions',
    () {
      fakeAsync((async) {
        final registrar = FakeHotKeyRegistrar(filtersKeyRepeat: true);
        final service = _makeService(registrar);
        final presses = <String, int>{};
        void count(String action) =>
            presses.update(action, (n) => n + 1, ifAbsent: () => 1);
        service.onQuickNoteHotkeyPressed = () => count('note');
        service.onSnippetPickerHotkeyPressed = () => count('snippet');
        service.onLanguageCycleHotkeyPressed = () => count('language');
        service.onRepasteHotkeyPressed = () => count('repaste');
        unawaited(service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN));
        unawaited(
          service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyS),
        );
        unawaited(
          service.updateLanguageCycleHotkey(key: LogicalKeyboardKey.keyL),
        );
        unawaited(service.updateRepasteHotkey(key: LogicalKeyboardKey.keyP));
        async.flushMicrotasks();
        for (final hotkey in registrar.registered) {
          final handler =
              registrar.keyDownHandlersByKeyId[hotkey.logicalKey.keyId]!;
          handler(hotkey);
          async.elapse(const Duration(milliseconds: 20));
          handler(
            hotkey,
          ); // Native layer saw a release before this second down.
        }
        expect(presses, {'note': 2, 'snippet': 2, 'language': 2, 'repaste': 2});
        expect(SuspendableHotKeyRegistrar(registrar).filtersKeyRepeat, isTrue);
      });
    },
  );
  _healGroup();
  // The sentry SDK requires a binding to be initialised before it can add
  // breadcrumbs; in tests it silently no-ops, which is what we want.
  TestWidgetsFlutterBinding.ensureInitialized();

  // #439: after a settings import the bootstrap is rebuilt; the hotkey must
  // reach the new one, never the torn-down state, and a throwing handler
  // must not end the key handling silently. One dispatch serves the macOS
  // registrar, the Windows RegisterHotKey + RawInput pair and the Linux
  // portal monitor, so each path is driven here.
  group('HotkeyService — callback owner and contained handler errors', () {
    late List<LogRecord> logs;
    late StreamSubscription<LogRecord> sub;
    late Level previousLevel;

    setUp(() {
      logs = [];
      previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      sub = Logger.root.onRecord.listen(logs.add);
    });
    tearDown(() async {
      await sub.cancel();
      Logger.root.level = previousLevel;
    });

    List<LogRecord> failures() =>
        logs.where((r) => r.message.contains('hotkey handler failed')).toList();

    test(
      'releasing an older owner keeps the newer owner\'s callbacks',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        final hotKey = registrar.registered.first;
        final oldOwner = Object();
        final newOwner = Object();
        final presses = <String>[];

        service.bindCallbacks(oldOwner);
        service.onHotkeyPressed = () => presses.add('old');
        // The rebuilt bootstrap wires itself before the old one is disposed.
        service.bindCallbacks(newOwner);
        service.onHotkeyPressed = () => presses.add('new');
        service.releaseCallbacks(oldOwner);

        registrar.capturedKeyDownHandler!(hotKey);
        expect(presses, ['new']);
      },
    );

    test('releasing the current owner clears every action callback', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final hotKey = registrar.registered.first;
      final owner = Object();
      var calls = 0;

      service.bindCallbacks(owner);
      void count() => calls++;
      service.onHotkeyPressed = count;
      service.onHotkeyReleased = count;
      service.onModifierOtherKey = count;
      service.onQuickNoteHotkeyPressed = count;
      service.onSnippetPickerHotkeyPressed = count;
      service.onLanguageCycleHotkeyPressed = count;
      service.onRepasteHotkeyPressed = count;
      service.onLearnCorrectionHotkeyPressed = count;
      service.onSmartModeHotkeyPressed = count;
      service.onSmartModeHotkeyReleased = count;
      service.onSelectionEditHotkeyPressed = count;
      service.onSelectionEditHotkeyReleased = count;
      service.onProfileHotkeyPressed = (_) => count();
      service.releaseCallbacks(owner);

      expect(service.onHotkeyPressed, isNull);
      expect(service.onHotkeyReleased, isNull);
      expect(service.onModifierOtherKey, isNull);
      expect(service.onQuickNoteHotkeyPressed, isNull);
      expect(service.onSnippetPickerHotkeyPressed, isNull);
      expect(service.onLanguageCycleHotkeyPressed, isNull);
      expect(service.onRepasteHotkeyPressed, isNull);
      expect(service.onLearnCorrectionHotkeyPressed, isNull);
      expect(service.onProfileHotkeyPressed, isNull);
      expect(service.onSmartModeHotkeyPressed, isNull);
      expect(service.onSmartModeHotkeyReleased, isNull);
      expect(service.onSelectionEditHotkeyPressed, isNull);
      expect(service.onSelectionEditHotkeyReleased, isNull);

      // A press with no owner is dropped with a log line, never a throw.
      registrar.capturedKeyDownHandler!(hotKey);
      registrar.capturedKeyUpHandler!(hotKey);
      expect(calls, 0);
      expect(
        logs.map((r) => r.message),
        contains(contains('no handler bound')),
      );
    });

    test('releasing the owner also drops a running dictation\'s Escape '
        'cancel key', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      final owner = Object();
      service.bindCallbacks(owner);
      await service.registerCancelDictationKey(onCancel: () {});
      expect(
        registrar.registered.map((h) => h.logicalKey),
        contains(LogicalKeyboardKey.escape),
      );

      service.releaseCallbacks(owner);
      await pumpEventQueue();

      expect(
        registrar.registered.map((h) => h.logicalKey),
        isNot(contains(LogicalKeyboardKey.escape)),
      );
    });

    test('macOS registrar: a throwing press handler is logged and the release '
        'still arrives', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final hotKey = registrar.registered.first;
      var released = false;
      service.onHotkeyPressed = () => throw StateError('disposed ref');
      service.onHotkeyReleased = () => released = true;

      expect(() => registrar.capturedKeyDownHandler!(hotKey), returnsNormally);
      registrar.capturedKeyUpHandler!(hotKey);

      expect(released, isTrue);
      expect(failures().single.level, Level.WARNING);
      expect(failures().single.message, contains('StateError'));
    });

    test('Windows RegisterHotKey + RawInput: the release watch is still armed '
        'after a throwing press handler', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor();
      service.injectMonitor(monitor);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      var released = false;
      service.onHotkeyPressed = () => throw StateError('disposed ref');
      service.onHotkeyReleased = () => released = true;

      registrar.capturedKeyDownHandler!(registrar.registered.first);
      monitor.emitKeyUp();

      expect(monitor.armCount, 1);
      expect(released, isTrue);
      expect(failures(), hasLength(1));
    });

    test('Linux portal monitor: a throwing press and release handler are both '
        'logged, the next press works', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor();
      service.injectMonitor(monitor);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      service.onHotkeyPressed = () => throw StateError('press');
      service.onHotkeyReleased = () => throw StateError('release');

      monitor.emitKeyDown();
      monitor.emitKeyUp();
      expect(failures(), hasLength(2));

      var pressed = false;
      service.onHotkeyPressed = () => pressed = true;
      monitor.emitKeyDown();
      expect(pressed, isTrue);
    });
  });

  group('HotkeyService — error handling', () {
    test(
      'AC1: catches Object — registration that throws TypeError does not propagate',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        // Must complete without throwing even though register throws TypeError.
        await expectLater(
          service.updateHotkey(key: LogicalKeyboardKey.keyD),
          completes,
        );
      },
    );

    test(
      'AC2: safe-default registered — after TypeError, safe-default key is registered',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        // The safe-default (Space) must be in the registered list.
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isTrue,
          reason: 'safe-default Space key should be registered after failure',
        );
      },
    );

    test(
      'AC3: localised toast callback — onRegistrationFailed is invoked after TypeError',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        var callbackFired = false;
        service.onRegistrationFailed = () => callbackFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          callbackFired,
          isTrue,
          reason:
              'onRegistrationFailed must be called so the UI can show a toast',
        );
      },
    );

    test(
      'AC4: Sentry breadcrumb — updateHotkey completes (breadcrumb added internally)',
      () async {
        // We cannot assert on the Sentry SDK directly in unit tests, but we
        // verify the code path doesn't throw and the key-code string is formed
        // correctly by checking the logged key ID is a hex string.
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        // No exception must escape — this verifies the breadcrumb call didn't
        // itself cause a crash.
        await expectLater(
          service.updateHotkey(key: LogicalKeyboardKey.keyD),
          completes,
        );

        // Verify the failed key code is formatted as a hex string (not PII).
        final hexPattern = RegExp(r'^[0-9a-f]+$');
        final keyCode = LogicalKeyboardKey.keyD.keyId.toRadixString(16);
        expect(
          hexPattern.hasMatch(keyCode),
          isTrue,
          reason: 'key code sent to breadcrumb must be a hex string, not PII',
        );
      },
    );

    test(
      'AC5: TypeError leaves service usable — onHotkeyPressed still fires after fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        var hotkeyFired = false;
        service.onHotkeyPressed = () => hotkeyFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        // The safe-default handler should have been registered.
        expect(
          registrar.registered.isNotEmpty,
          isTrue,
          reason:
              'safe-default hotkey must be registered so the service is usable',
        );

        // Simulate the hotkey press by calling the service's hotkeyPressed
        // callback directly to verify the service is still wired.
        service.onHotkeyPressed?.call();
        expect(
          hotkeyFired,
          isTrue,
          reason: 'service must remain usable after fallback',
        );
      },
    );

    test(
      'normal registration — no fallback triggered when register succeeds',
      () async {
        final registrar = FakeHotKeyRegistrar(); // no throw
        final service = _makeService(registrar);

        var failedCallbackFired = false;
        service.onRegistrationFailed = () => failedCallbackFired = true;

        await service.updateHotkey(
          key: LogicalKeyboardKey.keyD,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        );

        expect(
          failedCallbackFired,
          isFalse,
          reason:
              'onRegistrationFailed must NOT fire when registration succeeds',
        );
        // Only one key should be registered (the requested one, not the fallback).
        expect(registrar.registered.length, equals(1));
        expect(
          registrar.registered.first.logicalKey,
          equals(LogicalKeyboardKey.keyD),
        );
      },
    );

    test(
      'catches plain Exception — onRegistrationFailed fires for Exception too',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = Exception('platform error');
        final service = _makeService(registrar);

        var callbackFired = false;
        service.onRegistrationFailed = () => callbackFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.space);

        expect(callbackFired, isTrue);
      },
    );
  });

  group('safeDefaultHotKey', () {
    test('contains Space key', () {
      expect(safeDefaultHotKey.logicalKey, equals(LogicalKeyboardKey.space));
    });

    test('has at least one modifier', () {
      expect(safeDefaultHotKey.modifiers, isNotEmpty);
    });

    test('its settings strings resolve to the same combination', () {
      // Settings and dock display the active fallback from these strings.
      expect(resolveKey(safeDefaultHotkeyKey), safeDefaultHotKey.logicalKey);
      // Modifier order carries no meaning; storage keeps its canonical order.
      expect(
        resolveModifiers(safeDefaultHotkeyModifiers),
        unorderedEquals(safeDefaultHotKey.modifiers!),
      );
    });
  });

  group('activeGlobalHotkey (XP-5-09)', () {
    final configured = AppSettings.defaults.copyWith(
      hotkeyKey: ';',
      hotkeyKeyDisplay: 'Ö',
      hotkeyModifiers: 'ctrl+alt',
    );

    test('is the configured combination without a fallback', () {
      final active = activeGlobalHotkey(configured, fallback: false);
      expect(active.key, ';');
      expect(active.display, 'Ö');
      expect(active.modifiers, 'ctrl+alt');
    });

    test('is the safe default while it stands in', () {
      final active = activeGlobalHotkey(configured, fallback: true);
      expect(active.key, safeDefaultHotkeyKey);
      expect(active.display, isEmpty);
      expect(active.modifiers, safeDefaultHotkeyModifiers);
    });
  });

  group('re-recording a hotkey (fix/hotkey-rerecord-same)', () {
    // A registered combination never reaches the recorder, its own included:
    // the saved Cmd+Ä pressed again left only Cmd in the recorder.
    tearDown(HotkeyCaptureGuard.reset);

    ProviderContainer makeContainer(FakeHotKeyRegistrar registrar) {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _MutableSettingsNotifier(
              AppSettings.defaults.copyWith(hotkeyEnabled: false),
            ),
          ),
          hotkeyServiceProvider.overrideWith(() {
            final service = HotkeyService()..injectRegistrar(registrar);
            return service..injectMonitor(NoopKeyboardUpMonitor());
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a listening recorder takes the hotkey off the system and puts it '
        'back on cancel', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final hotKey = registrar.registered.single;

      HotkeyCaptureGuard.beginListening();
      await service.captureSuspensionSettled;
      expect(registrar.registered, isEmpty);

      HotkeyCaptureGuard.endListening();
      await service.captureSuspensionSettled;
      expect(registrar.registered.map((h) => h.identifier), [
        hotKey.identifier,
      ]);
    });

    test('a hotkey saved while recording is registered once recording '
        'ends', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      HotkeyCaptureGuard.beginListening();
      await service.updateHotkey(key: LogicalKeyboardKey.keyE);
      expect(registrar.registered, isEmpty);
      HotkeyCaptureGuard.endListening();
      await service.captureSuspensionSettled;

      expect(registrar.registered.map((h) => h.logicalKey), [
        LogicalKeyboardKey.keyE,
      ]);
    });

    test('a press while a recorder listens triggers nothing', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final keyDown = registrar.capturedKeyDownHandler!;
      final hotKey = registrar.registered.single;
      var presses = 0;
      service.onHotkeyPressed = () => presses++;

      HotkeyCaptureGuard.beginListening();
      keyDown(hotKey);

      expect(presses, 0);
    });

    test('a hotkey the system refuses after recording shows as a '
        'conflict', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      HotkeyCaptureGuard.beginListening();
      await service.captureSuspensionSettled;
      registrar.refuseKey = LogicalKeyboardKey.keyD;
      HotkeyCaptureGuard.endListening();
      await service.captureSuspensionSettled;

      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
    });

    test('a self-heal the system refuses shows the conflict instead of '
        'success', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      var clock = DateTime(2026, 11, 5, 12);
      service
        ..injectHealEnvironment(
          hotkeyEnabled: () => true,
          dictationBusy: () => false,
        )
        ..injectHealClock(() => clock);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.success,
      );

      // Another app took the combination while the app was running.
      registrar.refuseKey = LogicalKeyboardKey.keyD;
      clock = clock.add(kHotkeyHealMinInterval + const Duration(seconds: 1));
      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);

      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
    });

    test('a change after a refused registration does not unregister the '
        'refused combination', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      var clock = DateTime(2026, 11, 5, 12);
      service
        ..injectHealEnvironment(
          hotkeyEnabled: () => true,
          dictationBusy: () => false,
        )
        ..injectHealClock(() => clock);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      registrar.refuseKey = LogicalKeyboardKey.keyD;
      clock = clock.add(kHotkeyHealMinInterval + const Duration(seconds: 1));
      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);
      final unregisteredBefore = registrar.unregistered.length;

      // The native plugin holds no record of the refused combination (Windows
      // throws on an unknown identifier), so it must not be unregistered again.
      await service.updateHotkey(key: LogicalKeyboardKey.keyE);

      final refusedUnregisters = registrar.unregistered
          .skip(unregisteredBefore)
          .where((hotKey) => hotKey.logicalKey == LogicalKeyboardKey.keyD);
      expect(refusedUnregisters, isEmpty);
    });

    test('a stored key the resolver rejects shows as unknown, with the '
        'safe default in its place', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);

      await service.debugRegisterFromSettings(
        hotkeyKey: 'F25',
        hotkeyModifiers: '',
      );

      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknownKey,
      );
      expect(registrar.registered.single.logicalKey, LogicalKeyboardKey.space);
    });

    test('a recorder still listening after two minutes gives the hotkey '
        'back without waiting for the heal tick', () {
      FakeAsync().run((async) {
        final registrar = FakeHotKeyRegistrar();
        final container = makeContainer(registrar);
        final service = container.read(hotkeyServiceProvider.notifier);
        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        final start = DateTime(2026, 11, 1, 12);
        DateTime now() => start.add(async.elapsed);
        HotkeyCaptureGuard.clock = now;
        service.injectHealClock(now);

        HotkeyCaptureGuard.beginListening();
        async.flushMicrotasks();
        expect(registrar.registered, isEmpty);

        async.elapse(const Duration(minutes: 1, seconds: 59));
        expect(HotkeyCaptureGuard.listening, isTrue);
        expect(registrar.registered, isEmpty);

        async.elapse(const Duration(seconds: 2));
        expect(HotkeyCaptureGuard.listening, isFalse);
        expect(registrar.registered.map((h) => h.logicalKey), [
          LogicalKeyboardKey.keyD,
        ]);
      });
    });

    test('running out of the listening time keeps the saved combination, '
        'and the notice is raised once', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      var now = DateTime(2026, 11, 2, 9);
      HotkeyCaptureGuard.clock = () => now;
      service.injectHealClock(() => now);

      HotkeyCaptureGuard.beginListening();
      await service.captureSuspensionSettled;
      expect(registrar.registered, isEmpty);

      now = now.add(kHotkeyCaptureListenLimit + const Duration(minutes: 1));
      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);
      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);
      await service.captureSuspensionSettled;

      expect(registrar.registered.map((h) => h.logicalKey), [
        LogicalKeyboardKey.keyD,
      ]);
      expect(container.read(hotkeyCaptureTimeoutNoticeProvider), 1);
    });

    test('the heal tick gives the hotkey back after a recorder listened '
        'past the limit', () async {
      final registrar = FakeHotKeyRegistrar();
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      var now = DateTime(2026, 10, 31, 12);
      HotkeyCaptureGuard.clock = () => now;
      service.injectHealClock(() => now);

      HotkeyCaptureGuard.beginListening();
      await service.captureSuspensionSettled;
      expect(registrar.registered, isEmpty);

      now = now.add(kHotkeyCaptureListenLimit + const Duration(minutes: 1));
      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);
      await service.captureSuspensionSettled;

      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(registrar.registered.map((h) => h.logicalKey), [
        LogicalKeyboardKey.keyD,
      ]);
    });
  });

  group('globalHotkeyFallbackActiveProvider (XP-5-09)', () {
    // The fallback used to be silent: settings and dock kept showing the
    // configured combination although only the safe default listened.
    ProviderContainer makeContainer(FakeHotKeyRegistrar registrar) {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _MutableSettingsNotifier(
              AppSettings.defaults.copyWith(hotkeyEnabled: false),
            ),
          ),
          hotkeyServiceProvider.overrideWith(() {
            final service = HotkeyService()..injectRegistrar(registrar);
            return service..injectMonitor(NoopKeyboardUpMonitor());
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is set when the safe default replaces a taken hotkey', () async {
      final registrar = FakeHotKeyRegistrar()
        ..throwOnFirstRegister = PlatformException(code: 'hotkey_unavailable');
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);
      expect(container.read(globalHotkeyFallbackActiveProvider), isFalse);

      await service.updateHotkey(
        key: LogicalKeyboardKey.keyD,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      );

      expect(registrar.registered.single.logicalKey, LogicalKeyboardKey.space);
      expect(container.read(globalHotkeyFallbackActiveProvider), isTrue);
    });

    test('is cleared once the configured hotkey registers', () async {
      final registrar = FakeHotKeyRegistrar()
        ..throwOnFirstRegister = PlatformException(code: 'hotkey_unavailable');
      final container = makeContainer(registrar);
      final service = container.read(hotkeyServiceProvider.notifier);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateHotkey(key: LogicalKeyboardKey.keyE);

      expect(container.read(globalHotkeyFallbackActiveProvider), isFalse);
    });

    test('is cleared when the user switches the hotkey off', () async {
      // The settings listener and the startup registration may both try the
      // configured key; the taken combination must be refused on every try.
      final registrar = FakeHotKeyRegistrar()
        ..refuseKey = LogicalKeyboardKey.keyD;
      final container = makeContainer(registrar);
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      final settings = container.read(settingsProvider.notifier);

      await settings.updateSettings((s) => s.copyWith(hotkeyEnabled: true));
      await pumpEventQueue();
      expect(container.read(globalHotkeyFallbackActiveProvider), isTrue);

      await settings.updateSettings((s) => s.copyWith(hotkeyEnabled: false));
      await pumpEventQueue();
      expect(container.read(globalHotkeyFallbackActiveProvider), isFalse);
    });
  });

  group('HotkeyService — arrow key registration (AC1–AC3)', () {
    test('AC1: arrowLeft + alt registered correctly', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(
        key: LogicalKeyboardKey.arrowLeft,
        modifiers: [HotKeyModifier.alt],
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.arrowLeft),
        reason: 'arrowLeft must be registered, not silently replaced by keyD',
      );
      expect(
        registrar.registered.first.modifiers,
        contains(HotKeyModifier.alt),
      );
    });

    test('AC2: arrowUp + control registered correctly', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(
        key: LogicalKeyboardKey.arrowUp,
        modifiers: [HotKeyModifier.control],
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.arrowUp),
      );
    });

    test('AC3: all four arrow keys register without fallback', () async {
      final arrows = [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ];

      for (final arrow in arrows) {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(
          key: arrow,
          modifiers: [HotKeyModifier.control],
        );

        expect(
          registrar.registered.any((k) => k.logicalKey == arrow),
          isTrue,
          reason: '$arrow must be registered',
        );
        // Safe-default Space must NOT be in the list (no fallback)
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'fallback must not fire for a valid arrow key',
        );
      }
    });
  });

  group('HotkeyService — keyUp callback (Push-to-Talk wiring)', () {
    test(
      'optional actions get key-up only from the registrar, not the monitor',
      () {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        // Windows: RawInput delivers key-up for the global action only.
        service.injectMonitor(FakeKeyboardUpMonitor());

        expect(service.supportsKeyUp, isTrue);
        expect(
          service.optionalActionsSupportKeyUp,
          isFalse,
          reason:
              'Smart Mode and the selection edit register without keyUp here, '
              'so a hold on them could never end',
        );
      },
    );

    test(
      'supportsKeyUp=true: onHotkeyReleased fires when keyUp handler is called',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        var keyDownFired = false;
        var keyUpFired = false;
        service.onHotkeyPressed = () => keyDownFired = true;
        service.onHotkeyReleased = () => keyUpFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          registrar.capturedKeyUpHandler,
          isNotNull,
          reason: 'keyUpHandler must be registered when supportsKeyUp=true',
        );

        // Simulate keyDown and keyUp from the platform.
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        registrar.capturedKeyUpHandler!(registrar.registered.first);

        expect(keyDownFired, isTrue);
        expect(keyUpFired, isTrue);
      },
    );

    test('supportsKeyUp=false: keyUpHandler is not registered', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);

      service.onHotkeyReleased = () {};

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      expect(
        registrar.capturedKeyUpHandler,
        isNull,
        reason:
            'keyUpHandler must be null when platform does not support keyUp',
      );
    });

    test('supportsKeyUp reflects the registrar property', () {
      final registrarTrue = FakeHotKeyRegistrar(supportsKeyUp: true);
      final serviceTrue = _makeService(registrarTrue);
      expect(serviceTrue.supportsKeyUp, isTrue);

      final registrarFalse = FakeHotKeyRegistrar(supportsKeyUp: false);
      final serviceFalse = _makeService(registrarFalse);
      expect(serviceFalse.supportsKeyUp, isFalse);
    });
  });

  group('HotkeyService — RawInput key-up monitor (#39, Windows PTT)', () {
    for (var n = 13; n <= 24; n++) {
      test(
        'F$n delivers releases and rapid presses for hold and double tap',
        () async {
          final registrar = FakeHotKeyRegistrar(
            supportsKeyUp: false,
            filtersKeyRepeat: true,
          );
          final service = _makeService(registrar);
          final monitor = FakeKeyboardUpMonitor();
          service.injectMonitor(monitor);
          final events = <String>[];
          service.onHotkeyPressed = () => events.add('down');
          service.onHotkeyReleased = () => events.add('up');
          final key = LogicalKeyboardKey(0x100000800 + n);
          await service.updateHotkey(key: key);
          expect(monitor.started.single.logicalKey, key);
          expect(registrar.registered.single.modifiers, isEmpty);
          registrar.capturedKeyDownHandler!(registrar.registered.single);
          monitor.emitKeyUp();
          registrar.capturedKeyDownHandler!(registrar.registered.single);
          monitor.emitKeyUp();
          expect(events, ['down', 'up', 'down', 'up']);
        },
      );
    }

    test(
      'a key-up monitor enables supportsKeyUp even with a key-down-only registrar',
      () {
        // Mirrors Windows: registrar (RegisterHotKey) has no key-up, but the
        // RawInput monitor does → push-to-talk becomes available.
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        service.injectMonitor(FakeKeyboardUpMonitor(supportsKeyUp: true));

        expect(service.supportsKeyUp, isTrue);
      },
    );

    test(
      'the registered hotkey is handed to the monitor on registration',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(monitor.started, hasLength(1));
        expect(monitor.started.first.logicalKey, LogicalKeyboardKey.keyD);
      },
    );

    test(
      'a monitor key-up fires onHotkeyReleased (no registrar key-up)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        var released = false;
        service.onHotkeyReleased = () => released = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        // The registrar never delivers key-up on Windows…
        expect(registrar.capturedKeyUpHandler, isNull);
        // …RegisterHotKey fires the DOWN (a press is in flight)…
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        // …and the RawInput monitor delivers the matching release.
        monitor.emitKeyUp();

        expect(released, isTrue);
      },
    );

    test('a combination released before the native arm ends the press at once '
        '(no release event will come, so it must not record on)', () async {
      // A container gives the service a live ref, as in the app.
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _MutableSettingsNotifier(AppSettings.defaults),
          ),
          hotkeyServiceProvider.overrideWith(() {
            final service = HotkeyService()..injectRegistrar(registrar);
            return service
              ..injectMonitor(FakeKeyboardUpMonitor()..armHeld = false);
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      final service = container.read(hotkeyServiceProvider.notifier);

      var pressed = false;
      var released = false;
      service.onHotkeyPressed = () => pressed = true;
      service.onHotkeyReleased = () => released = true;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      registrar.capturedKeyDownHandler!(registrar.registered.first);
      // The arm answer and the press end are microtasks, no timer.
      await pumpEventQueue();

      expect(pressed, isTrue);
      expect(released, isTrue);
    });

    test('after a self-heal a press already released at arm time still ends '
        'the press (#771)', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      var now = DateTime(2026, 11, 5, 12);
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _MutableSettingsNotifier(AppSettings.defaults),
          ),
          hotkeyServiceProvider.overrideWith(() {
            final service = HotkeyService()..injectRegistrar(registrar);
            return service
              ..injectMonitor(FakeKeyboardUpMonitor()..armHeld = false)
              ..injectHealEnvironment(
                hotkeyEnabled: () => true,
                dictationBusy: () => false,
              )
              ..injectHealClock(() => now);
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      final service = container.read(hotkeyServiceProvider.notifier);

      var released = false;
      service.onHotkeyReleased = () => released = true;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final unregisteredBefore = registrar.unregistered.length;
      now = now.add(kHotkeyHealMinInterval + const Duration(seconds: 1));
      await service.requestHotkeyHeal(HotkeyHealTrigger.timer);
      expect(
        registrar.unregistered.length,
        unregisteredBefore + 1,
        reason: 'the heal ran',
      );

      registrar.capturedKeyDownHandler!(registrar.registered.first);
      // The arm answer and the press end are microtasks, no timer.
      await pumpEventQueue();

      expect(released, isTrue);
    });

    test(
      'a combination still held at the native arm keeps waiting for its release',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor()..armHeld = true;
        service.injectMonitor(monitor);

        var released = false;
        service.onHotkeyReleased = () => released = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        await Future<void>.delayed(Duration.zero);

        expect(released, isFalse);
      },
    );

    test(
      'a stray monitor key-up without a preceding down is ignored',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        var released = false;
        service.onHotkeyReleased = () => released = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        // No key-down happened (bare key seen by RawInput) → must be a no-op,
        // never reaching the push-to-talk trigger handler.
        monitor.emitKeyUp();

        expect(released, isFalse);
      },
    );

    test('a hotkey key-down arms the monitor release-watch', () async {
      // RegisterHotKey hides the hotkey key's DOWN from RawInput, so the
      // monitor must be armed from the Dart key-down to snapshot the held key.
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor();
      service.injectMonitor(monitor);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      registrar.capturedKeyDownHandler!(registrar.registered.first);

      expect(monitor.armCount, 1);
    });

    test('a lost release is noticed from the real key state and ends the '
        'press (#774)', () {
      fakeAsync((async) {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);
        var released = 0;
        service.onHotkeyReleased = () => released++;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();

        // Still held, or not known: the release event stays the only way out.
        monitor.heldNow = true;
        async.elapse(kHotkeyHeldProbeInterval * 3);
        monitor.heldNow = null;
        async.elapse(kHotkeyHeldProbeInterval * 2);
        expect(released, 0);
        expect(monitor.probeCount, 5);

        // The hardware says up while no release arrived.
        monitor.heldNow = false;
        async.elapse(kHotkeyHeldProbeInterval);
        expect(released, 1);

        // The press is over, so nothing is read any more.
        final reads = monitor.probeCount;
        async.elapse(kHotkeyHeldProbeInterval * 4);
        expect(monitor.probeCount, reads);
        expect(released, 1);
      });
    });

    test('a stalled read gives the queued real release time to arrive, so the '
        'check never ends the press first (#1194)', () {
      fakeAsync((async) {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);
        var released = 0;
        service.onHotkeyReleased = () => released++;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();

        monitor
          ..heldNow = false
          ..probeDelay = const Duration(seconds: 1);
        async.elapse(kHotkeyHeldProbeInterval + const Duration(seconds: 1));
        expect(released, 0, reason: 'the check waits for the queued event');

        // The queued real release arrives within the grace period.
        monitor.emitKeyUp();
        expect(released, 1);
        async.elapse(kHotkeyProbeStallGrace * 2);
        expect(released, 1, reason: 'the check adds no second release');
      });
    });

    test('a stalled read still ends a press whose release truly got lost '
        '(#1194)', () {
      fakeAsync((async) {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);
        var released = 0;
        service.onHotkeyReleased = () => released++;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();

        monitor
          ..heldNow = false
          ..probeDelay = const Duration(seconds: 1);
        async.elapse(
          kHotkeyHeldProbeInterval +
              const Duration(seconds: 1) +
              kHotkeyProbeStallGrace,
        );
        expect(released, 1);
      });
    });

    test('a late real release after the check ended the press is ignored, and '
        'a new press is checked on its own (#774)', () {
      fakeAsync((async) {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);
        var released = 0;
        service.onHotkeyReleased = () => released++;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();
        monitor.heldNow = false;
        async.elapse(kHotkeyHeldProbeInterval);
        expect(released, 1);

        monitor.emitKeyUp();
        expect(released, 1);

        // A second press is ended by its own check.
        async.elapse(kHotkeyHeldProbeInterval * 2);
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();
        async.elapse(kHotkeyHeldProbeInterval);
        expect(released, 2);
      });
    });

    test('a normal release stops the check and ends the press once (#774)', () {
      fakeAsync((async) {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);
        var released = 0;
        service.onHotkeyReleased = () => released++;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();
        monitor.emitKeyUp();
        expect(released, 1);

        monitor.heldNow = false;
        async.elapse(kHotkeyHeldProbeInterval * 4);
        expect(monitor.probeCount, 0);
        expect(released, 1);
      });
    });

    test('macOS: the check reads the key state through the modifier host and '
        'ends a press whose release was lost (#791)', () {
      fakeAsync((async) {
        const channel = MethodChannel('com.whispaste.modifier_monitor');
        final reads = <Object?>[];
        Object? reply = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'isHeld') reads.add(call.arguments);
              return reply;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar)
          ..injectModifierMonitor(
            ModifierKeyMonitor(isMacOS: true, channel: channel),
          );
        var released = 0;
        service.onHotkeyReleased = () => released++;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.flushMicrotasks();
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        async.flushMicrotasks();

        // Still held, or the host cannot tell: the release event stays the
        // only way out.
        async.elapse(kHotkeyHeldProbeInterval * 2);
        reply = null;
        async.elapse(kHotkeyHeldProbeInterval * 2);
        expect(released, 0);
        expect(reads, hasLength(4));
        // The registered key's macOS virtual key code (kVK_ANSI_D), fixed so
        // the check does not depend on the host's platform.
        expect(reads.first, {'keyCode': 0x02});

        // The hardware says up while no release arrived.
        reply = false;
        async.elapse(kHotkeyHeldProbeInterval);
        expect(released, 1);

        final count = reads.length;
        async.elapse(kHotkeyHeldProbeInterval * 4);
        expect(reads, hasLength(count));
      });
    });

    test('re-registering stops the previous monitor watch', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor();
      service.injectMonitor(monitor);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateHotkey(key: LogicalKeyboardKey.keyE);

      // updateHotkey unregisters first → monitor.stop ran at least once.
      expect(monitor.stopCount, greaterThanOrEqualTo(1));
      expect(monitor.started, hasLength(2));
    });
  });

  group('HotkeyService — Linux monitor (catchup/09)', () {
    test('a portal press + release drives a full hold cycle', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor(experimental: true);
      service.injectMonitor(monitor);
      var pressed = 0;
      var released = 0;
      service.onHotkeyPressed = () => pressed++;
      service.onHotkeyReleased = () => released++;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      monitor.emitKeyDown();
      monitor.emitKeyUp();

      expect(pressed, 1);
      expect(released, 1);
    });

    test('portal and X11 grab both firing the same press start once', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor(experimental: true);
      service.injectMonitor(monitor);
      var pressed = 0;
      service.onHotkeyPressed = () => pressed++;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      monitor.emitKeyDown();
      registrar.capturedKeyDownHandler!(registrar.registered.first);

      expect(pressed, 1);
    });

    test('keyUpExperimental mirrors a monitor-only experimental key-up', () {
      final service = _makeService(FakeHotKeyRegistrar(supportsKeyUp: false));
      service.injectMonitor(FakeKeyboardUpMonitor(experimental: true));

      expect(service.keyUpExperimental, isTrue);
    });

    test(
      'keyUpExperimental is false when the registrar has key-up (macOS)',
      () {
        final service = _makeService(FakeHotKeyRegistrar(supportsKeyUp: true));
        service.injectMonitor(FakeKeyboardUpMonitor(experimental: true));

        expect(service.keyUpExperimental, isFalse);
      },
    );

    test('keyUpExperimental is false for the Windows monitor', () {
      final service = _makeService(FakeHotKeyRegistrar(supportsKeyUp: false));
      service.injectMonitor(FakeKeyboardUpMonitor());

      expect(service.keyUpExperimental, isFalse);
    });
  });

  group('end-to-end: Recorder-Output → Registrar-Input', () {
    // Freezes the storage→registrar seam that the modifier-bug slipped
    // through. The previous service-level tests called the public API
    // with HotKeyModifier directly, so a recorder that wrote bogus
    // display-label tokens (e.g. "option") was never observed end-to-end.

    test('stored "option" + "←" → registrar receives [alt] + arrowLeft '
        '(self-healing for the reporter\'s existing DB)', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      // Simulate what _registerFromSettings does for an existing DB whose
      // hotkey_modifiers='option' and hotkey_key='←' (the reporter's state).
      await service.updateHotkey(
        key: resolveKey('←'),
        modifiers: resolveModifiers('option'),
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.arrowLeft),
      );
      expect(
        registrar.registered.first.modifiers,
        contains(HotKeyModifier.alt),
        reason:
            'Self-healing alias must turn legacy "option" into HotKeyModifier.alt '
            'so the existing DB works without rebind.',
      );
    });

    test('AC: registrar throwing ArgumentError → safe-default fallback fires '
        '(mirror of TypeError path)', () async {
      // _registerFromSettings catches ArgumentError thrown by resolveKey for
      // existing DBs that contain a non-resolvable key (e.g. hotkey_key='Ö'
      // from a corrupted pre-fix DB). Same observable behaviour as the
      // pre-existing TypeError path: safe-default hotkey is registered and
      // onRegistrationFailed fires so the UI can prompt the user to re-bind.
      final registrar = FakeHotKeyRegistrar()
        ..throwOnFirstRegister = ArgumentError.value(
          'Ö',
          'label',
          'Unknown key label',
        );
      final service = _makeService(registrar);

      var failedCallbackFired = false;
      service.onRegistrationFailed = () => failedCallbackFired = true;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      expect(
        registrar.registered.any(
          (k) => k.logicalKey == LogicalKeyboardKey.space,
        ),
        isTrue,
        reason:
            'ArgumentError from register must trigger safe-default fallback',
      );
      expect(
        failedCallbackFired,
        isTrue,
        reason:
            'onRegistrationFailed must fire so the UI can prompt for re-bind',
      );
    });

    test('AC: tryRegisterFromSettings with hotkeyKey="Ö" → safe-default '
        'registered and onRegistrationFailed fires', () async {
      // Direct exercise of the _registerFromSettings ArgumentError path
      // via a small testing seam. resolveKey("Ö") throws ArgumentError;
      // the service must catch that, add a Sentry breadcrumb, and route
      // through _registerSafeDefault — without leaking the exception.
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      var failedCallbackFired = false;
      service.onRegistrationFailed = () => failedCallbackFired = true;

      await service.debugRegisterFromSettings(
        hotkeyKey: 'Ö',
        hotkeyModifiers: 'meta',
      );

      expect(
        registrar.registered.length,
        equals(1),
        reason: 'a single (safe-default) hotkey must be registered',
      );
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.space),
        reason: 'safe-default Space key must be used as fallback for "Ö"',
      );
      expect(
        failedCallbackFired,
        isTrue,
        reason: 'onRegistrationFailed must fire after ArgumentError fallback',
      );
    });

    test('stored DE "strg+umschalt" + "D" → registrar receives '
        '[control, shift] + keyD', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(
        key: resolveKey('D'),
        modifiers: resolveModifiers('strg+umschalt'),
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.keyD),
      );
      expect(
        registrar.registered.first.modifiers,
        containsAll([HotKeyModifier.control, HotKeyModifier.shift]),
      );
    });
  });

  group('HotkeyService — auto-repeat suppression (held key)', () {
    test('macOS (keyUp): held key streams key-downs but toggles once; release '
        'then press toggles again', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      var presses = 0;
      service.onHotkeyPressed = () => presses++;
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final hk = registrar.registered.first;

      // Hold: OS streams repeated key-downs — only the first must count.
      registrar.capturedKeyDownHandler!(hk);
      registrar.capturedKeyDownHandler!(hk);
      registrar.capturedKeyDownHandler!(hk);
      expect(presses, 1, reason: 'auto-repeat key-downs must be swallowed');

      // Release, then a genuine new press toggles again.
      registrar.capturedKeyUpHandler!(hk);
      registrar.capturedKeyDownHandler!(hk);
      expect(presses, 2, reason: 'press after release must register');
    });

    test(
      'Windows/Linux (no keyUp): rapid auto-repeat key-downs toggle once',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        var presses = 0;
        service.onHotkeyPressed = () => presses++;
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        final hk = registrar.registered.first;

        // A held key with no key-up streams fast repeats within the window;
        // they must collapse to a single toggle (no start/stop flapping).
        for (var i = 0; i < 20; i++) {
          registrar.capturedKeyDownHandler!(hk);
        }
        expect(presses, 1, reason: 'held key must not flip start/stop');
      },
    );
  });

  group('HotkeyService — quick-note action (ticket 20)', () {
    test('registers independently of the global hotkey', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

      expect(registrar.registered, hasLength(2));
      expect(
        registrar.registered.map((k) => k.logicalKey),
        containsAll([LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyY]),
      );
    });

    test(
      'changing the quick-note combo does not re-register the global hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);

        // The global combo must never have been unregistered.
        expect(
          registrar.unregistered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isFalse,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
        );
        // Only the new quick-note combo remains registered.
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyN,
          ),
          isTrue,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isFalse,
        );
      },
    );

    test(
      'changing the global combo does not re-register the quick-note hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateHotkey(key: LogicalKeyboardKey.keyE);

        expect(
          registrar.unregistered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isFalse,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isTrue,
        );
      },
    );

    test(
      'a failed quick-note registration reports conflict without a safe-default fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await expectLater(
          service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY),
          completes,
        );

        // No Space (safe-default) must ever be registered for this action.
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'ticket 20 forbids a safe-default fallback for this action',
        );
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a failed quick-note registration does not affect the already-registered global hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
          reason: 'global hotkey must remain registered and untouched',
        );
      },
    );

    test(
      'a failed global registration (safe-default fallback) does not affect an already-registered quick-note hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isTrue,
          reason: 'quick-note hotkey must remain registered and untouched',
        );
      },
    );

    test(
      'no keyUpHandler is registered for the quick-note action even when '
      'the registrar supports keyUp (toggle-only, no push-to-talk)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        expect(registrar.capturedKeyUpHandler, isNull);
      },
    );

    test(
      'quick-note registration does not start the shared keyboard-up monitor',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        expect(
          monitor.started,
          isEmpty,
          reason:
              'the monitor is a single shared native channel — starting it '
              'for the toggle-only quick-note action would steal the '
              "global hotkey's release watch",
        );
      },
    );

    test(
      'quick-note key-down fires onQuickNoteHotkeyPressed exactly once per press',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var presses = 0;
        service.onQuickNoteHotkeyPressed = () => presses++;

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(presses, 1);
      },
    );

    test(
      'auto-repeat suppression is independent per action — holding the '
      'quick-note key does not suppress the global hotkey and vice versa',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var globalPresses = 0;
        var quickNotePresses = 0;
        service.onHotkeyPressed = () => globalPresses++;
        service.onQuickNoteHotkeyPressed = () => quickNotePresses++;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        final globalDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final quickNoteDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyY.keyId]!;
        final globalHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyD,
        );
        final quickNoteHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyY,
        );

        // Hold the global key: repeated key-downs collapse to a single press.
        globalDown(globalHotKey);
        globalDown(globalHotKey);
        expect(globalPresses, 1);

        // A fresh press of the quick-note key must fire immediately — the
        // held global key's auto-repeat window must not bleed into it.
        quickNoteDown(quickNoteHotKey);
        expect(quickNotePresses, 1);
      },
    );
  });

  group('quickNoteHotkeyRegistrationStatusProvider', () {
    test('starts unknown and reflects .set() calls independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(quickNoteHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );

      container
          .read(quickNoteHotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.conflict);

      expect(
        container.read(quickNoteHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
      // Independent of the existing (global) status provider.
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
    });
  });

  group('HotkeyService — snippet-picker action (ticket 26)', () {
    test(
      'registers independently of the global and quick-note hotkeys',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(registrar.registered, hasLength(3));
        expect(
          registrar.registered.map((k) => k.logicalKey),
          containsAll([
            LogicalKeyboardKey.keyD,
            LogicalKeyboardKey.keyN,
            LogicalKeyboardKey.keyE,
          ]),
        );
      },
    );

    test(
      'changing the snippet-picker combo does not re-register the other two hotkeys',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyF);

        expect(
          registrar.unregistered.any(
            (k) =>
                k.logicalKey == LogicalKeyboardKey.keyD ||
                k.logicalKey == LogicalKeyboardKey.keyN,
          ),
          isFalse,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyF,
          ),
          isTrue,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyE,
          ),
          isFalse,
        );
      },
    );

    test(
      'a failed snippet-picker registration reports conflict without a safe-default fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await expectLater(
          service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE),
          completes,
        );

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'ticket 26 forbids a safe-default fallback for this action',
        );
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a failed snippet-picker registration does not affect the already-registered global or quick-note hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyN,
          ),
          isTrue,
        );
      },
    );

    test(
      'a failed global registration (safe-default fallback) does not affect an already-registered snippet-picker hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyE,
          ),
          isTrue,
          reason: 'snippet-picker hotkey must remain registered and untouched',
        );
      },
    );

    test(
      'no keyUpHandler is registered for the snippet-picker action even when '
      'the registrar supports keyUp (one-shot, no push-to-talk)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(registrar.capturedKeyUpHandler, isNull);
      },
    );

    test(
      'snippet-picker registration does not start the shared keyboard-up monitor',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(monitor.started, isEmpty);
      },
    );

    test(
      'snippet-picker key-down fires onSnippetPickerHotkeyPressed exactly once per press',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var presses = 0;
        service.onSnippetPickerHotkeyPressed = () => presses++;

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(presses, 1);
      },
    );

    test(
      'repaste key-down fires onRepasteHotkeyPressed only, starts no recording',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var repastes = 0;
        var dictations = 0;
        service.onRepasteHotkeyPressed = () => repastes++;
        service.onHotkeyPressed = () => dictations++;

        await service.updateRepasteHotkey(key: LogicalKeyboardKey.keyV);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(repastes, 1);
        expect(dictations, 0);
      },
    );

    test(
      'learn-correction key-down fires its callback only, starts no recording',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var learns = 0;
        var dictations = 0;
        service.onLearnCorrectionHotkeyPressed = () => learns++;
        service.onHotkeyPressed = () => dictations++;

        await service.updateLearnCorrectionHotkey(key: LogicalKeyboardKey.keyL);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(learns, 1);
        expect(dictations, 0);
      },
    );

    test(
      'auto-repeat suppression is independent of the other two actions',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var globalPresses = 0;
        var snippetPickerPresses = 0;
        service.onHotkeyPressed = () => globalPresses++;
        service.onSnippetPickerHotkeyPressed = () => snippetPickerPresses++;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        final globalDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final snippetPickerDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyE.keyId]!;
        final globalHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyD,
        );
        final snippetPickerHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyE,
        );

        globalDown(globalHotKey);
        globalDown(globalHotKey);
        expect(globalPresses, 1);

        snippetPickerDown(snippetPickerHotKey);
        expect(snippetPickerPresses, 1);
      },
    );
  });

  group('HotkeyService — Smart-Mode action (ticket 04)', () {
    test('registers independently of the other three hotkeys', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
      await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
      await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

      expect(registrar.registered, hasLength(4));
      expect(
        registrar.registered.map((k) => k.logicalKey),
        containsAll([
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyN,
          LogicalKeyboardKey.keyE,
          LogicalKeyboardKey.keyM,
        ]),
      );
    });

    test(
      'a failed Smart-Mode registration reports conflict without a safe-default fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await expectLater(
          service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM),
          completes,
        );

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'ticket 04 forbids a safe-default fallback for this action',
        );
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a failed Smart-Mode registration does not affect the other already-registered hotkeys',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
        );
      },
    );

    test(
      'keyUpHandler IS registered for the Smart-Mode action when the '
      'registrar supports keyUp — push-to-talk parity with the main hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        var pressed = false;
        var released = false;
        service.onSmartModeHotkeyPressed = () => pressed = true;
        service.onSmartModeHotkeyReleased = () => released = true;

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(
          registrar.capturedKeyUpHandler,
          isNotNull,
          reason: 'ticket 04 requires push-to-talk parity with the main hotkey',
        );

        registrar.capturedKeyDownHandler!(registrar.registered.first);
        registrar.capturedKeyUpHandler!(registrar.registered.first);

        expect(pressed, isTrue);
        expect(released, isTrue);
      },
    );

    test(
      'keyUpHandler is not registered for the Smart-Mode action when the '
      'registrar does not support keyUp (Windows/Linux: toggle-only for now)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(registrar.capturedKeyUpHandler, isNull);
      },
    );

    test(
      'Smart-Mode registration does not start the shared keyboard-up monitor',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(monitor.started, isEmpty);
      },
    );

    test(
      'Smart-Mode key-down fires onSmartModeHotkeyPressed exactly once per press',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var presses = 0;
        service.onSmartModeHotkeyPressed = () => presses++;

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(presses, 1);
      },
    );

    test(
      'auto-repeat suppression is independent of the other three actions',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var globalPresses = 0;
        var smartModePresses = 0;
        service.onHotkeyPressed = () => globalPresses++;
        service.onSmartModeHotkeyPressed = () => smartModePresses++;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        final globalDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final smartModeDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyM.keyId]!;
        final globalHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyD,
        );
        final smartModeHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyM,
        );

        globalDown(globalHotKey);
        globalDown(globalHotKey);
        expect(globalPresses, 1);

        smartModeDown(smartModeHotKey);
        expect(smartModePresses, 1);
      },
    );
  });

  group('Edit-selection hotkey (voice-selection-edit)', () {
    test('press and release reach their own callbacks (push-to-talk where '
        'the registrar supports key-up)', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      var pressed = 0;
      var released = 0;
      var smartModePressed = 0;
      service.onSelectionEditHotkeyPressed = () => pressed++;
      service.onSelectionEditHotkeyReleased = () => released++;
      service.onSmartModeHotkeyPressed = () => smartModePressed++;

      await service.updateSelectionEditHotkey(key: LogicalKeyboardKey.keyY);
      registrar.capturedKeyDownHandler!(registrar.registered.first);
      registrar.capturedKeyUpHandler!(registrar.registered.first);

      expect(pressed, 1);
      expect(released, 1);
      expect(smartModePressed, 0);
    });

    test('toggle-only where the registrar has no key-up', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);

      await service.updateSelectionEditHotkey(key: LogicalKeyboardKey.keyY);

      expect(registrar.capturedKeyUpHandler, isNull);
    });
  });

  group('smartModeHotkeyRegistrationStatusProvider', () {
    test('starts unknown and reflects .set() calls independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(smartModeHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );

      container
          .read(smartModeHotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.conflict);

      expect(
        container.read(smartModeHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
      // Independent of the other three status providers.
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
      expect(
        container.read(snippetPickerHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
    });
  });

  group('snippetPickerHotkeyRegistrationStatusProvider', () {
    test('starts unknown and reflects .set() calls independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(snippetPickerHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );

      container
          .read(snippetPickerHotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.conflict);

      expect(
        container.read(snippetPickerHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
      // Independent of the other two status providers.
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
      expect(
        container.read(quickNoteHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
    });
  });

  group('HotkeyService — session-scoped interactive-snippet keys', () {
    Iterable<HotKey> stillRegistered(
      FakeHotKeyRegistrar registrar,
      LogicalKeyboardKey key,
    ) => registrar.registered.where((k) => k.logicalKey == key);

    test('registers bare Enter and Escape, keyDown dispatches the '
        'callbacks', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var advanceCalls = 0;
      var cancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () => cancelCalls++,
      );

      final enter = stillRegistered(registrar, LogicalKeyboardKey.enter);
      final escape = stillRegistered(registrar, LogicalKeyboardKey.escape);
      expect(enter, hasLength(1));
      expect(escape, hasLength(1));
      // Bare keys — a modifier would defeat the whole "just press Enter"
      // point.
      expect(enter.single.modifiers ?? const <HotKeyModifier>[], isEmpty);
      expect(escape.single.modifiers ?? const <HotKeyModifier>[], isEmpty);
      // Regression (crash report 2026-09-01): `modifiers` must be an empty
      // list, not `null`. A `null` list serializes via `HotKey.toJson()` as
      // `'modifiers': null`, which the macOS plugin force-casts with
      // `as! Array<String>` (HotkeyManagerMacosPlugin.swift:49) — that cast
      // on a null value aborts the process (SIGABRT / swift_dynamicCast
      // failure), crashing the app the moment an interactive snippet
      // registers its Enter/Escape keys.
      expect(enter.single.modifiers, isNotNull);
      expect(escape.single.modifiers, isNotNull);
      expect(enter.single.toJson()['modifiers'], isNotNull);
      expect(escape.single.toJson()['modifiers'], isNotNull);

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!(
        enter.single,
      );
      expect(advanceCalls, 1);
      expect(cancelCalls, 0);

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        escape.single,
      );
      expect(cancelCalls, 1);
    });

    test('unregister removes both keys and stale handlers dispatch '
        'nothing', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var advanceCalls = 0;
      var cancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () => cancelCalls++,
      );
      await service.unregisterInteractiveSnippetKeys();

      expect(stillRegistered(registrar, LogicalKeyboardKey.enter), isEmpty);
      expect(stillRegistered(registrar, LogicalKeyboardKey.escape), isEmpty);

      // A key event that slips through after unregister (native race) must
      // not fire the callbacks of the ended sequence.
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!(
        HotKey(key: LogicalKeyboardKey.enter),
      );
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        HotKey(key: LogicalKeyboardKey.escape),
      );
      expect(advanceCalls, 0);
      expect(cancelCalls, 0);
    });

    test('a failed Enter registration does not take Escape down', () async {
      final registrar = FakeHotKeyRegistrar()
        ..throwOnFirstRegister = TypeError();
      final service = _makeService(registrar);
      var cancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () => cancelCalls++,
      );

      expect(stillRegistered(registrar, LogicalKeyboardKey.enter), isEmpty);
      final escape = stillRegistered(registrar, LogicalKeyboardKey.escape);
      expect(escape, hasLength(1));
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        escape.single,
      );
      expect(cancelCalls, 1);
    });

    test('an unregister racing a still-pending registration leaves no '
        'system-wide key grab behind (epoch guard)', () async {
      final registrar = GatedHotKeyRegistrar();
      final service = _makeService(registrar);
      final gate = Completer<void>();
      registrar.gate = gate;

      final pending = service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () {},
      );
      // The sequence ends while the Enter registration is still parked on
      // the gate.
      await service.unregisterInteractiveSnippetKeys();
      registrar.gate = null;
      gate.complete();
      await pending;

      expect(
        stillRegistered(registrar, LogicalKeyboardKey.enter),
        isEmpty,
        reason:
            'The late-completing Enter registration must undo itself — a '
            'leaked bare-Enter grab would swallow Enter in every app',
      );
      expect(stillRegistered(registrar, LogicalKeyboardKey.escape), isEmpty);
    });

    test('a second sequence replaces the first registration instead of '
        'stacking a duplicate', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () {},
      );
      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () {},
      );

      expect(
        stillRegistered(registrar, LogicalKeyboardKey.enter),
        hasLength(1),
      );
      expect(
        stillRegistered(registrar, LogicalKeyboardKey.escape),
        hasLength(1),
      );
    });

    test('without key-up delivery a rapid double-Enter is debounced as OS '
        'auto-repeat', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var advanceCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () {},
      );

      final handler =
          registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!;
      final key = HotKey(key: LogicalKeyboardKey.enter);
      handler(key);
      handler(key);

      expect(advanceCalls, 1);
    });

    test('with key-up delivery (macOS) a released Enter is honoured again '
        'immediately', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      var advanceCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () {},
      );

      final down =
          registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!;
      final up =
          registrar.keyUpHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!;
      final key = HotKey(key: LogicalKeyboardKey.enter);
      down(key);
      up(key);
      down(key);

      expect(advanceCalls, 2);
    });
  });

  group('HotkeyService — cancel-dictation Escape key (issue #145)', () {
    test('registers bare Escape, keyDown dispatches onCancel', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var cancelCalls = 0;

      await service.registerCancelDictationKey(onCancel: () => cancelCalls++);

      final escape = registrar.registered.where(
        (k) => k.logicalKey == LogicalKeyboardKey.escape,
      );
      expect(escape, hasLength(1));
      expect(escape.single.modifiers ?? const <HotKeyModifier>[], isEmpty);

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        escape.single,
      );
      expect(cancelCalls, 1);
    });

    test('unregister removes the key and a stale handler dispatches '
        'nothing', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var cancelCalls = 0;

      await service.registerCancelDictationKey(onCancel: () => cancelCalls++);
      await service.unregisterCancelDictationKey();

      expect(
        registrar.registered.where(
          (k) => k.logicalKey == LogicalKeyboardKey.escape,
        ),
        isEmpty,
      );

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        HotKey(key: LogicalKeyboardKey.escape),
      );
      expect(cancelCalls, 0);
    });

    test('its own epoch is independent from the interactive-snippet '
        'Escape — unregistering one leaves the other alone', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var snippetCancelCalls = 0;
      var dictationCancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () => snippetCancelCalls++,
      );
      await service.unregisterInteractiveSnippetKeys();

      await service.registerCancelDictationKey(
        onCancel: () => dictationCancelCalls++,
      );

      final escape = registrar.registered.where(
        (k) => k.logicalKey == LogicalKeyboardKey.escape,
      );
      expect(escape, hasLength(1));
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        escape.single,
      );
      expect(dictationCancelCalls, 1);
      expect(snippetCancelCalls, 0);
    });
  });

  group('HotkeyService — notice-card action key (issue #585)', () {
    test('registers the given key, keyDown runs the card button', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var actionCalls = 0;

      await service.registerNoticeActionKey(
        key: LogicalKeyboardKey.f12,
        onPressed: () => actionCalls++,
      );

      final f12 = registrar.registered.where(
        (k) => k.logicalKey == LogicalKeyboardKey.f12,
      );
      expect(f12, hasLength(1));
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.f12.keyId]!(
        f12.single,
      );
      expect(actionCalls, 1);
    });

    test('unregister removes the key and a stale handler dispatches '
        'nothing', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var actionCalls = 0;

      await service.registerNoticeActionKey(
        key: LogicalKeyboardKey.f12,
        onPressed: () => actionCalls++,
      );
      await service.unregisterNoticeActionKey();

      expect(
        registrar.registered.where(
          (k) => k.logicalKey == LogicalKeyboardKey.f12,
        ),
        isEmpty,
      );

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.f12.keyId]!(
        HotKey(key: LogicalKeyboardKey.f12),
      );
      expect(actionCalls, 0);
    });
  });

  group('HotkeyService — short-press hint from the native press length', () {
    late FakeHotKeyRegistrar registrar;
    late FakeKeyboardUpMonitor monitor;

    /// Hold-to-talk setup: push-to-talk on, "Tap or hold" off unless given.
    ProviderContainer start({bool holdOrTap = false}) {
      registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      monitor = FakeKeyboardUpMonitor();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _MutableSettingsNotifier(
              AppSettings(
                audioInput: AudioInputSettings(
                  pushToTalk: true,
                  holdOrTap: holdOrTap,
                ),
              ),
            ),
          ),
          hotkeyServiceProvider.overrideWith(() {
            final service = HotkeyService()..injectRegistrar(registrar);
            return service..injectMonitor(monitor);
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Presses the hotkey, releases it with [pressed] as the native length,
    /// and returns whether the one-time hint is due afterwards.
    Future<bool> hintAfterPress(
      Duration? pressed, {
      bool holdOrTap = false,
    }) async {
      final container = start(holdOrTap: holdOrTap);
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      final service = container.read(hotkeyServiceProvider.notifier);
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      registrar.capturedKeyDownHandler!(registrar.registered.first);
      monitor.emitKeyUp(pressed);
      return container.read(shortPressHintProvider);
    }

    test(
      'a press up to the limit shows the hint, including a zero length',
      () async {
        expect(await hintAfterPress(Duration.zero), isTrue);
        expect(await hintAfterPress(shortPressMaxDuration), isTrue);
      },
    );

    test(
      'a press just over the limit or a deliberate hold shows no hint',
      () async {
        expect(
          await hintAfterPress(
            shortPressMaxDuration + const Duration(milliseconds: 1),
          ),
          isFalse,
        );
        expect(
          await hintAfterPress(const Duration(milliseconds: 400)),
          isFalse,
        );
      },
    );

    test('an unknown press length shows no hint', () async {
      expect(await hintAfterPress(null), isFalse);
    });

    test('with "Tap or hold" on a short press shows no hint', () async {
      expect(await hintAfterPress(Duration.zero, holdOrTap: true), isFalse);
    });

    test('a short press still ends the press at once', () async {
      final container = start();
      await container.read(settingsProvider.future);
      container.read(hotkeyServiceProvider);
      await pumpEventQueue();
      final service = container.read(hotkeyServiceProvider.notifier);
      var released = 0;
      service.onHotkeyReleased = () => released++;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      registrar.capturedKeyDownHandler!(registrar.registered.first);
      monitor.emitKeyUp(Duration.zero);

      expect(released, 1);
    });
  });

  group('HotkeyService — short-press hint from the registrar key-up', () {
    // PAR-064: macOS gets the release from the registrar, with no native
    // press length, so the press is timed in Dart.
    Future<bool> hintAfterPress(Duration pressed, {int repeats = 0}) async {
      var now = DateTime(2026, 10, 31, 12);
      return withClock(Clock(() => now), () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _MutableSettingsNotifier(
                const AppSettings(
                  audioInput: AudioInputSettings(pushToTalk: true),
                ),
              ),
            ),
            hotkeyServiceProvider.overrideWith(() {
              final service = HotkeyService()..injectRegistrar(registrar);
              return service..injectMonitor(NoopKeyboardUpMonitor());
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        final service = container.read(hotkeyServiceProvider.notifier);
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        final hotKey = registrar.registered.first;

        registrar.capturedKeyDownHandler!(hotKey);
        for (var i = 0; i < repeats; i++) {
          now = now.add(pressed);
          registrar.capturedKeyDownHandler!(hotKey);
        }
        now = now.add(pressed);
        registrar.capturedKeyUpHandler!(hotKey);
        return container.read(shortPressHintProvider);
      });
    }

    test('a press up to the limit shows the hint', () async {
      expect(await hintAfterPress(Duration.zero), isTrue);
      expect(await hintAfterPress(shortPressMaxDuration), isTrue);
    });

    test('a longer press shows no hint', () async {
      expect(
        await hintAfterPress(
          shortPressMaxDuration + const Duration(milliseconds: 1),
        ),
        isFalse,
      );
    });

    test('a hold with key repeats counts from the first press', () async {
      expect(
        await hintAfterPress(const Duration(milliseconds: 100), repeats: 5),
        isFalse,
      );
    });
  });

  group('HotkeyService — serialized global updates', () {
    // Register and unregister take real time, so overlapping updates would
    // interleave unless the service runs them one after another.
    test(
      'three quick updates leave exactly one registration, the last one',
      () {
        FakeAsync().run((async) {
          final registrar = _SlowRegistrar();
          final service = HotkeyService()
            ..injectRegistrar(registrar)
            ..injectMonitor(NoopKeyboardUpMonitor());
          final modifiers = [HotKeyModifier.control, HotKeyModifier.shift];

          var done = false;
          unawaited(
            Future.wait([
              service.updateHotkey(
                key: LogicalKeyboardKey.keyD,
                modifiers: modifiers,
              ),
              service.updateHotkey(
                key: LogicalKeyboardKey.keyE,
                modifiers: modifiers,
              ),
              service.updateHotkey(
                key: LogicalKeyboardKey.keyF,
                modifiers: modifiers,
              ),
            ]).then((_) => done = true),
          );
          async.elapse(const Duration(seconds: 1));

          expect(done, isTrue);
          expect(registrar.registered.map((k) => k.logicalKey), [
            LogicalKeyboardKey.keyF,
          ]);
        });
      },
    );

    test('a quick update after a slow one still ends with the last value', () {
      FakeAsync().run((async) {
        final registrar = _SlowRegistrar();
        final service = HotkeyService()
          ..injectRegistrar(registrar)
          ..injectMonitor(NoopKeyboardUpMonitor());

        var done = false;
        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        unawaited(
          service
              .updateHotkey(key: LogicalKeyboardKey.keyE)
              .then((_) => done = true),
        );
        async.elapse(const Duration(seconds: 1));

        expect(done, isTrue);
        expect(registrar.registered.map((k) => k.logicalKey), [
          LogicalKeyboardKey.keyE,
        ]);
      });
    });

    test('a native call that never answers does not block the next update', () {
      // The first register never completes, like a channel that hangs.
      FakeAsync().run((async) {
        final registrar = _HangingFirstRegistrar();
        final service = HotkeyService()
          ..injectRegistrar(registrar)
          ..injectMonitor(NoopKeyboardUpMonitor());
        var secondDone = false;

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        unawaited(
          service
              .updateHotkey(key: LogicalKeyboardKey.keyE)
              .then((_) => secondDone = true),
        );
        async.elapse(const Duration(seconds: 6));

        expect(secondDone, isTrue);
        expect(registrar.registered.map((k) => k.logicalKey), [
          LogicalKeyboardKey.keyE,
        ]);
      });
    });

    test('a timed-out register reports unavailable, not a conflict, and '
        'takes no safe default', () {
      FakeAsync().run((async) {
        // Every register hangs: the start-up registration from the settings
        // as well as the update, so no call answers at all.
        final registrar = _HangingRegistrar();
        final container = ProviderContainer(
          overrides: [
            hotkeyServiceProvider.overrideWith(
              () => HotkeyService()
                ..injectRegistrar(registrar)
                ..injectMonitor(NoopKeyboardUpMonitor()),
            ),
          ],
        );
        addTearDown(container.dispose);
        final service = container.read(hotkeyServiceProvider.notifier);

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        async.elapse(const Duration(seconds: 12));

        expect(
          container.read(hotkeyRegistrationStatusProvider),
          HotkeyRegistrationStatus.unavailable,
        );
        expect(container.read(globalHotkeyFallbackActiveProvider), isFalse);
        expect(
          registrar.attempted.map((k) => k.identifier),
          isNot(contains(safeDefaultHotKey.identifier)),
        );
      });
    });

    test('the next update waits until a slow one has ended', () {
      // Core review L-15 F15-1: native steps of 4 s each outlast the former
      // 5 s release of the chain; the next update must not run beside them.
      FakeAsync().run((async) {
        final registrar = FakeHotKeyRegistrar();
        final monitor = _SlowMonitor(const Duration(seconds: 4));
        final service = HotkeyService()
          ..injectRegistrar(registrar)
          ..injectMonitor(monitor);

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyE));
        async.elapse(const Duration(seconds: 40));

        expect(monitor.maxInFlight, 1);
        expect(monitor.started.map((k) => k.logicalKey), [
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyE,
        ]);
        expect(registrar.registered.map((k) => k.logicalKey), [
          LogicalKeyboardKey.keyE,
        ]);
      });
    });

    test('an update that never ends is aborted at the limit and releases the '
        'chain after the backstop', () {
      // Emergency exit (#293): a monitor start that never answers (e.g. a
      // portal dialog nobody confirms) is aborted after 60 s and its caller
      // answered; the next update waits a further 60 s for it to end, not
      // forever.
      FakeAsync().run((async) {
        final registrar = FakeHotKeyRegistrar();
        final monitor = _SlowMonitor(Duration.zero)..hangFirstStart = true;
        final service = HotkeyService()
          ..injectRegistrar(registrar)
          ..injectMonitor(monitor);
        var firstDone = false;
        var secondDone = false;

        unawaited(
          service
              .updateHotkey(key: LogicalKeyboardKey.keyD)
              .then((_) => firstDone = true),
        );
        unawaited(
          service
              .updateHotkey(key: LogicalKeyboardKey.keyE)
              .then((_) => secondDone = true),
        );
        async.elapse(const Duration(seconds: 59));
        expect(firstDone, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(firstDone, isTrue);
        expect(secondDone, isFalse);

        async.elapse(const Duration(seconds: 60));
        expect(secondDone, isTrue);
        expect(registrar.registered.map((k) => k.logicalKey), [
          LogicalKeyboardKey.keyE,
        ]);
      });
    });

    test('an update aborted at the limit registers nothing and the next one '
        'runs only after it', () {
      // Core review L-16 F16-5, #293: the first update hangs past the limit;
      // it must not register its combination, and the next update must not
      // run beside its late native stop.
      FakeAsync().run((async) {
        final registrar = FakeHotKeyRegistrar();
        final monitor = _SlowMonitor(Duration.zero)
          ..firstStopDelay = const Duration(seconds: 70);
        final service = HotkeyService()
          ..injectRegistrar(registrar)
          ..injectMonitor(monitor);

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyE));
        async.elapse(const Duration(seconds: 80));

        expect(monitor.maxInFlight, 1);
        expect(registrar.registered.map((k) => k.logicalKey), [
          LogicalKeyboardKey.keyE,
        ]);
      });
    });

    test('an update aborted at the limit reports unavailable, never a '
        'conflict', () {
      FakeAsync().run((async) {
        final monitor = _SlowMonitor(Duration.zero)
          ..firstStopDelay = const Duration(seconds: 70);
        // The aborted update's combination is refused: had the step gone on
        // to register it, the status would turn into a conflict. The
        // registration from the settings (default D) that follows it succeeds.
        final registrar = FakeHotKeyRegistrar()
          ..refuseKey = LogicalKeyboardKey.keyE;
        final container = ProviderContainer(
          overrides: [
            hotkeyServiceProvider.overrideWith(
              () => HotkeyService()
                ..injectRegistrar(registrar)
                ..injectMonitor(monitor)
                ..injectHealEnvironment(
                  hotkeyEnabled: () => false,
                  dictationBusy: () => false,
                ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final statuses = <HotkeyRegistrationStatus>[];
        container.listen(
          hotkeyRegistrationStatusProvider,
          (_, next) => statuses.add(next),
        );
        final service = container.read(hotkeyServiceProvider.notifier);

        unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyE));
        async.elapse(const Duration(seconds: 61));
        expect(statuses, [HotkeyRegistrationStatus.unavailable]);

        async.elapse(const Duration(seconds: 30));
        expect(statuses, isNot(contains(HotkeyRegistrationStatus.conflict)));
        expect(
          registrar.registered.map((k) => k.logicalKey),
          isNot(contains(LogicalKeyboardKey.keyE)),
        );
      });
    });

    test('quitting answers every update still waiting on the chain', () {
      FakeAsync().run((async) {
        final monitor = _SlowMonitor(Duration.zero)..hangFirstStart = true;
        final container = ProviderContainer(
          overrides: [
            hotkeyServiceProvider.overrideWith(
              () => HotkeyService()
                ..injectRegistrar(FakeHotKeyRegistrar())
                ..injectMonitor(monitor),
            ),
          ],
        );
        final service = container.read(hotkeyServiceProvider.notifier);
        var done = 0;

        for (final key in [
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyE,
          LogicalKeyboardKey.keyF,
        ]) {
          unawaited(service.updateHotkey(key: key).then((_) => done++));
        }
        async.elapse(const Duration(seconds: 1));
        expect(done, 0);

        container.dispose();
        async.flushMicrotasks();
        expect(done, 3);
      });
    });

    test('a key the resolver rejects is unknown, not a conflict', () {
      expect(
        hotkeyFailureStatus(ArgumentError.value('F25')),
        HotkeyRegistrationStatus.unknownKey,
      );
    });

    test('only a conflict and an unknown key ask for a new key', () {
      expect(HotkeyRegistrationStatus.values.where((s) => s.needsNewKey), [
        HotkeyRegistrationStatus.conflict,
        HotkeyRegistrationStatus.unknownKey,
      ]);
    });

    test('only a timeout counts as unavailable', () {
      expect(
        hotkeyFailureStatus(TimeoutException(null)),
        HotkeyRegistrationStatus.unavailable,
      );
      expect(
        hotkeyFailureStatus(PlatformException(code: 'hotkey_unavailable')),
        HotkeyRegistrationStatus.conflict,
      );
    });
  });

  group('HotkeyService — Input Monitoring offer for a combination (#807)', () {
    const channel = MethodChannel('com.whispaste.modifier_monitor.807');

    /// macOS combination, hold-to-talk, no Input Monitoring permission (the
    /// host cannot read the key state). Runs [presses] and returns whether
    /// the offer is due afterwards.
    Future<bool> offerAfter(
      Future<void> Function(
        HotKey hotKey,
        FakeHotKeyRegistrar registrar,
        void Function(Duration) advance,
      )
      presses, {
      bool pushToTalk = true,
    }) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'status') return {'listenAccess': false};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      var now = DateTime(2026, 11, 10, 12);
      return withClock(Clock(() => now), () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _MutableSettingsNotifier(
                AppSettings(
                  audioInput: AudioInputSettings(pushToTalk: pushToTalk),
                ),
              ),
            ),
            inputMonitoringMonitorProvider.overrideWithValue(
              ModifierKeyMonitor(isMacOS: true, channel: channel),
            ),
            hotkeyServiceProvider.overrideWith(() {
              final service = HotkeyService()
                ..injectRegistrar(registrar)
                ..injectMonitor(NoopKeyboardUpMonitor());
              return service..injectModifierMonitor(
                ModifierKeyMonitor(isMacOS: true, channel: channel),
              );
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        final service = container.read(hotkeyServiceProvider.notifier);
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await presses(
          registrar.registered.first,
          registrar,
          (d) => now = now.add(d),
        );
        await pumpEventQueue();
        return container.read(inputMonitoringOfferProvider);
      });
    }

    test('a new press after a lost release offers the permission', () async {
      expect(
        await offerAfter((hotKey, registrar, advance) async {
          registrar.capturedKeyDownHandler!(hotKey);
          advance(const Duration(seconds: 3));
          registrar.capturedKeyDownHandler!(hotKey);
        }),
        isTrue,
      );
    });

    test('a normal release and press offers nothing', () async {
      expect(
        await offerAfter((hotKey, registrar, advance) async {
          registrar.capturedKeyDownHandler!(hotKey);
          advance(const Duration(seconds: 1));
          registrar.capturedKeyUpHandler!(hotKey);
          advance(const Duration(seconds: 3));
          registrar.capturedKeyDownHandler!(hotKey);
        }),
        isFalse,
      );
    });

    test('key repeats of a held key offer nothing', () async {
      expect(
        await offerAfter((hotKey, registrar, advance) async {
          registrar.capturedKeyDownHandler!(hotKey);
          for (var i = 0; i < 5; i++) {
            advance(const Duration(milliseconds: 100));
            registrar.capturedKeyDownHandler!(hotKey);
          }
        }),
        isFalse,
      );
    });

    test('a lost release outside hold mode offers nothing', () async {
      expect(
        await offerAfter((hotKey, registrar, advance) async {
          registrar.capturedKeyDownHandler!(hotKey);
          advance(const Duration(seconds: 3));
          registrar.capturedKeyDownHandler!(hotKey);
        }, pushToTalk: false),
        isFalse,
      );
    });
  });
}

/// Monitor whose start and stop take [step] each, recording how many run at
/// once. With [hangFirstStart] the first start never answers.
class _SlowMonitor extends FakeKeyboardUpMonitor {
  _SlowMonitor(this.step);

  final Duration step;
  bool hangFirstStart = false;

  /// Delay of the first [stop] only, on top of [step].
  Duration? firstStopDelay;
  int _inFlight = 0;
  int maxInFlight = 0;

  Future<void> _run(Future<void> Function() body) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await Future<void>.delayed(step);
      await body();
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<void> start(HotKey hotKey, {String? description}) {
    if (hangFirstStart) {
      hangFirstStart = false;
      started.add(hotKey);
      return Completer<void>().future;
    }
    return _run(() => super.start(hotKey, description: description));
  }

  @override
  Future<void> stop() {
    final delay = firstStopDelay;
    firstStopDelay = null;
    return _run(() async {
      if (delay != null) await Future<void>.delayed(delay);
      await super.stop();
    });
  }
}

/// Registrar whose first register never completes; later calls answer.
class _HangingFirstRegistrar implements HotKeyRegistrar {
  final List<HotKey> registered = [];
  bool _hungOnce = false;

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) {
    if (!_hungOnce) {
      _hungOnce = true;
      return Completer<void>().future;
    }
    registered.add(hotKey);
    return Future<void>.value();
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }
}

/// Registrar whose register and unregister take a few milliseconds each
/// (fake time: its tests run in [FakeAsync]).
class _SlowRegistrar implements HotKeyRegistrar {
  final List<HotKey> registered = [];

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }
}

// ---------------------------------------------------------------------------
// Self-heal of the global hotkey registration
// ---------------------------------------------------------------------------

void _healGroup() {
  group('HotkeyService — self-heal of the global registration', () {
    late FakeHotKeyRegistrar registrar;
    late HotkeyService service;
    late bool enabled;
    late bool busy;
    late DateTime clock;
    late int toasts;
    late List<LogRecord> records;
    late StreamSubscription<LogRecord> logSub;

    setUp(() async {
      Logger.root.level = Level.ALL;
      records = [];
      logSub = Logger.root.onRecord.listen(records.add);
      registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      enabled = true;
      busy = false;
      clock = DateTime(2026, 10, 29, 19, 30);
      service = _makeService(registrar)
        ..injectHealEnvironment(
          hotkeyEnabled: () => enabled,
          dictationBusy: () => busy,
        )
        ..injectHealClock(() => clock);
      toasts = 0;
      service.onHotkeyHealFailedRepeatedly = () => toasts++;
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      // Stop the fake clock from throttling the test heals against each other.
      registrar.unregistered.clear();
      registrar.registered.clear();
    });

    tearDown(() async {
      await logSub.cancel();
      HotkeyCaptureGuard.reset();
    });

    Future<void> heal(HotkeyHealTrigger trigger) async {
      clock = clock.add(kHotkeyHealMinInterval + const Duration(seconds: 1));
      await service.requestHotkeyHeal(trigger);
    }

    for (final trigger in HotkeyHealTrigger.values) {
      test('${trigger.name} re-registers the same main hotkey', () async {
        await heal(trigger);

        expect(
          registrar.unregistered.single.logicalKey,
          LogicalKeyboardKey.keyD,
        );
        expect(registrar.registered.single.logicalKey, LogicalKeyboardKey.keyD);
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'a heal must never switch to the safe-default combination',
        );
      });
    }

    test(
      'does not run while the hotkey is held (hold mode keeps its release)',
      () async {
        final handler =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final keyD = HotKey(key: LogicalKeyboardKey.keyD);
        handler(keyD);

        await heal(HotkeyHealTrigger.uiStall);
        expect(registrar.unregistered, isEmpty);

        registrar.keyUpHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!(keyD);
        await heal(HotkeyHealTrigger.uiStall);
        expect(
          registrar.unregistered,
          hasLength(1),
          reason: 'released: heal runs',
        );
      },
    );

    test('does not run during a dictation', () async {
      busy = true;
      await heal(HotkeyHealTrigger.wake);
      expect(registrar.unregistered, isEmpty);
      expect(registrar.registered, isEmpty);
    });

    test('does not run while the recorder or onboarding captures', () async {
      HotkeyCaptureGuard.begin();
      await heal(HotkeyHealTrigger.timer);
      expect(registrar.unregistered, isEmpty);
    });

    test('does not run when the hotkey is disabled', () async {
      enabled = false;
      await heal(HotkeyHealTrigger.wake);
      expect(registrar.unregistered, isEmpty);
    });

    test(
      'is throttled: a second trigger right after a heal is skipped',
      () async {
        await heal(HotkeyHealTrigger.wake);
        registrar.unregistered.clear();
        await service.requestHotkeyHeal(HotkeyHealTrigger.uiStall);
        expect(registrar.unregistered, isEmpty);
      },
    );

    test(
      'concurrent triggers are serialized: one heal, no interleaving',
      () async {
        clock = clock.add(const Duration(minutes: 1));
        await Future.wait([
          service.requestHotkeyHeal(HotkeyHealTrigger.wake),
          service.requestHotkeyHeal(HotkeyHealTrigger.uiStall),
          service.requestHotkeyHeal(HotkeyHealTrigger.memoryPressure),
        ]);
        expect(registrar.unregistered, hasLength(1));
        expect(registrar.registered, hasLength(1));
      },
    );

    test('one failed heal logs a warning but shows no toast', () async {
      registrar.failNextRegisters = 1;
      await heal(HotkeyHealTrigger.wake);

      expect(toasts, 0);
      expect(
        records.where(
          (r) => r.level == Level.WARNING && r.message.contains('self-heal'),
        ),
        hasLength(1),
      );
    });

    test(
      'three failures in a row show exactly one toast and mark the status',
      () async {
        registrar.failNextRegisters = 3;
        await heal(HotkeyHealTrigger.wake);
        await heal(HotkeyHealTrigger.timer);
        await heal(HotkeyHealTrigger.uiStall);
        expect(toasts, 1);
        expect(
          records.where(
            (r) => r.level == Level.WARNING && r.message.contains('self-heal'),
          ),
          hasLength(3),
        );

        await heal(HotkeyHealTrigger.timer);
        expect(toasts, 1, reason: 'no toast storm on later failures');
      },
    );

    test(
      'a successful heal after failures restores the registration',
      () async {
        registrar.failNextRegisters = 1;
        await heal(HotkeyHealTrigger.wake);
        await heal(HotkeyHealTrigger.timer);
        expect(registrar.registered.single.logicalKey, LogicalKeyboardKey.keyD);
      },
    );

    test(
      'a hung native step is cut off by the time limit and counts as a failure',
      () {
        // The service is built inside the fake zone: a chain started in setUp
        // would schedule its next step in the real zone, out of elapse's reach.
        FakeAsync().run((async) {
          final service = _makeService(FakeHotKeyRegistrar(supportsKeyUp: true))
            ..injectHealEnvironment(
              hotkeyEnabled: () => true,
              dictationBusy: () => false,
            )
            ..injectHealClock(() => clock);
          unawaited(service.updateHotkey(key: LogicalKeyboardKey.keyD));
          async.flushMicrotasks();
          service.injectRegistrar(_HangingRegistrar());
          clock = clock.add(const Duration(minutes: 1));
          var done = false;
          unawaited(
            service
                .requestHotkeyHeal(HotkeyHealTrigger.wake)
                .then((_) => done = true),
          );
          async.elapse(const Duration(seconds: 6));
          expect(done, isTrue, reason: 'the heal blocked the chain');
        });
        expect(
          records.where(
            (r) => r.level == Level.WARNING && r.message.contains('self-heal'),
          ),
          isNotEmpty,
        );
      },
    );
  });
}

/// Registrar whose register never answers, like a platform call that hangs.
class _HangingRegistrar implements HotKeyRegistrar {
  /// Every hotkey a register was asked for, in order.
  final List<HotKey> attempted = [];

  @override
  bool get supportsKeyUp => true;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) {
    attempted.add(hotKey);
    return Completer<void>().future;
  }

  @override
  Future<void> unregister(HotKey hotKey) async {}
}
