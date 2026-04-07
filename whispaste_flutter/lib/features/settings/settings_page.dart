import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/page_shell.dart';
import 'sections/cloud_advanced_section.dart';
import 'sections/feedback_section.dart';
import 'sections/interface_section.dart';
import 'sections/overlay_button_section.dart';
import 'sections/postprocessing_section.dart';
import 'sections/recording_sections.dart';
import 'sections/stt_section.dart';
import 'settings_widgets.dart';

/// Settings page — thin coordinator that composes extracted section widgets.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Privacy Note ──
          _PrivacyBanner(isDark: isDark, l10n: l10n),
          const SizedBox(height: WpSpacing.md),

          // ═══════════════════════════════════════════
          //  RECORDING PIPELINE
          // ═══════════════════════════════════════════
          const AudioSection(),
          settingsSectionDivider(context),
          const RecordingSafetySection(),
          settingsSectionDivider(context),
          const AfterTranscriptionSection(),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  TRANSCRIPTION & ENHANCEMENT
          // ═══════════════════════════════════════════
          const SpeechRecognitionSection(),
          const SttModelSection(),
          settingsSectionDivider(context),
          const PostProcessingSection(),
          settingsSectionDivider(context),
          const TextReplacementsSection(),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  SHORTCUTS & FEEDBACK
          // ═══════════════════════════════════════════
          const KeyboardShortcutSection(),
          settingsSectionDivider(context),
          const SoundFeedbackSection(),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  DISPLAY & LAYOUT
          // ═══════════════════════════════════════════
          const OverlayButtonSection(),
          settingsSectionDivider(context),

          // ═══════════════════════════════════════════
          //  GENERAL
          // ═══════════════════════════════════════════
          const InterfaceSection(),
          settingsSectionDivider(context),
          const CloudProvidersSection(),
          settingsSectionDivider(context),
          const AdvancedSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy banner (top of settings page)
// ---------------------------------------------------------------------------

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.isDark, required this.l10n});

  final bool isDark;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle,
        borderRadius: WpRadius.borderSm,
        border: Border.all(
          color: isDark
              ? WpColorsDark.accent.withValues(alpha: 0.15)
              : WpColorsLight.accent.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.shieldCheck,
            size: WpIconSize.sm,
            color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              l10n.settingsPrivacyNote,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
