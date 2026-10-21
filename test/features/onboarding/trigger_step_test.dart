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

import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        HotKeyRegistrar,
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        HotkeyService,
        hotkeyRegistrationStatusProvider,
        hotkeyServiceProvider;
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

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
  @override
  void build() {}
}

/// Linux-style monitor: experimental native key-up (handy-catchup/09).
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

late L10n l10n;

Future<_FakeSettingsNotifier> _pumpStep(
  WidgetTester tester, {
  _FakeSettingsNotifier? settings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
  bool supportsKeyUp = true,
  bool experimental = false,
  DesktopShortcutFallback fallback = DesktopShortcutFallback.notNeeded,
  bool gnomeShortcutInstalled = false,
}) async {
  final s = settings ?? _FakeSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: TriggerStep()),
      size: const Size(1280, 1200),
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

  // ── Push-to-Talk toggle ────────────────────────────────────────────────

  group('TriggerStep — Push-to-Talk toggle', () {
    testWidgets(
      'supportsKeyUp=true: enabled, tapping persists pushToTalk=true',
      (tester) async {
        final settings = await _pumpStep(tester, supportsKeyUp: true);

        expect(settings.state.value!.pushToTalk, isFalse);

        final toggle = tester.widget<Switch>(
          find.byKey(kTriggerStepPttToggleKey),
        );
        expect(toggle.onChanged, isNotNull);

        await tester.tap(find.byKey(kTriggerStepPttToggleKey));
        await tester.pumpAndSettle();

        expect(settings.state.value!.pushToTalk, isTrue);
      },
    );

    testWidgets(
      'supportsKeyUp=false: disabled (onChanged null) + reason visible '
      '(UIA-ONB-06)',
      (tester) async {
        await _pumpStep(tester, supportsKeyUp: false);

        final toggle = tester.widget<Switch>(
          find.byKey(kTriggerStepPttToggleKey),
        );
        expect(
          toggle.onChanged,
          isNull,
          reason: 'toggle must be disabled when the platform has no key-up',
        );

        // On screen, not only in a hover tooltip: keyboard and screen-reader
        // users never see a tooltip. Host-specific copy (Linux gets its own
        // hint), same as the app shows.
        expect(
          find.textContaining(pushToTalkUnavailableMessage(l10n)),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip && w.message == pushToTalkUnavailableMessage(l10n),
          ),
          findsNothing,
        );
      },
    );
  });

  group('TriggerStep — experimental Linux key-up (handy-catchup/09)', () {
    testWidgets('experimental key-up: badge next to the enabled toggle', (
      tester,
    ) async {
      await _pumpStep(tester, experimental: true);

      expect(find.byKey(kTriggerStepPttExperimentalBadgeKey), findsOneWidget);
      expect(
        tester.widget<Switch>(find.byKey(kTriggerStepPttToggleKey)).onChanged,
        isNotNull,
      );
    });

    testWidgets('native key-up: no badge', (tester) async {
      await _pumpStep(tester);

      expect(find.byKey(kTriggerStepPttExperimentalBadgeKey), findsNothing);
    });
  });

  // ── Hotkey rebind (modal path) ────────────────────────────────────────

  group('TriggerStep — hotkey rebind', () {
    testWidgets(
      'success: Change button opens the modal WpHotkeyRecorderDialog',
      (tester) async {
        await _pumpStep(tester);

        expect(find.byKey(kTriggerStepChangeHotkeyKey), findsOneWidget);
        await tester.tap(find.byKey(kTriggerStepChangeHotkeyKey));
        await tester.pumpAndSettle();

        expect(find.byType(WpHotkeyRecorderDialog), findsOneWidget);
      },
    );
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
      expect(
        find.text(l10n.onboardingTriggerHotkeyConflictTitle),
        findsOneWidget,
      );
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

      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
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

      final element = tester.element(find.byKey(kTriggerStepPttToggleKey));
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
      expect(find.text(l10n.onboardingTriggerSystemWideHint), findsNothing);
      expect(find.byKey(block), findsOneWidget);
      expect(find.text(l10n.settingsDesktopShortcutAdd), findsOneWidget);
    });

    testWidgets('GNOME with the entry set up: works system-wide again', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        fallback: DesktopShortcutFallback.gnome,
        gnomeShortcutInstalled: true,
      );
      expect(find.text(l10n.onboardingTriggerSystemWideHint), findsOneWidget);
    });

    testWidgets('other desktops: shows the command to bind, no promise', (
      tester,
    ) async {
      await _pumpStep(tester, fallback: DesktopShortcutFallback.manual);
      expect(find.text(l10n.onboardingTriggerSystemWideHint), findsNothing);
      expect(find.text("'/usr/bin/whispaste' --toggle"), findsOneWidget);
    });

    testWidgets('with the portal or on X11: the promise stays, no block', (
      tester,
    ) async {
      await _pumpStep(tester);
      expect(find.text(l10n.onboardingTriggerSystemWideHint), findsOneWidget);
      expect(find.byKey(block), findsNothing);
    });
  });
}
