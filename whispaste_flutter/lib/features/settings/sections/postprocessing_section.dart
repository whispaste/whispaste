/// Post-Processing & Text Replacements settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Post-Processing section (needs local state for TextEditingControllers)
// ---------------------------------------------------------------------------

class PostProcessingSection extends ConsumerStatefulWidget {
  const PostProcessingSection({super.key});

  @override
  ConsumerState<PostProcessingSection> createState() =>
      _PostProcessingSectionState();
}

class _PostProcessingSectionState extends ConsumerState<PostProcessingSection> {
  final _customInstructionsCtrl = TextEditingController();

  @override
  void dispose() {
    _customInstructionsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    syncController(_customInstructionsCtrl, settings.smartModePrompt);

    return WpSection(
      title: l10n.settingsPostProcessing,
      subtitle: l10n.settingsTextEnhancementSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.sparkles,
            label: l10n.settingsEnabled,
            trailing: settingsToggle(
              value: settings.postProcessEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(postProcessEnabled: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.wandSparkles,
            label: l10n.settingsStyle,
            trailing: settingsDropdown(
              context: context,
              value: settings.postProcessPreset,
              items: PostProcessPreset.values
                  .map((e) => e.displayValue)
                  .toList(),
              labels: [
                l10n.settingsPresetCleanup,
                l10n.settingsPresetConcise,
                l10n.settingsPresetTranslate,
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(postProcessPreset: v!)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.server,
            label: l10n.settingsService,
            trailing: settingsDropdown(
              context: context,
              value: settings.postProcessProvider,
              items: PostProcessProviderType.values
                  .map((e) => e.value)
                  .toList(),
              labels: [
                l10n.statusLocal,
                'OpenAI',
                'Anthropic',
                'Groq',
                'Gemini',
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(postProcessProvider: v!)),
            ),
          ),
          if (settings.postProcessEnabled) ...[
            SettingRow(
              icon: LucideIcons.languages,
              label: l10n.settingsOutputLanguage,
              subtitle: l10n.settingsOutputLanguageSubtitle,
              trailing: settingsDropdown(
                context: context,
                value: settings.smartModeTarget.isEmpty
                    ? 'same'
                    : settings.smartModeTarget,
                items: const [
                  'same',
                  'English',
                  'German',
                  'French',
                  'Spanish',
                ],
                labels: [
                  l10n.settingsOutputLanguageSameAsInput,
                  l10n.settingsLanguageEnglish,
                  l10n.settingsLanguageGerman,
                  l10n.settingsLanguageFrench,
                  l10n.settingsLanguageSpanish,
                ],
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                        (s) => s.copyWith(
                            smartModeTarget: v == 'same' ? '' : v!)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.messageSquareText,
                        size: WpIconSize.sm,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: WpSpacing.sm),
                      Text(
                        l10n.settingsCustomInstructions,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 36,
                      top: WpSpacing.xs,
                    ),
                    child: Text(
                      l10n.settingsCustomInstructionsSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 36,
                      top: WpSpacing.xs,
                      right: WpSpacing.sm,
                      bottom: WpSpacing.xs,
                    ),
                    child: settingsTextField(
                      context: context,
                      controller: _customInstructionsCtrl,
                      hintText: l10n.settingsCustomInstructionsPlaceholder,
                      maxLines: 3,
                      onChanged: (v) => ref
                          .read(settingsProvider.notifier)
                          .updateSettings(
                              (s) => s.copyWith(smartModePrompt: v)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
