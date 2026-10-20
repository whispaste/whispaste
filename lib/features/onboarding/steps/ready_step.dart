import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/linux_desktop_shortcut.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paster.dart' show PasteCapabilityStatus;
import '../../../widgets/wp_button.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;
import '../stt_model_readiness.dart';
import 'onboarding_headings.dart';
import '../../../core/config/settings_labels.dart';

/// Closing content of the final onboarding page — quick-start guide and the
/// residual hotkey-conflict notice. Rendered as the trailing column beside
/// the guided test recording (see the shell's `tryAndGo` composition), so it
/// carries a section label rather than a second page title.
///
/// The autostart toggle that used to live here moved to the
/// Autostart & Auto-Paste page ([OnboardingAutostartToggle]); the Start CTA
/// and Back navigation are owned by the onboarding shell, which keeps the
/// residual safety gate: with a confirmed hotkey conflict the completion CTA
/// stays disabled rather than sending the user into a non-functional hotkey.
/// This widget only renders the matching heads-up text next to that gate.
@visibleForTesting
const kReadyStepBackToModelKey = Key('onboardingReadyStepBackToModel');
@visibleForTesting
const kReadyStepNoModelKey = Key('onboardingReadyStepNoModel');

class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key, this.onBackToModel});

  /// Returns to the speech-model step. Offered only while no model is
  /// installed (UIA-RT-01): "all set" would be false without one.
  final VoidCallback? onBackToModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final status = ref.watch(hotkeyRegistrationStatusProvider);
    final l10n = L10n.of(context);

    final accent = WpColors.accent;
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;

    // The completion CTA (owned by the onboarding shell) is gated on a healthy
    // hotkey registration; this content mirrors that gate with a short
    // heads-up so the disabled CTA never appears unexplained.
    final hasConflict = status == HotkeyRegistrationStatus.conflict;
    final desktopShortcutPending = ref.watch(desktopShortcutPendingProvider);
    // "All set" needs a model on disk or a saved cloud key. A running
    // download is no set-up: it lets the CTA through (UIA-MDL-GATE), but the
    // page keeps saying the model is missing until it is there.
    final modelInstalled = ref.watch(onboardingSttModelInstalledProvider);
    final cloudReady = ref.watch(onboardingCloudSttKeyProvider);
    final speechSetUp = modelInstalled || cloudReady;

    // Auto-Paste is active when `afterTranscription` is set to `paste` or
    // `clipboard_and_paste` — both inject the transcript at the cursor. The
    // other two states (`clipboard`, `nothing`) leave the user to paste with
    // ⌘V / Ctrl+V themselves, so step 3 must spell that out.
    final wantsAutoPaste = switch (settings.afterTranscriptionAction) {
      AfterTranscriptionAction.paste ||
      AfterTranscriptionAction.clipboardAndPaste => true,
      AfterTranscriptionAction.clipboard ||
      AfterTranscriptionAction.nothing => false,
    };
    // The setting alone is not enough: without a paste capability (Linux
    // without a usable uinput device, a missing macOS permission) the
    // transcript only reaches the clipboard, so step 3 must say that. Before
    // the first probe there is no answer yet, and the setting stands.
    final pasteStatus = ref
        .watch(pasteCapabilityNotifierProvider)
        .capability
        ?.status;
    final canAutoPaste =
        pasteStatus == null || pasteStatus == PasteCapabilityStatus.ready;
    final autoPasteAfterTranscription = wantsAutoPaste && canAutoPaste;
    final step3Text = autoPasteAfterTranscription
        ? l10n.onboardingReadyStep3AutoPaste
        : l10n.onboardingReadyStep3CopyOnly(pasteShortcutLabel(l10n: l10n));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section label, not a second page title: this block shares page 5
        // with the guided test recording, which owns the page heading. Two
        // headline-sized bold titles on one page was the single clearest
        // reason the flow read as "no structure".
        OnboardingSectionLabel(
          title: speechSetUp
              ? l10n.onboardingReadyTitle
              : l10n.onboardingReadyNoModelTitle,
          subtitle: l10n.onboardingReadySubtitle,
        ),
        const SizedBox(height: WpSpacing.lg),

        // Without a model or a cloud key nothing can be transcribed, so the
        // page says so and points back to the model step instead of claiming
        // the setup is complete (UIA-RT-01, UIA-MDL-GATE).
        if (!speechSetUp) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              l10n.onboardingReadyNoModelBody,
              key: kReadyStepNoModelKey,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: textMuted,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: WpButton(
                key: kReadyStepBackToModelKey,
                label: l10n.onboardingReadyBackToModel,
                variant: WpButtonVariant.secondary,
                tone: WpButtonTone.neutral,
                onPressed: onBackToModel,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
        ],

        // Residual conflict notice — the Hotkey page is the place to fix
        // this; here it explains the disabled completion CTA.
        //
        // Title *and* remedy: the headline alone ("hotkey already in use")
        // named the problem on the one page whose CTA it disables without
        // saying what to do about it. The remedy line is this page's own
        // string rather than the Hotkey page's — that one ends in "record a
        // new combination *below*", and there is no recorder below here.
        // Back reaches the Hotkey page in a few taps now that it is its own
        // page, which is cheaper than new deep-link navigation for a branch
        // this rare.
        if (hasConflict) ...[
          // Start-inset like the section label above and the instruction rows
          // below — these two lines used to start at the bare column edge,
          // 12 px left of everything else in the column.
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              l10n.onboardingTriggerHotkeyConflictTitle,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                fontWeight: FontWeight.w600,
                color: WpColors.error,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              l10n.onboardingReadyHotkeyConflictBody,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: textMuted,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
        ],

        // Step 1 below ("press the key") only holds once the desktop shortcut
        // carries the hotkey (XP-6-14). The Hotkey page shows the block that
        // sets it up, so this line names the way back rather than a second
        // copy of the block in a 3/9-wide column.
        if (!hasConflict && desktopShortcutPending) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              l10n.onboardingReadyDesktopShortcutHint(
                formatHotkeyKeycap(
                  settings.hotkeyModifiers,
                  settings.hotkeyKey,
                  l10n: l10n,
                  displayOverride: settings.hotkey.hotkeyKeyDisplay,
                ),
              ),
              key: const ValueKey('onboarding-ready-desktop-shortcut-hint'),
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: WpColors.warning,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
        ],

        // Quick start instructions
        _InstructionRow(
          number: '1.',
          text: l10n.onboardingReadyStep1,
          icon: LucideIcons.keyboard,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.lg),
        _InstructionRow(
          number: '2.',
          text: l10n.onboardingReadyStep2,
          icon: LucideIcons.micOff,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.lg),
        _InstructionRow(
          number: '3.',
          text: step3Text,
          icon: LucideIcons.clipboard,
          accent: accent,
          textColor: textPrimary,
        ),

        // NO trailing side note. The context-carryover tip that used to close
        // this column (two sentences on the ten-minute recognition-context
        // window and when to pause before switching topic) is gone on
        // purpose, and it is the single biggest cognitive-load cut on the
        // page: it was ~250 characters of behaviour trivia about a mechanism
        // the reader — who has not completed one real recording yet — has no
        // way to have noticed, parked on the one page that already asks them
        // to *do* something. The 2026-08-08 UX audit named it as part of this
        // page's overload (`.scratch/onboarding-ux-audit/befund.md`,
        // recommendation 1) and only the left column's two ambient lines were
        // merged in response; this is the other half of that finding.
        //
        // The behaviour it described is unchanged and self-correcting in
        // practice (a pause between topics), so nothing actionable is lost at
        // the moment it is dropped. Its l10n key stays in the `.arb` files —
        // removing it belongs to whoever gives the tip a permanent home in
        // Settings, next to the setting it actually concerns.
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Instruction row — numbered step with icon
// ---------------------------------------------------------------------------

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.number,
    required this.text,
    required this.icon,
    required this.accent,
    required this.textColor,
  });

  final String number;
  final String text;
  final IconData icon;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      label: '$number $text',
      child: Row(
        children: [
          // `sm` (16), not `md` (20). The glyph stands beside 14 px text, and
          // at 20 px it was taller than the line it belonged to — the icon
          // read as the row's subject and the numbered step as its caption.
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Icon(icon, size: WpIconSize.sm, color: accent),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              '$number $text',
              style: TextStyle(
                fontSize: WpTypography.subheading,
                color: textColor,
                // Explicit, and deliberately tighter than the gap between two
                // rows (`lg`, 20): a wrapped step used to set its own two
                // lines further apart than it sat from the next step, so the
                // three numbered steps read as one paragraph instead of as
                // three. Line spacing inside an item has to stay below the
                // spacing between items for grouping to be visible at all.
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
