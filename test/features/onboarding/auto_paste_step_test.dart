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

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

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
    this._afterPromptCheck,
    this._repairResult,
  }) : _afterRepair = null,
       _initial = initial,
       _afterCheck = afterCheck ?? initial;

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

  /// When non-null, [check] returns this Completer's future instead of an
  /// immediately-resolving one. Tests use it to observe the widget's
  /// in-flight UI state by stalling the async chain at the first await.
  Completer<void>? promptedCheckGate;

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
    // Stall on the prompted-check path when a gate is installed so the
    // widget's async chain stays suspended at the first await. The
    // un-prompted initState probe is never gated.
    if (prompt && promptedCheckGate != null) {
      await promptedCheckGate!.future;
    }
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
      // Pin the locale to `en` so labels are deterministic regardless of
      // the host's system language — CI runners ship with varying default
      // locales and `null` would otherwise fall back to whatever the
      // platform reports.
      locale: const Locale('en'),
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

  // Single resolved English copy used for every label lookup below. Using
  // `l10n.<key>` instead of hardcoded strings keeps the suite stable across
  // wording changes in the ARB and surfaces *missing keys* as compile-time
  // errors. The only way to silently break this test is to actually remove
  // the affordance from the widget — which is precisely what the assertion
  // is supposed to catch.
  late final L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

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
    testWidgets('macOS intro phase: Grant CTA + Skip visible, Next disabled, '
        'fires one prompt-less check on mount', (tester) async {
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

      // Grant CTA shown.
      expect(find.text(l10n.onboardingPasteGrantCta), findsOneWidget);
      // Skip secondary visible while not ready.
      expect(find.text(l10n.onboardingPasteSkip), findsOneWidget);
      // In the intro phase the permission status card is intentionally not
      // rendered — the Grant CTA + why-mac caption are the only signal.
      expect(find.text(l10n.pasteCapabilityReady), findsNothing);

      // initState fires exactly one un-prompted check.
      expect(paste.checkCalls, [false]);

      // Tapping the Next CTA while disabled must not fire onNext.
      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(nextCalled, isFalse);
    });

    testWidgets('granted phase: success card visible, Grant + Skip hidden, '
        'Next is enabled and advances onNext', (tester) async {
      final paste = _FakePasteCapabilityNotifier(
        initial: const PasteCapabilityState(
          capability: PasteCapability(status: PasteCapabilityStatus.ready),
        ),
      );
      var nextCalled = false;

      await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

      // Success label is the only card in the granted phase.
      expect(find.text(l10n.pasteCapabilityReady), findsOneWidget);
      // Skip and Grant disappear once the capability is ready — Next is the
      // single primary CTA.
      expect(find.text(l10n.onboardingPasteSkip), findsNothing);
      expect(find.text(l10n.onboardingPasteGrantCta), findsNothing);

      // Next is enabled in the granted phase and advances directly.
      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(
        nextCalled,
        isTrue,
        reason: 'Next must be enabled and advance once the phase is granted',
      );
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

        await tester.tap(find.text(l10n.onboardingPasteSkip));
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
          find.text(l10n.pasteCapabilityRepairButton),
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
          // After the user clicks Grant, the simulated prompted check ends in
          // the full TCC-mismatch state: permissionMissing + failed-grant
          // latch + a timed-out polling loop. That conjunction is what flips
          // the macOS body into the troubleshoot phase where Reset entry is
          // rendered. In production the timedOut value is set by the polling
          // timer; here we seed it directly so the widget contract assertion
          // ("Reset entry appears once troubleshoot conditions hold") can be
          // observed without waiting on a real timer.
          afterPromptCheck: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            hadFailedGrantAttempt: true,
            pollingPhase: PollingPhase.timedOut,
          ),
        );

        await _pumpStep(tester, paste: paste);

        // Repair must NOT be present before the failed grant attempt — the
        // intro phase only shows Grant + Skip.
        expect(find.text(l10n.pasteCapabilityRepairButton), findsNothing);

        // Simulate user clicking Grant → notifier.check(prompt: true) runs
        // and seeds the troubleshoot conditions via _afterPromptCheck.
        await tester.tap(find.text(l10n.onboardingPasteGrantCta));
        await tester.pump();
        await tester.pump();

        // Now the troubleshoot phase is active and Reset entry is visible.
        expect(find.text(l10n.pasteCapabilityRepairButton), findsOneWidget);
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
          // All three TCC-mismatch conditions seeded so the macOS body lands
          // in the troubleshoot phase where Reset entry is rendered.
          hadFailedGrantAttempt: true,
          pollingPhase: PollingPhase.timedOut,
        ),
        repairResult: const TccRepairResult(
          accessibilityCleared: 1,
          appleEventsCleared: 0,
        ),
      );

      await _pumpStep(tester, paste: paste);

      // Reset entry is immediately visible because the seeded state satisfies
      // suspectedTccMismatch. Use sequential pump() to flush the setState
      // frames without blocking on the polling spinner that the follow-on
      // grant flow activates.
      await tester.tap(find.text(l10n.pasteCapabilityRepairButton));
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
          // Troubleshoot-phase seed so the Reset entry button is reachable
          // from the first frame.
          hadFailedGrantAttempt: true,
          pollingPhase: PollingPhase.timedOut,
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

      await tester.tap(find.text(l10n.pasteCapabilityRepairButton));
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
            // Troubleshoot-phase seed so Reset entry is rendered.
            hadFailedGrantAttempt: true,
            pollingPhase: PollingPhase.timedOut,
          ),
          repairResult: const TccRepairResult(
            accessibilityCleared: -1,
            appleEventsCleared: -1,
            error: 'tccutil_failed',
          ),
        );
        var nextCalled = false;

        await _pumpStep(tester, paste: paste, onNext: () => nextCalled = true);

        await tester.tap(find.text(l10n.pasteCapabilityRepairButton));
        await tester.pumpAndSettle();

        // Inline failure copy is visible — we reuse the existing
        // `pasteCapabilityRepairFailed` string from the settings indicator.
        expect(find.text(l10n.pasteCapabilityRepairFailed), findsOneWidget);

        // Step stays in current state: no auto-advance, Repair still
        // reachable for the user to retry.
        expect(nextCalled, isFalse);
        expect(find.text(l10n.pasteCapabilityRepairButton), findsOneWidget);
      },
    );

    testWidgets(
      'Grant button busy-state: onPressed is null while _onGrantPressed is '
      'in-flight, re-enabled once the chain completes',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );
        // Gate the prompted check so the widget stays suspended at the
        // first await inside _onGrantPressed — that's the window where the
        // busy state is observable from outside.
        final gate = Completer<void>();
        paste.promptedCheckGate = gate;

        await _pumpStep(tester, paste: paste);

        // Locate the Grant CTA's underlying WpAccentButton — there are two
        // accent buttons on screen (Grant + Next); we pick the one wrapping
        // the localized Grant label.
        Finder grantButtonFinder() => find.ancestor(
          of: find.text(l10n.onboardingPasteGrantCta),
          matching: find.byType(WpAccentButton),
        );

        // Baseline: button is interactive before any tap.
        expect(
          tester.widget<WpAccentButton>(grantButtonFinder()).onPressed,
          isNotNull,
        );

        // Tap and flush the setState(grantInFlight=true) frame. The
        // gated check() leaves the rest of the chain suspended, so we can
        // observe the disabled state.
        await tester.tap(find.text(l10n.onboardingPasteGrantCta));
        await tester.pump();

        expect(
          tester.widget<WpAccentButton>(grantButtonFinder()).onPressed,
          isNull,
          reason:
              'While _onGrantPressed is in-flight the Grant WpAccentButton '
              'must be disabled (onPressed == null).',
        );

        // Release the gate so the awaited chain resolves and the finally
        // block runs setState(grantInFlight=false). Sequential pumps flush
        // the resulting microtasks without deadlocking on the polling
        // spinner (which animates forever).
        gate.complete();
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(
          tester.widget<WpAccentButton>(grantButtonFinder()).onPressed,
          isNotNull,
          reason:
              'After _onGrantPressed completes the button must be re-enabled '
              'so the user can retry without re-mounting the step.',
        );
      },
    );

    testWidgets(
      'Grant button busy-state: a second tap while in-flight does NOT trigger '
      'a second _onGrantPressed call',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );
        // Gate the prompted check so we can attempt the second tap while
        // the first call is provably still in-flight.
        final gate = Completer<void>();
        paste.promptedCheckGate = gate;

        await _pumpStep(tester, paste: paste);

        // First tap arms the busy state and suspends inside check().
        await tester.tap(find.text(l10n.onboardingPasteGrantCta));
        await tester.pump();

        // Second tap while in-flight must be ignored. tester.tap fails on a
        // disabled InkWell hit-test (the WpAccentButton wraps onPressed=null
        // around the InkWell), so we use warnIfMissed:false to make the
        // attempt observable rather than a test failure — the assertion
        // below is what proves the no-op behaviour.
        await tester.tap(
          find.text(l10n.onboardingPasteGrantCta),
          warnIfMissed: false,
        );
        await tester.pump();

        // Release the gate so the original call can complete cleanly.
        gate.complete();
        await tester.pump();
        await tester.pump();

        // Exactly one prompted check fired — proves the second tap was a
        // no-op. (initState fires an un-prompted check, so we filter on
        // prompt: true to isolate the Grant flow's call.)
        expect(
          paste.checkCalls.where((p) => p == true).length,
          1,
          reason:
              'Double-tap during in-flight must not queue a second '
              '_onGrantPressed call.',
        );
        // Same for polling: arm once, not twice.
        expect(paste.startPollingCalls, 1);
      },
    );

    testWidgets(
      '_RepairResultBanner renders pasteCapabilityRepairNothingToClear when '
      'both cleared counters are 0 and error is null',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            // Troubleshoot-phase seed so Reset entry is rendered.
            hadFailedGrantAttempt: true,
            pollingPhase: PollingPhase.timedOut,
          ),
          // Supported result (error == null) but both counters at 0 — the
          // honest "nothing to actually fix" path the new copy targets.
          repairResult: const TccRepairResult(
            accessibilityCleared: 0,
            appleEventsCleared: 0,
          ),
        );

        await _pumpStep(tester, paste: paste);

        await tester.tap(find.text(l10n.pasteCapabilityRepairButton));
        // Sequential pump() because the success path chains into the Grant
        // flow which arms polling; pumpAndSettle would deadlock on the
        // polling spinner.
        await tester.pump();
        await tester.pump();
        await tester.pump();

        // The nothing-to-clear copy is rendered with restart guidance.
        expect(
          find.text(l10n.pasteCapabilityRepairNothingToClear),
          findsOneWidget,
          reason:
              'Banner must render pasteCapabilityRepairNothingToClear when '
              'both cleared counters are 0 and error is null.',
        );

        // The generic pluralised pasteCapabilityRepairDone copy must NOT
        // render alongside it — otherwise both messages would clash on
        // screen. We check the =0 plural variant as the canonical "would
        // have rendered" form for this seeded state.
        expect(
          find.text(l10n.pasteCapabilityRepairDone(0)),
          findsNothing,
          reason:
              'Generic pasteCapabilityRepairDone copy must not render when '
              'the nothing-to-clear branch fires.',
        );
      },
    );

    testWidgets(
      'polling hint card is visible while pollingPhase == awaitingGrant',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            pollingPhase: PollingPhase.awaitingGrant,
          ),
        );

        await _pumpStep(tester, paste: paste);

        // Hint title is rendered.
        expect(
          find.text(l10n.onboardingPasteWaitingForGrantTitle),
          findsOneWidget,
        );
        // Hint body is rendered.
        expect(
          find.text(l10n.onboardingPasteWaitingForGrantHint),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'polling hint card is hidden when pollingPhase is idle, succeeded or timedOut',
      (tester) async {
        for (final phase in <PollingPhase>[
          PollingPhase.idle,
          PollingPhase.succeeded,
          PollingPhase.timedOut,
        ]) {
          final paste = _FakePasteCapabilityNotifier(
            initial: PasteCapabilityState(
              capability: const PasteCapability(
                status: PasteCapabilityStatus.permissionMissing,
                canPrompt: true,
              ),
              pollingPhase: phase,
            ),
          );

          await _pumpStep(tester, paste: paste);

          expect(
            find.text(l10n.onboardingPasteWaitingForGrantTitle),
            findsNothing,
            reason:
                'Polling hint must not show outside the awaitingGrant phase '
                '(was: $phase)',
          );

          // Tear down between phase iterations so the next pump starts clean.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    // -- TCC-mismatch banner ------------------------------------------------
    //
    // The banner light-up is gated by `notifier.suspectedTccMismatch`, which
    // is the conjunction of three state fields. The fake notifier inherits
    // that getter (no override), so seeding the three fields on `initial` is
    // enough to drive the banner without re-implementing the conjunction.
    testWidgets(
      'TCC-mismatch banner is visible when suspectedTccMismatch == true '
      '(all three conditions satisfied)',
      (tester) async {
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            hadFailedGrantAttempt: true,
            pollingPhase: PollingPhase.timedOut,
          ),
        );

        await _pumpStep(tester, paste: paste);

        // Title is rendered.
        expect(find.text(l10n.onboardingPasteTccMismatchTitle), findsOneWidget);
      },
    );

    testWidgets('TCC-mismatch banner is hidden for every state where '
        'suspectedTccMismatch is false', (tester) async {
      // Each entry falsifies a different conjunct so the banner must stay
      // hidden. The all-true case is covered by the test above.
      final hiddenCases = <PasteCapabilityState>[
        // Default — nothing set.
        const PasteCapabilityState(),
        // hadFailedGrantAttempt == false (other two true).
        const PasteCapabilityState(
          capability: PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
          pollingPhase: PollingPhase.timedOut,
        ),
        // capability.status != permissionMissing (other two true).
        const PasteCapabilityState(
          capability: PasteCapability(status: PasteCapabilityStatus.ready),
          hadFailedGrantAttempt: true,
          pollingPhase: PollingPhase.timedOut,
        ),
        // pollingPhase != timedOut — try awaitingGrant and idle as the two
        // representative non-terminal/terminal alternatives.
        const PasteCapabilityState(
          capability: PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
          hadFailedGrantAttempt: true,
          pollingPhase: PollingPhase.awaitingGrant,
        ),
        const PasteCapabilityState(
          capability: PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
          hadFailedGrantAttempt: true,
          pollingPhase: PollingPhase.idle,
        ),
      ];

      for (final seed in hiddenCases) {
        final paste = _FakePasteCapabilityNotifier(initial: seed);
        await _pumpStep(tester, paste: paste);

        expect(
          find.text(l10n.onboardingPasteTccMismatchTitle),
          findsNothing,
          reason:
              'TCC-mismatch banner must stay hidden when '
              'suspectedTccMismatch is false (seed: $seed)',
        );

        // Tear down between iterations so the next pump starts clean.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });

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

    testWidgets(
      'after polling has started and the step is disposed, no active polling '
      'remains (defends against zombie timers from Grant → window-close)',
      (tester) async {
        // Start in the pre-grant state so the Grant CTA is reachable.
        final paste = _FakePasteCapabilityNotifier(
          initial: const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );

        await _pumpStep(tester, paste: paste);

        // Kick polling on via the production grant path. Use sequential
        // pump() because pumpAndSettle would deadlock on the in-status
        // spinner that the polling badge keeps animating.
        await tester.tap(find.text(l10n.onboardingPasteGrantCta));
        await tester.pump();
        await tester.pump();
        expect(
          paste.startPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Grant must arm polling so the dispose path has work to do',
        );
        expect(paste.isPolling, isTrue);

        // Now simulate the user leaving the step (Next/Skip/Re-mount) by
        // swapping the widget tree wholesale. The step's dispose must stop
        // polling so the shared notifier doesn't keep a timer alive.
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

        expect(
          paste.stopPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Step dispose must explicitly call stopPolling()',
        );
        expect(
          paste.isPolling,
          isFalse,
          reason: 'After dispose no polling timer must remain active',
        );
      },
    );

    testWidgets(
      're-mounting the step while polling runs stops the previous timer '
      'before the new instance arms its own',
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
        await tester.tap(find.text(l10n.onboardingPasteGrantCta));
        await tester.pump();
        await tester.pump();
        expect(paste.isPolling, isTrue);
        final stopCallsBeforeRemount = paste.stopPollingCalls;

        // Re-mount with a fresh key to force a full dispose/init cycle.
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(
              child: AutoPasteStep(
                key: ValueKey('remounted'),
                onNext: _noop,
                onBack: _noop,
              ),
            ),
            size: const Size(1280, 980),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(() => paste),
              settingsProvider.overrideWith(() => _RecordingSettingsNotifier()),
            ],
          ),
        );
        await tester.pump();

        expect(
          paste.stopPollingCalls,
          greaterThan(stopCallsBeforeRemount),
          reason:
              'Re-mount must run dispose of the previous instance, which '
              'must call stopPolling on the shared notifier',
        );
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
      'ready first-mount: verify card + active Next, NO macOS-specific '
      'Grant/Repair/Skip affordances',
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
          expect(find.text(l10n.pasteCapabilityReady), findsOneWidget);

          // The Windows verify branch hides the macOS-specific Skip CTA —
          // there is no action the user has to take, so offering Skip would
          // only invite a mis-tap that disables Auto-Paste for no reason.
          expect(find.text(l10n.onboardingPasteSkip), findsNothing);

          // macOS-only affordances must not bleed into the Windows surface.
          expect(find.text(l10n.onboardingPasteGrantCta), findsNothing);
          expect(find.text(l10n.pasteCapabilityRepairButton), findsNothing);

          // Next is enabled in the Windows verify branch and advances
          // immediately — there is no test-paste gate on this platform.
          await tester.tap(find.text(l10n.onboardingNext));
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

          // Warn copy is rendered — we assert the full localised string so
          // an ARB rewording is caught loudly but a value tweak does not
          // silently mismatch a substring.
          expect(
            find.text(l10n.onboardingPasteWhyWinUipi),
            findsOneWidget,
            reason: 'UIPI warn card must render its explanation text',
          );

          // Skip CTA appears in the warn branch (mirrors the macOS skip flow)
          // so users in the edge case can opt out of Auto-Paste cleanly.
          expect(find.text(l10n.onboardingPasteSkip), findsOneWidget);

          // The macOS verify-state success label is NOT shown in this branch.
          expect(find.text(l10n.pasteCapabilityReady), findsNothing);

          // Edge case is non-blocking: Next must remain active so the user
          // can keep Auto-Paste on and still move forward.
          await tester.tap(find.text(l10n.onboardingNext));
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

          await tester.tap(find.text(l10n.onboardingPasteSkip));
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
