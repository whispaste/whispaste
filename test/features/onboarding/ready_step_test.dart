/// Widget tests for [ReadyStep] (onboarding step 4).
///
/// Covers:
/// 1. The step-3 wording, which reacts to the user's Auto-Paste decision.
/// 2. The hotkey-registration-status branches (success / conflict / unknown)
///    introduced by issue 08 — including the conflict warn-box, embedded
///    inline recorder, disabled Start CTA, and the conflict → success
///    transition.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/steps/ready_step.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        hotkeyRegistrationStatusProvider;
import 'package:whispaste/widgets/hotkey_recorder.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

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

/// Test-only [HotkeyRegistrationStatusController] that lets a test seed an
/// initial status and flip it later to verify reactive UI transitions.
class _FakeHotkeyStatusController extends HotkeyRegistrationStatusController {
  _FakeHotkeyStatusController(this._initial);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

void _noop() {}

Future<void> _pumpStep(
  WidgetTester tester, {
  required _FakeSettingsNotifier settings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(
        child: ReadyStep(onComplete: _noop, onBack: _noop),
      ),
      size: const Size(1280, 980),
      overrides: [
        settingsProvider.overrideWith(() => settings),
        hotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeHotkeyStatusController(hotkeyStatus),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Wording-hygiene (issue 10) ───────────────────────────────────────────
  //
  // CONTEXT.md §7 forbids "dictation" vocabulary — WhisPaste is explicitly
  // not a dictation tool. The final CTA on ReadyStep must use the neutral
  // "Let's go" wording instead of the legacy "Start Dictating".

  group('ReadyStep — final CTA wording (issue 10)', () {
    testWidgets('Start CTA renders the dictation-free "Let\'s go" label', (
      tester,
    ) async {
      final settings = _FakeSettingsNotifier();
      await _pumpStep(tester, settings: settings);

      expect(
        find.text("Let's go"),
        findsOneWidget,
        reason:
            'Final CTA must use the CONTEXT.md §7-conformant "Let\'s go" '
            'label, not the legacy "Start Dictating".',
      );
      expect(
        find.textContaining('Dictating'),
        findsNothing,
        reason:
            'No dictation vocabulary may appear in the final CTA per '
            'CONTEXT.md §7.',
      );
    });
  });

  group('ReadyStep — step 3 wording reacts to Auto-Paste setting', () {
    testWidgets(
      'Auto-Paste on (afterTranscription == paste) → step 3 shows Auto-Paste wording, '
      'NOT the Copy-Only / ⌘V hint',
      (tester) async {
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
          ),
        );

        await _pumpStep(tester, settings: settings);

        expect(
          find.textContaining('Text flows straight into the active app'),
          findsOneWidget,
          reason:
              'Auto-Paste users must see the active-app wording, not the '
              'clipboard fallback hint.',
        );
        expect(
          find.textContaining('Ctrl+V'),
          findsNothing,
          reason:
              'When Auto-Paste fires automatically, the manual ⌘V / Ctrl+V '
              'hint must not appear.',
        );
      },
    );

    testWidgets(
      'Auto-Paste off (afterTranscription == clipboard) → step 3 shows '
      'Copy-Only wording with the ⌘V / Ctrl+V hint',
      (tester) async {
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'clipboard',
            ),
          ),
        );

        await _pumpStep(tester, settings: settings);

        expect(
          find.textContaining('Text is in your clipboard'),
          findsOneWidget,
          reason:
              'Skip-Auto-Paste users must see the clipboard wording so they '
              'know the transcript is parked there.',
        );
        expect(
          find.textContaining('Ctrl+V'),
          findsOneWidget,
          reason:
              'Copy-Only wording must include the manual paste hint so users '
              'know how to retrieve the transcript.',
        );
        expect(
          find.textContaining('Text flows straight into the active app'),
          findsNothing,
          reason:
              'The Auto-Paste wording must not appear when Auto-Paste is off.',
        );
      },
    );

