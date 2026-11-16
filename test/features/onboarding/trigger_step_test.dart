/// Widget tests for [TriggerStep].
///
/// Covers:
/// 1. Push-to-Talk toggle: persists `pushToTalk`, disabled + tooltip when
///    the platform (`HotkeyService.supportsKeyUp`) doesn't support it.
/// 2. Hotkey rebind: opening the modal recorder via "Change", and the
///    embedded inline recorder in the confirmed-conflict branch.
/// 3. Conflict branch: warn-box + inline recorder visible, gone again once
///    the registration status flips back to success.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/config/settings_labels.dart' show singleKeyCap;
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        DoubleTapFallbackController,
        GlobalHotkeyFallbackController,
        HotKeyRegistrar,
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        HotkeyService,
        dictationHotkeyActivityProvider,
        doubleTapFallbackActiveProvider,
        globalHotkeyFallbackActiveProvider,
        hotkeyRegistrationStatusProvider,
        hotkeyServiceProvider;
import 'package:whispaste/services/input_monitoring_offer.dart'
    show inputMonitoringMonitorProvider;
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/services/permission_helper_service.dart';
import 'package:whispaste/services/permissions/permissions_overview_provider.dart'
    show PermissionOverviewStatus;
import 'package:whispaste/widgets/hotkey_recorder.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';
import 'package:whispaste/widgets/wp_keycap.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

class _FakeHotkeyStatusController extends HotkeyRegistrationStatusController {
  _FakeHotkeyStatusController(this._initial);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

/// Fake [HotKeyRegistrar] — mirrors `test/widgets/push_to_talk_toggle_test.dart`.
class _FakeRegistrar implements HotKeyRegistrar {
  const _FakeRegistrar({required this.supportsKeyUp});

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

/// [HotkeyService] whose `build()` never runs the real startup registration
/// flow (`Future.microtask` re-registering from settings). The real `build()`
/// would asynchronously re-register with the injected (non-throwing) fake
/// registrar and overwrite whatever [hotkeyRegistrationStatusProvider] value
/// a test seeded — TriggerStep only needs `supportsKeyUp` from this service;
/// the registration *status* is a separate, independently-faked provider.
class _NoopHotkeyService extends HotkeyService {
  int retries = 0;

  @override
  void build() {}

  @override
  void retryDoubleTapFallback() => retries++;
}

/// The Input Monitoring grant as the test sets it; [requestAccess] grants
/// when [grantOnRequest] is set, like a user answering the system prompt.
class _FakeListenMonitor extends ModifierKeyMonitor {
  _FakeListenMonitor({this.access, this.grantOnRequest = false})
    : super(isMacOS: false);

  bool? access;
  bool grantOnRequest;
  int requests = 0;

  @override
  Future<bool?> listenAccess() async => access;

  @override
  Future<bool> requestAccess() async {
    requests++;
    if (grantOnRequest) access = true;
    return access ?? false;
  }
}

/// Linux-style monitor: experimental native key-up (catchup/09).
class _ExperimentalMonitor extends NoopKeyboardUpMonitor {
  @override
  bool get supportsKeyUp => true;

  @override
  bool get experimental => true;
}

HotkeyService _fakeHotkeyService({
  required bool supportsKeyUp,
  bool experimental = false,
}) {
  final svc = _NoopHotkeyService();
  svc.injectRegistrar(
    _FakeRegistrar(supportsKeyUp: supportsKeyUp && !experimental),
  );
  svc.injectMonitor(
    experimental ? _ExperimentalMonitor() : NoopKeyboardUpMonitor(),
  );
  return svc;
}

class _FallbackActive extends GlobalHotkeyFallbackController {
  @override
  bool build() => true;
}

class _DoubleTapFallbackActive extends DoubleTapFallbackController {
  @override
  bool build() => true;
}

late L10n l10n;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TriggerStep)));

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<WpHeroButton>(find.byType(WpHeroButton)).onPressed != null;

bool _keycapLit(WidgetTester tester) =>
    tester.widgetList<WpKeycap>(find.byType(WpKeycap)).every((k) => k.lit);

