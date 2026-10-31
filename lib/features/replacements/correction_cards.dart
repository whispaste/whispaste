/// Two header cards of the dictionary's suggestion flow: the switch that
/// turns correction learning on or off, and the card that announces pending
/// suggestions. Shared by the Replacements list and the dictionary's
/// Suggestions tab, so both show the same switch and the same wording.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_button.dart';
import '../settings/settings_widgets.dart' show SettingRow, settingsToggle;

class CorrectionLearningToggleCard extends StatelessWidget {
  const CorrectionLearningToggleCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.xxs,
        WpSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
        decoration: BoxDecoration(
          color: WpColors.cardFill,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: SettingRow(
          icon: LucideIcons.sparkles,
          label: l10n.correctionLearningToggleLabel,
          subtitle: enabled
              ? l10n.correctionLearningToggleEnabled
              : l10n.correctionLearningToggleDisabled,
          semanticToggledValue: enabled,
          // The subtitle only says *that* corrections are watched, never
          // *how* to trigger one -- a user landing on this page cold has no
          // other way to discover the `correct:`/`korrektur:` voice-command
          // syntax (the only other explanation lives behind a one-shot,
          // permanently-dismissible hint in the History panel, see
          // `history_notes_section.dart`). An info tooltip next to the
          // toggle -- same pattern as `stt_model_selector.dart` -- adds that
          // without growing the row for everyone who already knows it.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: l10n.correctionLearningHowTo,
                child: Icon(
                  LucideIcons.info,
                  size: WpIconSize.xs,
                  color: WpColors.textMuted,
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              settingsToggle(value: enabled, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown only while there is at least one correction candidate awaiting
/// review — opens the shared vocabulary-import review page (PRD.md
/// decision: reuse it rather than build a second review UI).
class CorrectionCandidatesCard extends StatelessWidget {
  const CorrectionCandidatesCard({
    super.key,
    required this.count,
    required this.reviewing,
    required this.onReview,
  });

  final int count;
  final bool reviewing;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.xxs,
        WpSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
        decoration: BoxDecoration(
          color: WpColors.cardFill,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: SettingRow(
          icon: LucideIcons.lightbulb,
          label: l10n.correctionCandidatesCardTitle,
          subtitle: l10n.correctionCandidatesCardHint(count),
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          trailing: WpButton(
            key: const ValueKey('dictionary-suggestions-review'),
            label: l10n.correctionCandidatesReviewButton,
            variant: WpButtonVariant.secondary,
            size: WpButtonSize.dense,
            isLoading: reviewing,
            onPressed: reviewing ? null : onReview,
          ),
        ),
      ),
    );
  }
}
