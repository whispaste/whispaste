/// Widget tests for [ReadyStep] — the closing content of the final
/// onboarding page.
///
/// Covers:
/// 1. The step-3 wording, which reacts to the user's Auto-Paste decision.
/// 2. The residual hotkey-conflict notice: the completion CTA itself (and
///    its disabled state) is owned by the onboarding shell and covered in
///    `onboarding_flow_test.dart`; this widget must render the matching
///    heads-up text exactly when a conflict is confirmed.
///
/// The autostart toggle moved to the Autostart & Auto-Paste page — see
/// `autostart_toggle_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/ready_step.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        hotkeyRegistrationStatusProvider;

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
/// initial status.
class _FakeHotkeyStatusController extends HotkeyRegistrationStatusController {
  _FakeHotkeyStatusController(this._initial);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

late L10n l10n;

Future<void> _pumpStep(
  WidgetTester tester, {
  required _FakeSettingsNotifier settings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: ReadyStep()),
      size: const Size(1280, 980),
      locale: const Locale('en'),
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

  // Resolve English copy once so labels are looked up via the ARB key.
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  // ── Wording-hygiene (issue 10) ───────────────────────────────────────────
  //
  // CONTEXT.md §7 forbids "dictation" vocabulary — WhisPaste is explicitly
  // not a dictation tool. No dictation vocabulary may appear anywhere on the
  // closing content.

  group('ReadyStep — wording hygiene (issue 10)', () {
    testWidgets('no dictation vocabulary appears in the closing content', (
      tester,
    ) async {
      final settings = _FakeSettingsNotifier();
      await _pumpStep(tester, settings: settings);

      expect(find.text(l10n.onboardingReadyTitle), findsOneWidget);
      // Anti-vocabulary check stays on a literal substring on purpose — we
      // are asserting "the word 'Dictating' MUST NOT appear", regardless of
      // which ARB key it would have come from.
      expect(
        find.textContaining('Dictating'),
        findsNothing,
        reason:
            'No dictation vocabulary may appear on the closing page per '
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
          find.textContaining(l10n.onboardingReadyStep3AutoPaste),
          findsOneWidget,
          reason:
              'Auto-Paste users must see the active-app wording, not the '
              'clipboard fallback hint.',
        );
        expect(
          find.textContaining(l10n.onboardingReadyStep3CopyOnly),
          findsNothing,
          reason:
              'When Auto-Paste fires automatically, the manual ⌘V / Ctrl+V '
              'hint (part of the copy-only step) must not appear.',
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

        // The copy-only ARB string ("Text is in your clipboard — press ⌘V /
        // Ctrl+V to paste") already bundles the manual paste hint, so a
        // single positive assertion covers both the wording and the hint.
        expect(
          find.textContaining(l10n.onboardingReadyStep3CopyOnly),
          findsOneWidget,
          reason:
              'Skip-Auto-Paste users must see the clipboard wording so they '
              'know the transcript is parked there and how to retrieve it.',
        );
        expect(
          find.textContaining(l10n.onboardingReadyStep3AutoPaste),
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
          find.textContaining(l10n.onboardingReadyStep3AutoPaste),
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

      expect(
        find.textContaining(l10n.onboardingReadyStep3CopyOnly),
        findsOneWidget,
      );
    });
  });

  // ── Residual hotkey-conflict notice ──────────────────────────────────────
  //
  // The shell disables the completion CTA on a confirmed conflict (covered
  // in onboarding_flow_test.dart); this content must render the matching
  // heads-up so the disabled CTA never appears unexplained.

  group('ReadyStep — residual hotkey-conflict notice', () {
    testWidgets('success: no conflict notice', (tester) async {
      final settings = _FakeSettingsNotifier();
      await _pumpStep(
        tester,
        settings: settings,
        hotkeyStatus: HotkeyRegistrationStatus.success,
      );

      expect(
        find.text(l10n.onboardingTriggerHotkeyConflictTitle),
        findsNothing,
        reason: 'success branch must not show the residual conflict notice',
      );
    });

    testWidgets('conflict: conflict notice visible', (tester) async {
      final settings = _FakeSettingsNotifier();
      await _pumpStep(
        tester,
        settings: settings,
        hotkeyStatus: HotkeyRegistrationStatus.conflict,
      );

      expect(
        find.text(l10n.onboardingTriggerHotkeyConflictTitle),
        findsOneWidget,
        reason: 'conflict must surface a short heads-up next to the CTA',
      );
    });

    testWidgets('unknown: neutral state — no conflict notice', (tester) async {
      // `unknown` is the very-first transitional state before the
      // background registration completes — it must not scare the user.
      final settings = _FakeSettingsNotifier();
      await _pumpStep(
        tester,
        settings: settings,
        hotkeyStatus: HotkeyRegistrationStatus.unknown,
      );

      expect(
        find.text(l10n.onboardingTriggerHotkeyConflictTitle),
        findsNothing,
      );
    });
  });
}
