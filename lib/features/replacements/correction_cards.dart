/// The switch that turns correction learning on or off, shown above the
/// dictionary's Suggestions tab. How corrections are noticed is said once, in
/// the banner under it; this row only carries the switch.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
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
    // No inset of its own: the list around it owns the page edges.
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.xxs),
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
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.correctionLearningToggleLabel,
            value: enabled,
            onChanged: onChanged,
            key: const ValueKey('dictionary-suggestions-learning-toggle'),
            testId: 'dictionary-suggestions-learning-toggle',
          ),
        ),
      ),
    );
  }
}
