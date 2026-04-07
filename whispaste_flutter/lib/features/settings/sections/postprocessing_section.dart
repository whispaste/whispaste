/// Post-Processing & Text Replacements settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Post-Processing section — Coming Soon (backend not yet wired)
// ---------------------------------------------------------------------------

class PostProcessingSection extends ConsumerWidget {
  const PostProcessingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    return Opacity(
      opacity: 0.5,
      child: AbsorbPointer(
        child: WpSection(
          title: '${l10n.settingsPostProcessing} — Coming Soon',
          subtitle: l10n.settingsTextEnhancementSubtitle,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingRow(
                icon: LucideIcons.sparkles,
                label: l10n.settingsEnabled,
                trailing: settingsToggle(
                  value: false,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text Replacements section
// ---------------------------------------------------------------------------

class TextReplacementsSection extends ConsumerWidget {
  const TextReplacementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsTextReplacements,
      subtitle: l10n.settingsTextReplacementsSubtitle,
      padding: EdgeInsets.zero,
      child: SettingRow(
        icon: LucideIcons.replace,
        label: l10n.settingsTextReplacementsEnabled,
        trailing: settingsToggle(
          value: settings.textReplacementsEnabled,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                  (s) => s.copyWith(textReplacementsEnabled: v)),
        ),
      ),
    );
  }
}
