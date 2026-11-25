/// Device evidence for the Input Monitoring journey on macOS (#1180): fresh
/// install → onboarding with the double tap → grant without a restart →
/// the double tap starts a dictation → the grant is withdrawn → the one
/// notice appears and the permissions row reads "missing".
///
/// Why the grant itself is simulated: macOS keeps Input Monitoring in the
/// system TCC database. Switching it on needs the user's password or Touch ID
/// in System Settings, and the database is protected by SIP, so no unattended
/// run can give the grant. Everything the app does with the grant goes
/// through one seam, the host channel `com.whispaste.modifier_monitor`
/// (`status` → `listenAccess`/`tapActive`, `requestListenAccess`, `start`,
/// `stop`, and the host's `event` calls). This test therefore runs in two
/// parts on the real Mac build:
///
/// 1. Real host: the native `ModifierKeyHost` of this build answers `status`
///    with a real `listenAccess` (CGPreflightListenEventAccess). A freshly
///    built, never granted binary reads "not granted", and the host then
///    refuses to start the event tap, so the app keeps the key combination.
/// 2. Simulated grant: a stand-in host on the same channel plays the system
///    (not granted → the user flips the switch → granted → revoked, with the
///    tap going dead like a real revoke). Everything above the channel is
///    the real app code: the onboarding hotkey page ([TriggerStep]), the
///    shared grant steps (`grantInputMonitoring`), the live grant poll,
///    [HotkeyService] with its observer start, double-tap fallback and
///    periodic health check, [ModifierKeyMonitor] with the real platform
///    channel codec, the [RecordingTriggerHandler] gesture logic and the
///    [PermissionsSection] row. Only the hotkey registrar (no system-wide
///    hotkey is taken during the test), the permission-helper panel (it
///    would open System Settings) and the recording itself (no microphone)
///    are stand-ins.
///
/// Run on the Mac (needs Xcode for the macOS build); Windows and Linux run
/// the journey and the "no grant there" check:
///   `wp-test.sh run <worktree> --host mac integration_test/input_monitoring_journey_test.dart`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:integration_test/integration_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/features/settings/sections/permissions_section.dart';
import 'package:whispaste/services/hotkey_heal_notice.dart'
    show hotkeyObserverLostNoticeProvider;
import 'package:whispaste/services/hotkey_observer_health.dart'
    show ObserverLossReason;
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/input_monitoring_offer.dart'
    show inputMonitoringMonitorProvider;
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/services/permission_helper_service.dart';
import 'package:whispaste/services/permissions/input_monitoring_status.dart';
import 'package:whispaste/services/permissions/permissions_overview_provider.dart';
import 'package:whispaste/services/recording_trigger_handler.dart';

const _hostChannel = MethodChannel('com.whispaste.modifier_monitor');

/// The helper panel gets its own channel name: the real panel would open
/// System Settings.
const _helperChannel = MethodChannel('whispaste/permission_helper_itest');

const _key = ModifierHotkey.rightMeta;

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Plays macOS behind the host channel: the Input Monitoring grant as a
/// switch the test flips, and the event tap that needs it.
class _SimulatedMac {
  bool granted = false;
  bool tapRunning = false;
  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'status':
        return {'listenAccess': granted, 'tapActive': tapRunning};
      case 'requestListenAccess':
        // A fresh install: the system prompt appears and is not answered
        // yet, so the grant is still missing when the call returns.
        return granted;
      case 'start':
        // Like CGEvent.tapCreate: a listen-only tap needs the grant.
        tapRunning = granted;
        return tapRunning;
      case 'stop':
        tapRunning = false;
        return null;
      case 'isHeld':
        return granted ? false : null;
      case 'globeKeyAction':
        return 'none';
    }
    return null;
  }

  /// The user switches WhisPaste on in System Settings.
  void grant() => granted = true;

  /// The user switches it off again: macOS disables the tap with it.
  void revoke() {
    granted = false;
    tapRunning = false;
  }

  /// Sends one host `event` through the real channel codec, the way the
  /// native tap delivers it.
  Future<void> event(String type, {required int atMs, int? pressMs}) async {
    final completer = Completer<void>();
    await _messenger.handlePlatformMessage(
      _hostChannel.name,
      _hostChannel.codec.encodeMethodCall(
        MethodCall('event', {'type': type, 'atMs': atMs, 'pressMs': ?pressMs}),
      ),
      (_) => completer.complete(),
    );
    await completer.future;
  }
}

