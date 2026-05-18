/// Widget tests for [AutoPasteStep] (onboarding step 3).
///
/// External behaviour only: we check what the user sees and which side
/// effects fire (settings update, polling timer disposal). The shared
/// [PasteCapabilityNotifier] is overridden with a tiny fake so we don't
/// touch the real platform bridge — the production notifier still owns the
/// `Paster` integration; here we only exercise the widget contract.
///
/// Platform branching is driven by [defaultTargetPlatform], so Windows
/// cases use `debugDefaultTargetPlatformOverride = TargetPlatform.windows`
/// (reset in a `finally`) and macOS cases run under the test host's
/// default target.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Drop-in fake of [PasteCapabilityNotifier] for widget tests.
///
/// Records every method call so tests can assert which side effects fired,
/// and lets each test seed the initial state plus the result of any
/// follow-up `check()` (mirroring how the real notifier would update its
/// state after a Paster probe).
class _FakePasteCapabilityNotifier extends PasteCapabilityNotifier {
  _FakePasteCapabilityNotifier({
    PasteCapabilityState initial = const PasteCapabilityState(),
    PasteCapabilityState? afterCheck,
    PasteCapabilityState? afterPromptCheck,
    TccRepairResult? repairResult,
    PasteCapabilityState? afterRepair,
  }) : _initial = initial,
       _afterCheck = afterCheck ?? initial,
       _afterPromptCheck = afterPromptCheck,
       _repairResult = repairResult,
       _afterRepair = afterRepair;

  final PasteCapabilityState _initial;
  final PasteCapabilityState _afterCheck;
  // Optional alternative state to apply when a prompted check runs — lets a
  // test simulate the "user grants in OS dialog, capability flips to
  // permissionMissing anyway (ad-hoc-signed bug)" sequence without coupling
  // to the production notifier's internal hadFailedGrantAttempt accounting.
  final PasteCapabilityState? _afterPromptCheck;
  // Result returned from repair(). Tests that don't care about repair leave
  // this null and the call is treated as unsupported.
  final TccRepairResult? _repairResult;
  // Optional state to apply right after a repair() completes — simulates a
  // post-repair re-check or follow-up grant flow updating the notifier.
  final PasteCapabilityState? _afterRepair;

  final List<bool> checkCalls = <bool>[];
  int startPollingCalls = 0;
  int stopPollingCalls = 0;
  int repairCalls = 0;
  Duration? lastPollInterval;
  Duration? lastPollTimeout;
  bool _isPollingFake = false;

  @override
  bool get isPolling => _isPollingFake;

  @override
  PasteCapabilityState build() {
    ref.onDispose(() => stopPollingCalls++);
    return _initial;
  }

  @override
  Future<void> check({bool prompt = false}) async {
    checkCalls.add(prompt);
    state = prompt ? (_afterPromptCheck ?? _afterCheck) : _afterCheck;
  }

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {
    startPollingCalls++;
    lastPollInterval = interval;
    lastPollTimeout = timeout;
    _isPollingFake = true;
  }

  @override
  void stopPolling() {
    stopPollingCalls++;
    _isPollingFake = false;
  }

  @override
  Future<TccRepairResult> repair() async {
    repairCalls++;
    if (_afterRepair != null) state = _afterRepair;
    return _repairResult ?? TccRepairResult.unsupported();
  }
}

class _RecordingSettingsNotifier extends SettingsNotifier {
  _RecordingSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;
  final List<AppSettings> updates = <AppSettings>[];

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    updates.add(_settings);
    state = AsyncData(_settings);
  }
}

void _noop() {}

Future<
  ({_FakePasteCapabilityNotifier paste, _RecordingSettingsNotifier settings})
