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
import 'package:whispaste/services/linux_desktop_shortcut.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/ready_step.dart';
import 'package:whispaste/features/onboarding/stt_model_readiness.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        hotkeyRegistrationStatusProvider;
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart'
    show PasteCapability, PasteCapabilityStatus;

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

/// Test-only paste capability: seeds the probe result. `null` means "no probe
/// has run yet", which is what the notifier starts with.
class _FakePasteCapabilityNotifier extends PasteCapabilityNotifier {
  _FakePasteCapabilityNotifier(this._capability);

  final PasteCapability? _capability;

  @override
  PasteCapabilityState build() => PasteCapabilityState(capability: _capability);
}

late L10n l10n;

Future<void> _pumpStep(
  WidgetTester tester, {
  required _FakeSettingsNotifier settings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
  DesktopShortcutFallback fallback = DesktopShortcutFallback.notNeeded,
  bool modelInstalled = true,
  VoidCallback? onBackToModel,
  PasteCapability? pasteCapability = const PasteCapability(
    status: PasteCapabilityStatus.ready,
  ),
}) async {
  await tester.pumpWidget(
    makeTestable(
      SingleChildScrollView(child: ReadyStep(onBackToModel: onBackToModel)),
      size: const Size(1280, 980),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => settings),
        hotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeHotkeyStatusController(hotkeyStatus),
        ),
        desktopShortcutFallbackProvider.overrideWith((ref) async => fallback),
        gnomeToggleShortcutInstalledProvider.overrideWith((ref) async => false),
        onboardingSttModelInstalledProvider.overrideWithValue(modelInstalled),
        pasteCapabilityNotifierProvider.overrideWith(
          () => _FakePasteCapabilityNotifier(pasteCapability),
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

  // ── "All set" only with a speech model (UIA-RT-01) ──────────────────────

  group('ReadyStep — speech model (UIA-RT-01)', () {
    testWidgets('without an installed model the page does not say all set, '
        'and offers the way back to the model step', (tester) async {
      var backCalls = 0;
      await _pumpStep(
        tester,
        settings: _FakeSettingsNotifier(),
        modelInstalled: false,
        onBackToModel: () => backCalls++,
      );

      expect(find.text(l10n.onboardingReadyTitle), findsNothing);
      expect(find.text(l10n.onboardingReadyNoModelTitle), findsOneWidget);
      expect(find.text(l10n.onboardingReadyNoModelBody), findsOneWidget);

      await tester.tap(find.byKey(kReadyStepBackToModelKey));
      await tester.pump();
      expect(backCalls, 1);
    });

    testWidgets('with an installed model the page says all set and offers no '
        'way back', (tester) async {
      await _pumpStep(tester, settings: _FakeSettingsNotifier());

      expect(find.text(l10n.onboardingReadyTitle), findsOneWidget);
      expect(find.byKey(kReadyStepBackToModelKey), findsNothing);
    });
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

  // ── Step 3 follows the paste capability (UIA-XP-7-12) ────────────────────
  //
  // The setting says what the user chose; the probe says whether a paste can
  // actually happen. Where it cannot (no usable uinput device on Linux, a
  // missing macOS permission, no paste bridge), the transcript only reaches the
  // clipboard, so step 3 must not promise that text flows into the app.
  // The platform itself does not branch here: the native probe reports it
  // (macOS and Linux can report permissionMissing, Windows reports ready).

  group('ReadyStep — step 3 follows the paste capability (UIA-XP-7-12)', () {
    final cases =
        <
          ({String platform, PasteCapability? capability, bool expectAutoPaste})
        >[
          (
            platform: 'macOS',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.ready,
            ),
            expectAutoPaste: true,
          ),
          (
            platform: 'macOS',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            expectAutoPaste: false,
          ),
          (
            platform: 'Windows',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.ready,
            ),
            expectAutoPaste: true,
          ),
          (
            platform: 'Windows',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.unsupported,
            ),
            expectAutoPaste: false,
          ),
          (
            platform: 'Linux',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.ready,
            ),
            expectAutoPaste: true,
          ),
          (
            platform: 'Linux',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
            ),
            expectAutoPaste: false,
          ),
          (
            platform: 'Linux',
            capability: const PasteCapability(
              status: PasteCapabilityStatus.unsupported,
            ),
            expectAutoPaste: false,
          ),
          (platform: 'Linux', capability: null, expectAutoPaste: true),
        ];

    for (final c in cases) {
      final probe = c.capability?.status.name ?? 'no probe yet';
      testWidgets('paste setting on ${c.platform}, $probe → '
          '${c.expectAutoPaste ? 'Auto-Paste wording' : 'clipboard wording'}', (
        tester,
      ) async {
        await _pumpStep(
          tester,
          settings: _FakeSettingsNotifier(
            const AppSettings(
              afterTranscriptionSection: AfterTranscriptionSettings(
                afterTranscription: 'paste',
              ),
            ),
          ),
          pasteCapability: c.capability,
        );

        final copyText = l10n.onboardingReadyStep3CopyOnly(
          pasteShortcutLabel(l10n: l10n),
        );
        expect(
          find.textContaining(l10n.onboardingReadyStep3AutoPaste),
          c.expectAutoPaste ? findsOneWidget : findsNothing,
        );
        expect(
          find.textContaining(copyText),
          c.expectAutoPaste ? findsNothing : findsOneWidget,
        );
      });
    }
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
          find.textContaining(
            l10n.onboardingReadyStep3CopyOnly(pasteShortcutLabel(l10n: l10n)),
          ),
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
          find.textContaining(
            l10n.onboardingReadyStep3CopyOnly(pasteShortcutLabel(l10n: l10n)),
          ),
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
        find.textContaining(
          l10n.onboardingReadyStep3CopyOnly(pasteShortcutLabel(l10n: l10n)),
        ),
        findsOneWidget,
      );
    });
  });

  // ── The closing column ends on the third step ────────────────────────────
  //
  // Issue 10 originally closed this column with a muted context-carryover tip
  // (the ten-minute recognition-context window and when to pause before
  // switching topic). It is deliberately gone: the 2026-08-08 UX audit named
  // it as part of the final page's overload, and it explained a mechanism the
  // reader cannot have noticed yet on the one page that already asks them to
  // act. See the comment where it used to sit in `ready_step.dart`.
  //
  // Asserted rather than left implicit, because "add one more helpful muted
  // line" is exactly how this page got dense the first time.

  group('ReadyStep — quick-start rows', () {
    testWidgets('exactly three numbered rows, and nothing trailing them', (
      tester,
    ) async {
      final settings = _FakeSettingsNotifier();
      await _pumpStep(tester, settings: settings);

      expect(find.textContaining('1. '), findsOneWidget);
      expect(find.textContaining('2. '), findsOneWidget);
      expect(find.textContaining('3. '), findsOneWidget);
      expect(find.textContaining('4. '), findsNothing);

      expect(
        find.text(l10n.onboardingReadyContextCarryoverHint),
        findsNothing,
        reason:
            'The context-carryover tip was cut from the closing content — it '
            'is behaviour trivia about something the reader has not been able '
            'to observe yet, on the flow densest page.',
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

  // XP-6-14: step 1 of the quick start ("press the key") is only true once
  // the desktop shortcut carries the hotkey; until then the page says where
  // to set it up.
  group('ReadyStep — desktop shortcut still needed (XP-6-14)', () {
    const hint = ValueKey('onboarding-ready-desktop-shortcut-hint');

    for (final fallback in [
      DesktopShortcutFallback.gnome,
      DesktopShortcutFallback.manual,
    ]) {
      testWidgets('points back to the hotkey page (${fallback.name})', (
        tester,
      ) async {
        final settings = _FakeSettingsNotifier();
        await _pumpStep(tester, settings: settings, fallback: fallback);
        final s = AppSettings.defaults;
        expect(
          tester.widget<Text>(find.byKey(hint)).data,
          l10n.onboardingReadyDesktopShortcutHint(
            formatHotkeyKeycap(s.hotkeyModifiers, s.hotkeyKey, l10n: l10n),
          ),
        );
      });
    }

    testWidgets('no hint when the hotkey works system-wide', (tester) async {
      await _pumpStep(tester, settings: _FakeSettingsNotifier());
      expect(find.byKey(hint), findsNothing);
    });
  });
}