    testWidgets(
      'Auto-Paste on via clipboard_and_paste → step 3 also shows Auto-Paste wording',
      (tester) async {
        // The `clipboard_and_paste` mode still injects keystrokes, so the
        // step-3 hint must match the `paste` case rather than the Copy-Only
        // fallback.
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'clipboard_and_paste',
            ),
          ),
        );

        await _pumpStep(tester, settings: settings);

        expect(
          find.textContaining('Text flows straight into the active app'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Auto-Paste off via nothing → step 3 shows Copy-Only wording', (
      tester,
    ) async {
      // `nothing` leaves the transcript on the clipboard too (the app
      // never auto-pastes), so Copy-Only wording with the ⌘V hint is the
      // right fallback even though no copy fires automatically — the
      // wording matches the actionable user step.
      final settings = _FakeSettingsNotifier(
        const AppSettings(
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
        ),
      );

      await _pumpStep(tester, settings: settings);

      expect(find.textContaining('Text is in your clipboard'), findsOneWidget);
      expect(find.textContaining('Ctrl+V'), findsOneWidget);
    });
  });

  // ── Hotkey registration status branches (issue 08) ───────────────────────
  //
  // Default hotkey can collide with another app (e.g. Chrome's bookmark bar).
  // ReadyStep must surface that BEFORE the user clicks Start.

  group('ReadyStep — hotkey registration status branches', () {
    testWidgets(
      'success: KeyCaps + change-link visible, Start CTA active, no warn-box',
      (tester) async {
        final settings = _FakeSettingsNotifier();
        await _pumpStep(
          tester,
          settings: settings,
          hotkeyStatus: HotkeyRegistrationStatus.success,
        );

        // Warn-box must NOT be present.
        expect(
          find.byKey(kReadyStepConflictWarnBoxKey),
          findsNothing,
          reason: 'success branch must not show the conflict warn-box',
        );
        // Inline recorder must NOT be present.
        expect(
          find.byKey(kReadyStepInlineRecorderKey),
          findsNothing,
          reason: 'success branch must not embed the inline recorder',
        );
        // Change-link visible (classic success path).
        expect(find.text('Change Hotkey'), findsOneWidget);

        // Start CTA active (onPressed != null).
        final button = tester.widget<WpAccentButton>(
          find.byKey(kReadyStepStartButtonKey),
        );
        expect(
          button.onPressed,
          isNotNull,
          reason: 'success status must keep Start enabled',
        );
      },
    );

    testWidgets(
      'conflict: warn-box + inline recorder visible, Start CTA disabled',
      (tester) async {
        final settings = _FakeSettingsNotifier();
        await _pumpStep(
          tester,
          settings: settings,
          hotkeyStatus: HotkeyRegistrationStatus.conflict,
        );

        // Warn-box visible.
        expect(
          find.byKey(kReadyStepConflictWarnBoxKey),
          findsOneWidget,
          reason: 'conflict must show the red warn-box',
        );
        // Warn-box copy visible (sanity-check the localised strings reach
        // the widget).
        expect(find.text('Hotkey already in use'), findsOneWidget);
        // Inline recorder embedded directly (NOT as a modal dialog).
        expect(
          find.byKey(kReadyStepInlineRecorderKey),
          findsOneWidget,
          reason: 'conflict must embed the inline HotkeyRecorderDialog',
        );
        expect(
          find.byType(HotkeyRecorderDialog),
          findsOneWidget,
          reason: 'the embedded widget is the real HotkeyRecorderDialog',
        );
        // Change-link must be GONE — the recorder is right there.
        expect(
          find.text('Change Hotkey'),
          findsNothing,
          reason:
              'change-link is redundant when the recorder is already on screen',
        );

        // Start CTA disabled (onPressed == null).
        final button = tester.widget<WpAccentButton>(
          find.byKey(kReadyStepStartButtonKey),
        );
        expect(
          button.onPressed,
          isNull,
          reason: 'conflict status must block Start until the user rebinds',
        );
      },
    );

    testWidgets(
      'transition conflict → success: warn-box gone, Start CTA active',
      (tester) async {
        // Seed with conflict, then flip the provider to success — the widget
        // must rebuild and reach the success branch with Start re-enabled.
        final settings = _FakeSettingsNotifier();
        await _pumpStep(
          tester,
          settings: settings,
          hotkeyStatus: HotkeyRegistrationStatus.conflict,
        );

        // Sanity-check the starting state.
        expect(find.byKey(kReadyStepConflictWarnBoxKey), findsOneWidget);
        final disabledButton = tester.widget<WpAccentButton>(
          find.byKey(kReadyStepStartButtonKey),
        );
        expect(disabledButton.onPressed, isNull);

        // Flip the registration status — mirrors what the real service does
        // after a successful re-registration via `updateHotkey`. Read the
        // notifier from the live element tree so we hit the same provider
        // container the widget is watching.
        final element = tester.element(find.byKey(kReadyStepStartButtonKey));
        final container = ProviderScope.containerOf(element);
        container
            .read(hotkeyRegistrationStatusProvider.notifier)
            .set(HotkeyRegistrationStatus.success);
        await tester.pumpAndSettle();

        // Warn-box and inline recorder gone.
        expect(
          find.byKey(kReadyStepConflictWarnBoxKey),
          findsNothing,
          reason: 'warn-box must disappear once registration succeeds',
        );
        expect(
          find.byKey(kReadyStepInlineRecorderKey),
          findsNothing,
          reason: 'inline recorder must unmount on success',
        );
        // Start CTA active again.
        final enabledButton = tester.widget<WpAccentButton>(
          find.byKey(kReadyStepStartButtonKey),
        );
        expect(
          enabledButton.onPressed,
          isNotNull,
          reason: 'Start CTA must re-enable after the conflict clears',
        );
      },
    );

    testWidgets(
      'unknown: neutral state — classic hotkey display, Start CTA active',
      (tester) async {
        // `unknown` is the very-first transitional state before the
        // background registration completes. We don't want to block the
        // user on a transient race, so Start stays enabled.
        final settings = _FakeSettingsNotifier();
        await _pumpStep(
          tester,
          settings: settings,
          hotkeyStatus: HotkeyRegistrationStatus.unknown,
        );

        expect(find.byKey(kReadyStepConflictWarnBoxKey), findsNothing);
        expect(find.byKey(kReadyStepInlineRecorderKey), findsNothing);

        final button = tester.widget<WpAccentButton>(
          find.byKey(kReadyStepStartButtonKey),
        );
        expect(
          button.onPressed,
          isNotNull,
          reason: 'unknown must not block Start (transient first-mount race)',
        );
      },
    );
  });
}
