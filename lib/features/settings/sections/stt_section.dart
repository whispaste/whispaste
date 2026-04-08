/// Speech Recognition & STT Model settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/model_download_service.dart';
import '../../../widgets/model_download_card.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Quality tier helpers
// ---------------------------------------------------------------------------

const _qualityModelIds = [
  'whisper-tiny',
  'whisper-base',
  'whisper-small',
  'whisper-medium',
  'whisper-large-v3-turbo',
  'whisper-large-v3',
];

List<String> _qualityLabels(L10n l10n) => [
      l10n.settingsQualityFast,
      l10n.settingsQualityBasic,
      l10n.settingsQualityBalanced,
      '${l10n.settingsQualityHigh}  ${l10n.settingsQualityRecommended}',
      l10n.settingsQualityBest,
      l10n.settingsQualityMaximum,
    ];

String _qualityDescription(String modelId, L10n l10n) {
  final model = findSttModel(modelId);
  if (model == null) return '';
  return switch (modelId) {
    'whisper-tiny' => '${l10n.modelSizeTiny} (${model.sizeLabel})',
    'whisper-base' => '${l10n.modelSizeBase} (${model.sizeLabel})',
    'whisper-small' => '${l10n.modelSizeSmall} (${model.sizeLabel})',
    'whisper-medium' => '${l10n.modelSizeMedium} (${model.sizeLabel})',
    'whisper-large-v3-turbo' =>
      '${l10n.modelSizeLargeTurbo} (${model.sizeLabel})',
    'whisper-large-v3' => '${l10n.modelSizeLarge} (${model.sizeLabel})',
    _ => '',
  };
}

// ---------------------------------------------------------------------------
// Speech Recognition section
// ---------------------------------------------------------------------------

class SpeechRecognitionSection extends ConsumerWidget {
  const SpeechRecognitionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsSpeechRecognition,
      subtitle: l10n.settingsSpeechRecognitionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.cpu,
            label: l10n.settingsService,
            trailing: settingsDropdown(
              context: context,
              value: settings.sttProviderType.value,
              items:
                  SttProviderType.values.map((e) => e.value).toList(),
              labels: [
                l10n.settingsServiceOnDevicePrivate,
                'OpenAI',
                'Groq',
                'Deepgram',
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(sttProvider: v!)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.brain,
            label: l10n.settingsQuality,
            trailing: settingsDropdown(
              context: context,
              value: _qualityModelIds.contains(settings.sttModel)
                  ? settings.sttModel
                  : 'whisper-medium',
              items: _qualityModelIds,
              labels: _qualityLabels(l10n),
              onChanged: (v) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(sttModel: v!));
                final dlState = ref.read(modelDownloadProvider);
                if (!dlState.downloadedModels.contains(v) && !dlState.isBusy) {
                  ref.read(modelDownloadProvider.notifier).downloadModel(v!);
                }
              },
            ),
          ),
          // Quality description + download status
          _QualityStatusRow(modelId: settings.sttModel),
          SettingRow(
            icon: LucideIcons.languages,
            label: l10n.settingsRecognitionLanguage,
            trailing: settingsDropdown(
              context: context,
              value: settings.sttLanguage,
              items: const [
                'Auto-detect',
                'English',
                'German',
                'French',
                'Spanish',
              ],
              labels: [
                l10n.settingsLanguageAutoDetect,
                l10n.settingsLanguageEnglish,
                l10n.settingsLanguageGerman,
                l10n.settingsLanguageFrench,
                l10n.settingsLanguageSpanish,
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(sttLanguage: v!)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quality status row — download progress + description
// ---------------------------------------------------------------------------

class _QualityStatusRow extends ConsumerWidget {
  const _QualityStatusRow({required this.modelId});
  final String modelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dlState = ref.watch(modelDownloadProvider);
    final isDownloaded = dlState.downloadedModels.contains(modelId);
    final isDownloading = dlState.isBusy && dlState.activeModelId == modelId;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final success = isDark ? WpColorsDark.success : WpColorsLight.success;
    final textSec =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(
        left: 52,
        right: WpSpacing.md,
        bottom: WpSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _qualityDescription(modelId, l10n),
            style: TextStyle(fontSize: 11, color: textSec),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isDownloaded
                    ? LucideIcons.circleCheck
                    : isDownloading
                        ? LucideIcons.loader
                        : LucideIcons.download,
                size: 12,
                color: isDownloaded
                    ? success
                    : isDownloading
                        ? accent
                        : textSec,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isDownloaded
                      ? l10n.settingsModelStatusReady
                      : isDownloading
                          ? '${l10n.settingsModelStatusDownloading} ${dlState.progressPercent}%'
                          : l10n.settingsModelStatusNeeded,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDownloaded
                        ? success
                        : isDownloading
                            ? accent
                            : textSec,
                  ),
                ),
              ),
            ],
          ),
          if (isDownloading && dlState.phase == DownloadPhase.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WpRadius.full),
                child: LinearProgressIndicator(
                  value: dlState.progressPercent / 100,
                  minHeight: 2,
                  backgroundColor: isDark
                      ? WpColorsDark.borderSubtle
                      : WpColorsLight.borderSubtle,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// STT Model Management section
// ---------------------------------------------------------------------------

class SttModelSection extends ConsumerWidget {
  const SttModelSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return WpSection(
      title: l10n.settingsSttModels,
      padding: EdgeInsets.zero,
      child: const SttModelManager(),
    );
  }
}
