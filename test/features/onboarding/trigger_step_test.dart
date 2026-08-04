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

HotkeyService _fakeHotkeyService({required bool supportsKeyUp}) {
  final svc = _NoopHotkeyService();
  svc.injectRegistrar(_FakeRegistrar(supportsKeyUp: supportsKeyUp));
  svc.injectMonitor(NoopKeyboardUpMonitor());
  return svc;
}

late L10n l10n;

Future<_FakeSettingsNotifier> _pumpStep(
  WidgetTester tester, {
  _FakeSettingsNotifier? settings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
  bool supportsKeyUp = true,
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
          () => _fakeHotkeyService(supportsKeyUp: supportsKeyUp),
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
      'supportsKeyUp=false: disabled (onChanged null) + tooltip shown',
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

        final tooltips = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .where((t) => t.message == l10n.pushToTalkUnavailableTooltip)
            .toList();
        expect(tooltips, isNotEmpty);
      },
    );
  });

  // ── Hotkey rebind (modal path) ────────────────────────────────────────

  group('TriggerStep — hotkey rebind', () {
    testWidgets('success: Change button opens the modal HotkeyRecorderDialog', (
      tester,
    ) async {
      await _pumpStep(tester);

      expect(find.byKey(kTriggerStepChangeHotkeyKey), findsOneWidget);
      await tester.tap(find.byKey(kTriggerStepChangeHotkeyKey));
      await tester.pumpAndSettle();

      expect(find.byType(HotkeyRecorderDialog), findsOneWidget);
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
      expect(
        find.text(l10n.onboardingTriggerHotkeyConflictTitle),
        findsOneWidget,
      );
      expect(find.byKey(kTriggerStepInlineRecorderKey), findsOneWidget);
      expect(find.byType(HotkeyRecorderDialog), findsOneWidget);

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
}