Future<_FakeSettingsNotifier> _pumpStep(
  WidgetTester tester, {
  _FakeSettingsNotifier? settings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
  bool supportsKeyUp = true,
  bool experimental = false,
  DesktopShortcutFallback fallback = DesktopShortcutFallback.notNeeded,
  bool gnomeShortcutInstalled = false,
  bool secureInputBlocked = false,
  bool hotkeyFallback = false,
  bool doubleTapFallback = false,
  _FakeListenMonitor? listenMonitor,
  VoidCallback? onNext,
}) async {
  // A tall view, so the inline recorder's Save sits inside the hit-test area.
  const size = Size(1280, 1200);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final s = settings ?? _FakeSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      // A split page: it fills the window rather than scrolling inside one.
      SizedBox.fromSize(
        size: size,
        child: TriggerStep(onNext: onNext),
      ),
      size: size,
      disableAnimations: true,
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => s),
        hotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeHotkeyStatusController(hotkeyStatus),
        ),
        hotkeyServiceProvider.overrideWith(
          () => _fakeHotkeyService(
            supportsKeyUp: supportsKeyUp,
            experimental: experimental,
          ),
        ),
        desktopShortcutFallbackProvider.overrideWith((ref) async => fallback),
        gnomeToggleShortcutInstalledProvider.overrideWith(
          (ref) async => gnomeShortcutInstalled,
        ),
        manualToggleCommandProvider.overrideWithValue(
          "'/usr/bin/whispaste' --toggle",
        ),
        hotkeySecureInputProbeProvider.overrideWithValue(
          () async => secureInputBlocked,
        ),
        if (hotkeyFallback)
          globalHotkeyFallbackActiveProvider.overrideWith(_FallbackActive.new),
        if (doubleTapFallback)
          doubleTapFallbackActiveProvider.overrideWith(
            _DoubleTapFallbackActive.new,
          ),
        inputMonitoringMonitorProvider.overrideWithValue(
          listenMonitor ?? _FakeListenMonitor(access: true),
        ),
        permissionHelperProvider.overrideWithValue(
          PermissionHelperService(isMacOS: false),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('TriggerStep — secure input (macOS, E05-04)', () {
    testWidgets('a press in a secure field says so instead of failing '
        'silently (macOS, E05-04)', (tester) async {
      await _pumpStep(tester, secureInputBlocked: true);
      expect(find.byKey(kTriggerStepSecureInputKey), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TriggerStep)),
      );
      container
          .read(dictationHotkeyActivityProvider.notifier)
          .pressed(keyUpSupported: true);
      await tester.pumpAndSettle();

      expect(find.byKey(kTriggerStepSecureInputKey), findsOneWidget);
    });

    testWidgets('no secure-input notice when the probe says the field is '
        'not secure', (tester) async {
      await _pumpStep(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TriggerStep)),
      );
      container
          .read(dictationHotkeyActivityProvider.notifier)
          .pressed(keyUpSupported: true);
      await tester.pumpAndSettle();

      expect(find.byKey(kTriggerStepSecureInputKey), findsNothing);
    });
  });

  // ── Conflict branch ────────────────────────────────────────────────────

  group('TriggerStep — confirmed conflict', () {
    testWidgets('conflict: warn-box + inline recorder visible; recording a new '
        'combination and saving persists it', (tester) async {
      final settings = await _pumpStep(
        tester,
        hotkeyStatus: HotkeyRegistrationStatus.conflict,
      );

      expect(find.byKey(kTriggerStepConflictWarnBoxKey), findsOneWidget);
      expect(find.byKey(kTriggerStepInlineRecorderKey), findsOneWidget);
      expect(find.byType(WpHotkeyRecorderDialog), findsOneWidget);

      // Record Ctrl+Shift+F5 and save — exercises the inline `onSubmit`
      // wiring straight through to `updateSettings`.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('hotkey-recorder-save'));
      await tester.pumpAndSettle();

      expect(settings.state.value!.hotkeyKey, 'F5');
    });

    testWidgets('unknown/success: no warn-box, no inline recorder', (
      tester,
    ) async {
      await _pumpStep(tester, hotkeyStatus: HotkeyRegistrationStatus.success);

      expect(find.byKey(kTriggerStepConflictWarnBoxKey), findsNothing);
      expect(find.byKey(kTriggerStepInlineRecorderKey), findsNothing);
    });

    testWidgets('transition conflict → success: warn-box disappears', (
      tester,
    ) async {
      await _pumpStep(tester, hotkeyStatus: HotkeyRegistrationStatus.conflict);
      expect(find.byKey(kTriggerStepConflictWarnBoxKey), findsOneWidget);

      final element = tester.element(
        find.byKey(kTriggerStepConflictWarnBoxKey),
      );
      final container = ProviderScope.containerOf(element);
      container
          .read(hotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.success);
      await tester.pumpAndSettle();

      expect(find.byKey(kTriggerStepConflictWarnBoxKey), findsNothing);
      expect(find.byKey(kTriggerStepInlineRecorderKey), findsNothing);
    });
  });

  // XP-6-14 / XP-6-13: without the GlobalShortcuts portal (or with GTK
  // forced onto native Wayland) the hotkey does not work system-wide until
  // the desktop's own shortcut carries it. The page must not promise
  // otherwise, and it offers the same block as the settings.
  group('TriggerStep — desktop shortcut needed (XP-6-14)', () {
    const block = ValueKey('general-desktop-shortcut');

    testWidgets('GNOME without the entry: offers "Add to GNOME", no promise', (
      tester,
    ) async {
      await _pumpStep(tester, fallback: DesktopShortcutFallback.gnome);
      expect(find.byKey(block), findsOneWidget);
    });

    testWidgets('GNOME with the entry set up: no block', (tester) async {
      await _pumpStep(
        tester,
        fallback: DesktopShortcutFallback.gnome,
        gnomeShortcutInstalled: true,
      );
      expect(find.byKey(block), findsNothing);
    });

    testWidgets('with the portal or on X11: no block', (tester) async {
      await _pumpStep(tester);
      expect(find.byKey(block), findsNothing);
    });
  });

  // #227: the probe runs on the global hotkey path. A press lights the key;
  // a press too short to record does not free Next. (A full start and stop
  // freeing Next: onboarding_overlay_test, "Hotkey page — key test".)
  group('TriggerStep — probe (#227)', () {
    testWidgets('a press lights the key; one shorter than the minimum hold '
        'does not free Next', (tester) async {
      await _pumpStep(tester, onNext: () {});
      final activity = _container(
        tester,
      ).read(dictationHotkeyActivityProvider.notifier);

      activity.pressed(keyUpSupported: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_keycapLit(tester), isTrue);
      activity.released();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(_nextEnabled(tester), isFalse);
      expect(find.byKey(const ValueKey('onboarding-hotkey-skip')), findsOne);
    });
  });

  // #227: a taken combination with the safe default standing in is told on
  // this page, in the words of the settings and the start-up toast.
  group('TriggerStep — safe-default fallback (#227)', () {
    testWidgets('fallback active: names the taken and the working hotkey', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        hotkeyStatus: HotkeyRegistrationStatus.conflict,
        hotkeyFallback: true,
      );
      expect(find.byKey(kTriggerStepHotkeyFallbackKey), findsOneWidget);
    });

    testWidgets('no fallback: no fallback line', (tester) async {
      await _pumpStep(tester, hotkeyStatus: HotkeyRegistrationStatus.conflict);
      expect(find.byKey(kTriggerStepHotkeyFallbackKey), findsNothing);
    });
  });

  // #227 guard: the page changes the hotkey with the settings' recorder,
  // never a recorder of its own.
  testWidgets('"Change" opens the same recorder as the settings', (
    tester,
  ) async {
    await _pumpStep(tester);
    await tester.tap(find.byKey(kTriggerStepChangeHotkeyKey));
    await tester.pumpAndSettle();
    expect(find.byType(WpHotkeyRecorderDialog), findsOneWidget);
  });
  // #1199: a single key on macOS needs Input Monitoring. The page explains
  // that first and asks only from its own button; the grant status drives it.
  group('TriggerStep — Input Monitoring step (#1199)', () {
    final singleKey = AppSettings.defaults.copyWithSections(
      hotkey: AppSettings.defaults.hotkey.copyWith(
        hotkeyDoubleTapKey: ModifierHotkey.rightAlt.name,
      ),
    );

    final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

    test('the step shows only on macOS with the grant missing', () {
      for (final platform in TargetPlatform.values) {
        for (final status in PermissionOverviewStatus.values) {
          expect(
            onboardingInputMonitoringStepVisible(
              platform: platform,
              status: status,
            ),
            platform == TargetPlatform.macOS &&
                status == PermissionOverviewStatus.missing,
            reason: '$platform / $status',
          );
        }
      }
    });

    testWidgets('missing grant: explanation and grant button, no practice', (
      tester,
    ) async {
      final monitor = _FakeListenMonitor(access: false);
      await _pumpStep(
        tester,
        settings: _FakeSettingsNotifier(singleKey),
        listenMonitor: monitor,
      );

      expect(find.byKey(kTriggerStepAccessExplainKey), findsOneWidget);
      expect(find.byKey(kTriggerStepAccessGrantKey), findsOneWidget);
      expect(_keycapLit(tester), isFalse);
      // Explaining is no prompt: nothing was requested yet.
      expect(monitor.requests, 0);
    }, variant: macOS);

    testWidgets('missing grant: key caps name the single key, not the '
        'stored combination', (tester) async {
      // Without the grant the single key is not observed, so the app-wide
      // fallback is active; the explain step still talks about that key.
      await _pumpStep(
        tester,
        settings: _FakeSettingsNotifier(singleKey),
        doubleTapFallback: true,
        listenMonitor: _FakeListenMonitor(access: false),
      );

      final caps = tester
          .widgetList<WpKeycap>(find.byType(WpKeycap))
          .map((k) => k.label)
          .toList();
      expect(caps, hasLength(1));
      expect(caps.single, singleKeyCap(l10n, ModifierHotkey.rightAlt.name).cap);
    }, variant: macOS);

    testWidgets('grant already given: no explanation (existing users)', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        settings: _FakeSettingsNotifier(singleKey),
        listenMonitor: _FakeListenMonitor(access: true),
      );

      expect(find.byKey(kTriggerStepAccessExplainKey), findsNothing);
      expect(find.byKey(kTriggerStepAccessGrantKey), findsNothing);
    }, variant: macOS);

    testWidgets('a key combination needs no grant: no explanation', (
      tester,
    ) async {
      await _pumpStep(tester, listenMonitor: _FakeListenMonitor(access: false));

      expect(find.byKey(kTriggerStepAccessExplainKey), findsNothing);
    }, variant: macOS);

    testWidgets('grant button asks the system; the grant arriving lifts the '
        'step without a restart and retries the double tap', (tester) async {
      final monitor = _FakeListenMonitor(access: false, grantOnRequest: true);
      await _pumpStep(
        tester,
        settings: _FakeSettingsNotifier(singleKey),
        listenMonitor: monitor,
      );

      await tester.tap(find.byKey(kTriggerStepAccessGrantKey));
      await tester.pumpAndSettle();

      expect(monitor.requests, 1);
      expect(find.byKey(kTriggerStepAccessExplainKey), findsNothing);
      expect(find.byKey(kTriggerStepAccessGrantedKey), findsOneWidget);
      final service =
          _container(tester).read(hotkeyServiceProvider.notifier)
              as _NoopHotkeyService;
      expect(service.retries, 1);
    }, variant: macOS);

    testWidgets('grant given in System Settings: polling picks it up', (
      tester,
    ) async {
      final monitor = _FakeListenMonitor(access: false);
      await _pumpStep(
        tester,
        settings: _FakeSettingsNotifier(singleKey),
        listenMonitor: monitor,
      );
      expect(find.byKey(kTriggerStepAccessExplainKey), findsOneWidget);

      monitor.access = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byKey(kTriggerStepAccessExplainKey), findsNothing);
      expect(find.byKey(kTriggerStepAccessGrantedKey), findsOneWidget);
    }, variant: macOS);
  });
}
