/// Widget tests for [OnboardingOverlay] step-sequence behaviour.
///
/// Focus is on the platform-dependent flow assembly: only macOS renders
/// five steps (Welcome → Microphone → AutoPaste → Model → Ready); Windows
/// and Linux render four (AutoPasteStep is omitted on both — Windows
/// because no permission is needed in the 99 % case and the diagnostic
/// test-paste step was confusing real users; Linux because the underlying
/// capability is not supported). The stepper dots and "Step X of Y"
/// counter must both reflect the active list length.
///
/// We only assert on the first frame here: the initial step is always
/// [WelcomeStep], so we can verify total counts without driving the user
/// through later steps (which have their own dedicated tests).
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';

import '../../fixtures/test_helpers.dart';

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

/// Minimal recording fake — counts [stopPolling] calls so the overlay
/// disposal test can verify the defensive cleanup fires.
class _RecordingPasteCapabilityNotifier extends PasteCapabilityNotifier {
  int stopPollingCalls = 0;

  @override
  PasteCapabilityState build() => const PasteCapabilityState();

  @override
  void stopPolling() {
    stopPollingCalls++;
  }
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  _RecordingPasteCapabilityNotifier? paste,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const OnboardingOverlay(),
      size: const Size(1280, 980),
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
        if (paste != null)
          pasteCapabilityNotifierProvider.overrideWith(() => paste),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingOverlay step sequence', () {
    testWidgets('on Linux: renders 4-step flow, AutoPasteStep never appears, '
        'counter and dots reflect 4 total', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpOverlay(tester);

        // Counter reflects the Linux 4-step total on the initial Welcome step.
        expect(find.text('Step 1 of 4'), findsOneWidget);
        // AutoPasteStep is never instantiated in the Linux flow.
        expect(find.byType(AutoPasteStep), findsNothing);
      } finally {
        // Reset before the framework's foundation-vars-unset assertion.
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('on macOS: renders 5-step flow with AutoPasteStep included; '
        'counter reflects 5 total', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(tester);

        // Counter reflects the macOS 5-step total on the initial Welcome step.
        expect(find.text('Step 1 of 5'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('on Windows: renders 4-step flow, AutoPasteStep never appears, '
        'counter and dots reflect 4 total', (tester) async {
      // Windows drops AutoPasteStep entirely: no permission is required in
      // the 99 % case and the diagnostic test-paste sub-step was misread as
      // "press a hotkey" during real onboarding sessions, so the flow now
      // matches Linux in shape. The Windows-specific UIPI/UAC edge surfaces
      // through the Settings paste capability indicator instead.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await _pumpOverlay(tester);

        expect(find.text('Step 1 of 4'), findsOneWidget);
        expect(find.byType(AutoPasteStep), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ── Skip-button wording (issue 10) ───────────────────────────────────────
  //
  // The header Skip button used to read just "Skip", which was ambiguous —
  // users could not tell whether it skipped the current step or the whole
  // onboarding. It now reads "Skip this step" to disambiguate.

  group('OnboardingOverlay — header Skip button wording (issue 10)', () {
    testWidgets(
      'header Skip button on a non-final step renders the disambiguated '
      '"Skip this step" label',
      (tester) async {
        // Force macOS so the full 5-step flow is rendered — guarantees the
        // initial Welcome step is not the final step, so the Skip button is
        // visible.
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(tester);

          expect(
            find.text('Skip this step'),
            findsOneWidget,
            reason:
                'Header Skip button must disambiguate that it skips only the '
                'current step, not the whole onboarding.',
          );
          // The bare "Skip" label is the historic, ambiguous form — must be
          // gone now.
          expect(
            find.text('Skip'),
            findsNothing,
            reason: 'Legacy "Skip" label must be replaced by "Skip this step".',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('OnboardingOverlay disposal', () {
    testWidgets(
      'dispose explicitly stops Auto-Paste polling — defends against zombie '
      'timers when the overlay tears down (window close, app quit, re-mount)',
      (tester) async {
        final paste = _RecordingPasteCapabilityNotifier();

        await _pumpOverlay(tester, paste: paste);
        // Replace the overlay with an empty widget to trigger dispose.
        await tester.pumpWidget(
          makeTestable(
            const SizedBox.shrink(),
            size: const Size(1280, 980),
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
              pasteCapabilityNotifierProvider.overrideWith(() => paste),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          paste.stopPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Overlay dispose must explicitly call stopPolling()',
        );
      },
    );
  });
}