class _SettingsNotifier extends SettingsNotifier {
  _SettingsNotifier(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Takes no system-wide hotkey during the test; macOS reports key-up.
class _Registrar implements HotKeyRegistrar {
  @override
  bool get supportsKeyUp => true;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

/// The recording as the trigger handler sees it; no microphone involved.
class _Recording {
  bool running = false;
  bool handsFree = false;
  int starts = 0;

  Future<void> start() async {
    starts++;
    running = true;
  }

  Future<void> stop() async => running = false;
}

/// Pumps until [done] holds or [timeout] passes; the app's own timers run in
/// real time meanwhile.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 5),
  String reason = '',
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out after ${timeout.inSeconds} s: $reason');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real host: a fresh build reads the grant and, without it, '
      'refuses the event tap', (tester) async {
    final monitor = ModifierKeyMonitor();
    final access = await monitor.listenAccess();
    if (!Platform.isMacOS) {
      // Windows and Linux have no such grant: nothing to read, no tap.
      expect(access, isNull);
      expect(await monitor.start(_key), isFalse);
      return;
    }
    expect(
      access,
      isNotNull,
      reason: 'the native ModifierKeyHost answers status with listenAccess',
    );
    if (access == false) {
      expect(
        await monitor.start(_key),
        isFalse,
        reason: 'without the grant the host must not start the tap',
      );
    } else {
      // This binary was granted by hand earlier; the refusal cannot be shown.
      debugPrint('Input Monitoring is granted for this build; refusal skipped');
      await monitor.stop();
    }
  });

  testWidgets(
    'journey: onboarding with the double tap, grant without a '
    'restart, double tap dictates, revoke shows the one notice',
    (tester) async {
      final mac = _SimulatedMac();
      _messenger.setMockMethodCallHandler(_hostChannel, mac.handle);
      addTearDown(
        () => _messenger.setMockMethodCallHandler(_hostChannel, null),
      );
      final helperCalls = <String>[];
      _messenger.setMockMethodCallHandler(_helperChannel, (call) async {
        helperCalls.add(call.method);
        return call.method == 'show' ? 'shown' : null;
      });
      addTearDown(
        () => _messenger.setMockMethodCallHandler(_helperChannel, null),
      );

      // The onboarding saved the double tap on the right ⌘ (fresh install).
      final settings = _SettingsNotifier(
        AppSettings.defaults.copyWithSections(
          hotkey: AppSettings.defaults.hotkey.copyWith(
            hotkeyDoubleTapKey: _key.name,
            hotkeyDoubleTap: true,
          ),
        ),
      );
      final helper = PermissionHelperService(
        channel: _helperChannel,
        isMacOS: true,
      );
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          hotkeyServiceProvider.overrideWith(
            () => HotkeyService()
              ..injectRegistrar(_Registrar())
              ..injectMonitor(NoopKeyboardUpMonitor())
              ..injectModifierMonitor(
                ModifierKeyMonitor(channel: _hostChannel),
              ),
          ),
          inputMonitoringMonitorProvider.overrideWithValue(
            ModifierKeyMonitor(channel: _hostChannel),
          ),
          permissionHelperProvider.overrideWithValue(helper),
          // Microphone and Auto-Paste are not part of this journey.
          permissionsOverviewProvider.overrideWithValue(const []),
          hotkeySecureInputProbeProvider.overrideWithValue(() async => false),
        ],
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) container.dispose();
      });
      await container.read(settingsProvider.future);

      // The app's wiring of the trigger (service_bootstrap.dart), with the
      // recording replaced.
      final recording = _Recording();
      final service = container.read(hotkeyServiceProvider.notifier);
      final trigger = RecordingTriggerHandler(
        startRecording: recording.start,
        stopRecording: recording.stop,
        toggleRecording: () =>
            recording.running ? recording.stop() : recording.start(),
        cancelRecording: recording.stop,
        pushToTalkEnabled: () => settings._settings.pushToTalk,
        registrarSupportsKeyUp: () => service.supportsKeyUp,
        doubleTapEnabled: () => settings._settings.hotkey.hotkeyDoubleTap,
        doubleTapLatches: () => true,
        singleKey: () => true,
        isRecording: () => recording.running,
        onHandsFreeChanged: (v) => recording.handsFree = v,
        nativeEventAt: () => service.nativeEventAt,
        nativePressed: () => service.nativePressed,
      );
      service
        ..onHotkeyPressed = trigger.onKeyDown
        ..onHotkeyReleased = trigger.onKeyUp
        ..onModifierOtherKey = trigger.onOtherKey;

      const size = Size(1280, 900);
      Widget app(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wpDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: size, disableAnimations: true),
            child: Scaffold(
              body: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        ),
      );

      // ── 1. Fresh install: the single key cannot listen yet ──
      await tester.pumpWidget(app(const TriggerStep()));
      await _pumpUntil(
        tester,
        () => container.read(doubleTapFallbackActiveProvider),
        reason: 'without the grant the stored combination stands in',
      );
      expect(mac.tapRunning, isFalse);
      await _pumpUntil(
        tester,
        () => find.byKey(kTriggerStepAccessExplainKey).evaluate().isNotEmpty,
        reason: 'the page explains the grant before asking for it',
      );
      expect(
        mac.calls,
        isNot(contains('requestListenAccess')),
        reason: 'explanation first: no system prompt before the tap',
      );

      // ── 2. "Allow Input Monitoring": system prompt, then the drag panel ──
      await tester.tap(find.byKey(kTriggerStepAccessGrantKey));
      await _pumpUntil(
        tester,
        () => find.byKey(kTriggerStepAccessMissingKey).evaluate().isNotEmpty,
        reason: 'the page says where to switch it on',
      );
      expect(mac.calls, contains('requestListenAccess'));
      expect(helperCalls, contains('show'));

      // ── 3. The user flips the switch; no restart ──
      mac.grant();
      await _pumpUntil(
        tester,
        () => find.byKey(kTriggerStepAccessGrantedKey).evaluate().isNotEmpty,
        reason: 'the live poll picks the grant up and confirms it',
      );
      expect(find.byKey(kTriggerStepAccessExplainKey), findsNothing);
      await _pumpUntil(
        tester,
        () =>
            mac.tapRunning && !container.read(doubleTapFallbackActiveProvider),
        reason: 'the single key takes over from the stand-in combination',
      );
      expect(helperCalls, contains('hide'), reason: 'the drag panel closes');
      expect(
        container.read(inputMonitoringStatusProvider),
        PermissionOverviewStatus.granted,
      );

      // ── 4. Double tap on the right ⌘ starts a hands-free dictation ──
      await mac.event('down', atMs: 10000);
      await mac.event('up', atMs: 10060, pressMs: 60);
      await mac.event('down', atMs: 10200);
      await mac.event('up', atMs: 10250, pressMs: 50);
      await _pumpUntil(
        tester,
        () => recording.running && recording.handsFree,
        reason: 'the double tap starts a latched dictation',
      );
      // The user ends the dictation before the grant is taken away (a running
      // dictation pauses the observer check).
      await recording.stop();

      // ── 5. Settings: the row reads "granted" ──
      await tester.pumpWidget(app(const PermissionsSection()));
      await tester.pump();
      const statusKey = ValueKey('permissions-input-monitoring-status');
      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(
        find.descendant(
          of: find.byKey(statusKey),
          matching: find.text(l10n.permissionRowGranted),
        ),
        findsOneWidget,
      );

      // ── 6. Revoke: the next health check finds it ──
      // Run at once instead of waiting for its 15 s timer: one test may take
      // at most 10 s (test-strategy §3b). That the timer runs on its own is
      // covered in `hotkey_observer_health_test`.
      mac.revoke();
      await service.checkObserverHealth();
      await _pumpUntil(
        tester,
        () => container.read(hotkeyObserverLostNoticeProvider) != null,
        reason: 'the observer check reports the withdrawn grant',
      );
      expect(
        container.read(hotkeyObserverLostNoticeProvider)!.reason,
        ObserverLossReason.permissionRevoked,
      );
      expect(container.read(doubleTapFallbackActiveProvider), isTrue);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(statusKey),
          matching: find.text(l10n.permissionRowMissing),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('permissions-input-monitoring-action')),
        findsOneWidget,
        reason: 'the row offers the same "Grant access" as the notice',
      );

      // The app's timers (heal, observer check, grant poll) end with it.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      disposed = true;
      await tester.pump();
    },
    // The simulated host plays macOS, so the journey runs on every system;
    // on the Mac it runs inside the real macOS build.
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