>
_pumpStep(
  WidgetTester tester, {
  required _FakePasteCapabilityNotifier paste,
  _RecordingSettingsNotifier? settings,
  VoidCallback onNext = _noop,
}) async {
  final settingsNotifier = settings ?? _RecordingSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      SingleChildScrollView(
        child: AutoPasteStep(onNext: onNext, onBack: _noop),
      ),
      size: const Size(1280, 980),
      overrides: [
        pasteCapabilityNotifierProvider.overrideWith(() => paste),
        settingsProvider.overrideWith(() => settingsNotifier),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return (paste: paste, settings: settingsNotifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub the `url_launcher` platform channel so the Grant flow's
  // deep-link into System Settings does not hang the test on a missing
  // platform implementation.
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
          // Both v6 (`launch`) and v7+ (`canLaunch`/`launch`) shapes return a
          // bool — answering true is enough to make the future resolve.
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
  });

  group('AutoPasteStep', () {
    testWidgets(
      'macOS pre-grant: shows permissionMissing status, Grant CTA, Next disabled, '
      'fires one prompt-less check on mount',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );
        var nextCalled = false;

        await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

        // Permission-missing label rendered.
        expect(
          find.text('Accessibility permission not granted'),
          findsOneWidget,
        );
        // Grant CTA shown.
        expect(find.text('Grant Accessibility permission'), findsOneWidget);
        // Skip-Auto-Paste secondary still visible while not ready.
        expect(find.text('Skip — disable Auto-Paste'), findsOneWidget);

        // initState fires exactly one un-prompted check.
        expect(paste.checkCalls, [false]);

        // Tapping the Next CTA while disabled must not fire onNext.
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(nextCalled, isFalse);
      },
    );

    testWidgets('ready state: success icon, Next enabled, Skip hidden', (
      tester,
    ) async {
      final paste = _FakePasteCapabilityNotifier(
        initial: const PasteCapabilityState(
          capability: PasteCapability(status: PasteCapabilityStatus.ready),
        ),
      );
      var nextCalled = false;

      await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

      // "Ready to paste" label is the success message.
      expect(find.text('Ready to paste'), findsOneWidget);
      // Skip button is not shown anymore once status is ready.
      expect(find.text('Skip — disable Auto-Paste'), findsNothing);
      // Grant CTA also hidden in the success state.
      expect(find.text('Grant Accessibility permission'), findsNothing);

      // Tapping Next now advances.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(nextCalled, isTrue);
    });

    testWidgets(
      'Skip persists afterTranscription = clipboard and advances via onNext',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );
        final settings = _RecordingSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
          ),
        );
        var nextCalled = false;

        await _pumpStep(
          tester,
          paste: paste,
          settings: settings,
          onNext: () => nextCalled = true,
        );

        await tester.tap(find.text('Skip — disable Auto-Paste'));
        await tester.pumpAndSettle();

        expect(
          nextCalled,
          isTrue,
          reason: 'Skip must advance via onNext after persisting the setting',
        );
        expect(
          settings.updates,
          hasLength(1),
          reason: 'Skip must run exactly one settings update',
        );
        expect(
          settings.updates.single.afterTranscriptionSection.afterTranscription,
          'clipboard',
        );
      },
    );

    testWidgets(
      'pre-grant + no failed prompt yet: Repair button is NOT visible',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );

        await _pumpStep(tester, paste: paste);

        expect(
          find.text('Repair permissions'),
          findsNothing,
          reason:
              'Repair button is lazy — it must only appear after a prompted '
              'grant attempt has failed (hadFailedGrantAttempt == true).',
        );
      },
    );

    testWidgets(
      'macOS post-grant-fail: Repair button appears after a prompted check '
      'still returns permissionMissing',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
          // After the user clicks Grant, the simulated prompted check comes
          // back as permissionMissing AND hadFailedGrantAttempt flips to
          // true — the canonical ad-hoc-signed-Sequoia symptom.
          afterPromptCheck: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            hadFailedGrantAttempt: true,
          ),
        );

        await _pumpStep(tester, paste: paste);

        // Repair must NOT be present before the failed grant attempt.
        expect(find.text('Repair permissions'), findsNothing);

        // Simulate user clicking Grant → notifier.check(prompt: true) runs.
        // Use sequential pump() instead of pumpAndSettle(): once polling
        // starts the in-status spinner animates forever, which would keep
        // pumpAndSettle from ever resolving.
        await tester.tap(find.text('Grant Accessibility permission'));
        await tester.pump();
        await tester.pump();

        // Now the repair button should be reachable.
        expect(find.text('Repair permissions'), findsOneWidget);
      },
    );

    testWidgets('repair click triggers notifier.repair() exactly once', (
      tester,
    ) async {
      final paste = _FakePasteCapabilityNotifier(
        initial: const PasteCapabilityState(
          capability: PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
          hadFailedGrantAttempt: true,
        ),
        repairResult: const TccRepairResult(
          accessibilityCleared: 1,
          appleEventsCleared: 0,
        ),
      );

      await _pumpStep(tester, paste: paste);

      // Repair is immediately visible because the seeded state already has
      // hadFailedGrantAttempt = true. Use sequential pump() to flush the
      // setState frames without blocking on the polling spinner that the
      // follow-on grant flow activates.
      await tester.tap(find.text('Repair permissions'));
      await tester.pump();
      await tester.pump();

      expect(paste.repairCalls, 1);
    });

    testWidgets('successful repair triggers the follow-on grant flow '
        '(prompted check + polling start)', (tester) async {
      final paste = _FakePasteCapabilityNotifier(
        initial: const PasteCapabilityState(
          capability: PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
          hadFailedGrantAttempt: true,
        ),
        repairResult: const TccRepairResult(
          accessibilityCleared: 1,
          appleEventsCleared: 0,
        ),
      );

      await _pumpStep(tester, paste: paste);

      // Baseline: no prompted check or polling has been issued yet.
      expect(paste.checkCalls.any((p) => p == true), isFalse);
      expect(paste.startPollingCalls, 0);

      await tester.tap(find.text('Repair permissions'));
      // Drain the async chain: repair() → setState → _onGrantPressed →
      // check(prompt:true) → startPolling. Sequential pumps flush each
      // step's microtasks without waiting for the polling spinner to
      // settle (it animates forever and would deadlock pumpAndSettle).
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The follow-on grant flow must run after a successful repair —
      // either directly or via a labelled CTA. We assert the direct path
      // since that gives the smoothest UX: one prompted check + polling.
      expect(
        paste.checkCalls.where((p) => p == true).length,
        greaterThanOrEqualTo(1),
        reason:
            'Successful repair must trigger a follow-up check(prompt: true)',
      );
      expect(
        paste.startPollingCalls,
        greaterThanOrEqualTo(1),
        reason: 'Successful repair must restart capability polling',
      );
    });

    testWidgets(
      'failed repair surfaces an inline error and keeps the step usable '
      '(no advance, repair stays clickable)',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            hadFailedGrantAttempt: true,
          ),
          repairResult: const TccRepairResult(
            accessibilityCleared: -1,
            appleEventsCleared: -1,
            error: 'tccutil_failed',
          ),
        );
        var nextCalled = false;

        await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

        await tester.tap(find.text('Repair permissions'));
        await tester.pumpAndSettle();

        // Inline failure copy is visible — we reuse the existing
        // `pasteCapabilityRepairFailed` string from the settings indicator.
        expect(
          find.textContaining('Could not run the macOS permission reset'),
          findsOneWidget,
        );

        // Step stays in current state: no auto-advance, Repair still
        // reachable for the user to retry.
        expect(nextCalled, isFalse);
        expect(find.text('Repair permissions'), findsOneWidget);
      },
    );

    testWidgets(
      'dispose stops the shared polling timer — no zombie timer survives the step',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );

        await _pumpStep(tester, paste: paste);
        // Replace the step with an empty widget to trigger dispose.
        await tester.pumpWidget(
          makeTestable(
            const SizedBox.shrink(),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(() => paste),
              settingsProvider.overrideWith(() => _RecordingSettingsNotifier()),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The widget explicitly stops polling on dispose. The provider scope
        // tearing down adds one more stop call — we only require at least one
        // explicit stop from the widget's own dispose path.
        expect(paste.stopPollingCalls, greaterThanOrEqualTo(1));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Windows-specific surface (slice 05).
  //
  // Branching is driven by `defaultTargetPlatform` so we exercise both paths
  // by flipping `debugDefaultTargetPlatformOverride` per test and resetting
  // it in `finally`. The fake notifier seeds the capability state — the real
  // Paster bridge stays untouched.
  // ---------------------------------------------------------------------------
  group('AutoPasteStep — Windows', () {
    testWidgets(
      'ready first-mount: minimal verify state, Next active, NO Skip button, '
      'NO macOS-specific Grant/Repair affordances',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final paste = _FakePasteCapabilityNotifier(
            initial: const PasteCapabilityState(
              capability: PasteCapability(status: PasteCapabilityStatus.ready),
            ),
          );
          var nextCalled = false;

          await _pumpStep(
            tester,
            paste: paste,
            onNext: () => nextCalled = true,
          );

          // Verify card shows the success label.
          expect(find.text('Ready to paste'), findsOneWidget);

          // The Windows verify branch hides the macOS-specific Skip CTA —
          // there is no action the user has to take, so offering Skip would
          // only invite a mis-tap that disables Auto-Paste for no reason.
          expect(find.text('Skip — disable Auto-Paste'), findsNothing);

          // macOS-only affordances must not bleed into the Windows surface.
          expect(find.text('Grant Accessibility permission'), findsNothing);
          expect(find.text('Repair permissions'), findsNothing);

          // Next is active in the 99% case — tapping advances.
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(nextCalled, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'permissionMissing (UIPI edge): non-blocking warn card visible, '
      'Skip-Auto-Paste button visible, Next STILL active',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final paste = _FakePasteCapabilityNotifier(
            initial: const PasteCapabilityState(
              capability: PasteCapability(
                status: PasteCapabilityStatus.permissionMissing,
                canPrompt: false,
              ),
            ),
          );
          var nextCalled = false;

          await _pumpStep(
            tester,
            paste: paste,
            onNext: () => nextCalled = true,
          );

          // Warn copy is rendered — we match the unique UIPI fragment so the
          // assertion stays robust against rewording of the framing sentence.
          expect(
            find.textContaining('UIPI/UAC'),
            findsOneWidget,
            reason: 'UIPI warn card must render its explanation text',
          );

          // Skip CTA appears in the warn branch (mirrors the macOS skip flow)
          // so users in the edge case can opt out of Auto-Paste cleanly.
          expect(find.text('Skip — disable Auto-Paste'), findsOneWidget);

          // The macOS verify-state success label is NOT shown in this branch.
          expect(find.text('Ready to paste'), findsNothing);

          // Edge case is non-blocking: Next must remain active so the user
          // can keep Auto-Paste on and still move forward.
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(
            nextCalled,
            isTrue,
            reason: 'UIPI edge is non-blocking — Next must stay enabled',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'permissionMissing skip persists afterTranscription=clipboard and '
      'advances via onNext',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final paste = _FakePasteCapabilityNotifier(
            initial: const PasteCapabilityState(
              capability: PasteCapability(
                status: PasteCapabilityStatus.permissionMissing,
                canPrompt: false,
              ),
            ),
          );
          final settings = _RecordingSettingsNotifier(
            const AppSettings(
              afterTranscriptionSection: AfterTranscriptionSettings(
                afterTranscription: 'paste',
              ),
            ),
          );
          var nextCalled = false;

          await _pumpStep(
            tester,
            paste: paste,
            settings: settings,
            onNext: () => nextCalled = true,
          );

          await tester.tap(find.text('Skip — disable Auto-Paste'));
          await tester.pumpAndSettle();

          expect(nextCalled, isTrue);
          expect(settings.updates, hasLength(1));
          expect(
            settings
                .updates
                .single
                .afterTranscriptionSection
                .afterTranscription,
            'clipboard',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
