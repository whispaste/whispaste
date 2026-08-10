import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;
import 'onboarding_headings.dart';

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
class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final status = ref.watch(hotkeyRegistrationStatusProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    // The completion CTA (owned by the onboarding shell) is gated on a healthy
    // hotkey registration; this content mirrors that gate with a short
    // heads-up so the disabled CTA never appears unexplained.
    final hasConflict = status == HotkeyRegistrationStatus.conflict;

    // Auto-Paste is active when `afterTranscription` is set to `paste` or
    // `clipboard_and_paste` — both inject the transcript at the cursor. The
    // other two states (`clipboard`, `nothing`) leave the user to paste with
    // ⌘V / Ctrl+V themselves, so step 3 must spell that out.
    final autoPasteAfterTranscription =
        switch (settings.afterTranscriptionAction) {
          AfterTranscriptionAction.paste ||
          AfterTranscriptionAction.clipboardAndPaste => true,
          AfterTranscriptionAction.clipboard ||
          AfterTranscriptionAction.nothing => false,
        };
    final step3Text = autoPasteAfterTranscription
        ? l10n.onboardingReadyStep3AutoPaste
        : l10n.onboardingReadyStep3CopyOnly;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section label, not a second page title: this block shares page 5
        // with the guided test recording, which owns the page heading. Two
        // headline-sized bold titles on one page was the single clearest
        // reason the flow read as "no structure".
        OnboardingSectionLabel(
          title: l10n.onboardingReadyTitle,
          subtitle: l10n.onboardingReadySubtitle,
        ),
        const SizedBox(height: WpSpacing.lg),

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
          Text(
            l10n.onboardingTriggerHotkeyConflictTitle,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.small,
              fontWeight: FontWeight.w600,
              color: isDark ? WpColorsDark.error : WpColorsLight.error,
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.onboardingReadyHotkeyConflictBody,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: textMuted,
              height: 1.35,
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
