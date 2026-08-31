/// Smart Mode settings section — standard-preset dropdown plus the local
/// Gemma-4-E2B-it model download (ticket 01 of `.scratch/smart-mode-v2/`).
///
/// No live dictation behavior is wired up here — this section only owns
/// schema (`AppSettings.smartMode`), the download, and the soft RAM warning.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_download_service.dart'
    show formatModelSizeLabel;
import '../../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../../services/smart_mode/smart_mode_presets.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

/// Below this, [SmartModeSection] shows a soft warning before starting the
/// download — not a hard block (ticket 01, mirrors [hw.kMinRamMB]'s use for
/// STT, but Smart Mode's own threshold since it is a separate model class).
const int kSmartModeRamWarningThresholdMB = 8192;

const List<String> _kPresets = ['off', 'cleanup', 'concise', 'translate'];

class SmartModeSection extends ConsumerWidget {
  const SmartModeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final download = ref.watch(smartModeDownloadProvider);

    ref.listen<SmartModeDownloadState>(smartModeDownloadProvider, (
      previous,
      next,
    ) {
      if (next.phase != SmartModeDownloadPhase.done) return;
      if (previous?.phase == SmartModeDownloadPhase.done) return;
      if (!context.mounted) return;
      WpToast.show(
        context,
        message: l10n.smartModeDownloadComplete,
        type: WpToastType.success,
      );
    });

    String presetLabel(String preset) => switch (preset) {
      'cleanup' => l10n.smartModePresetCleanup,
      'concise' => l10n.smartModePresetConcise,
      'translate' => l10n.smartModePresetTranslate,
      _ => l10n.smartModePresetOff,
    };

    String targetLanguageLabel(SmartModeTargetLanguage lang) => switch (lang) {
      SmartModeTargetLanguage.german => l10n.smartModeTargetLanguageGerman,
      // Ticket 09 adds a label for each remaining language once it clears
      // its own validation spike — until then
      // smartModeValidatedTargetLanguages contains only german, so no other
      // branch is reachable.
      _ => lang.languageName,
    };

    return WpSection(
      title: l10n.settingsSmartMode,
      subtitle: l10n.settingsSmartModeSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.sparkles,
            label: l10n.smartModeStandardPreset,
            trailing: settingsDropdown(
              context: context,
              value: settings.smartMode.standardPreset,
              items: _kPresets,
              labels: _kPresets.map(presetLabel).toList(),
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        smartMode: s.smartMode.copyWith(standardPreset: v),
                      ),
                    );
              },
            ),
          ),
          if (settings.smartMode.standardPreset == 'translate') ...[
            const SizedBox(height: WpSpacing.md),
            SettingRow(
              icon: LucideIcons.languages,
              label: l10n.smartModeTargetLanguage,
              trailing: settingsDropdown(
                context: context,
                value: smartModeTargetLanguageFromSettingsValue(
                  settings.smartMode.targetLanguage,
                ).code,
                items: smartModeValidatedTargetLanguages
                    .map((lang) => lang.code)
                    .toList(),
                labels: smartModeValidatedTargetLanguages
                    .map(targetLanguageLabel)
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        (s) => s.copyWithSections(
                          smartMode: s.smartMode.copyWith(targetLanguage: v),
                        ),
                      );
                },
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.md),
          _ModelDownloadRow(download: download, l10n: l10n),
        ],
      ),
    );
  }
}

class _ModelDownloadRow extends ConsumerWidget {
  const _ModelDownloadRow({required this.download, required this.l10n});

  final SmartModeDownloadState download;
  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(smartModeDownloadProvider.notifier);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${smartModeModel.label} · ${smartModeModel.sizeLabel}',
                style: const TextStyle(
                  fontSize: WpTypography.body,
                  color: WpColors.textPrimary,
                ),
              ),
              if (download.isBusy) ...[
                const SizedBox(height: 6),
                _ProgressInfo(download: download, l10n: l10n),
              ] else if (download.isError) ...[
                const SizedBox(height: 4),
                Text(
                  download.errorMessage ?? '',
                  style: const TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: WpSpacing.md),
        _ActionButton(
          download: download,
          l10n: l10n,
          onDownload: () => _startDownload(context, notifier),
          onCancel: notifier.cancelDownload,
          onDelete: () => notifier.deleteModel(),
        ),
      ],
    );
  }

  Future<void> _startDownload(
    BuildContext context,
    SmartModeDownloadNotifier notifier,
  ) async {
    final ramMB = await hw.detectRamMB();
    if (ramMB != null && ramMB < kSmartModeRamWarningThresholdMB) {
      if (!context.mounted) return;
      final proceed = await showWpConfirmDialog(
        context: context,
        title: l10n.smartModeRamWarningTitle,
        message: l10n.smartModeRamWarningBody,
        confirmLabel: l10n.smartModeRamWarningContinue,
        cancelLabel: l10n.smartModeRamWarningCancel,
      );
      if (!proceed) return;
    }
    unawaited(notifier.downloadModel());
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.download,
    required this.l10n,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final SmartModeDownloadState download;
  final L10n l10n;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (download.isBusy) {
      return WpButton(
        label: l10n.actionCancel,
        variant: WpButtonVariant.secondary,
        onPressed: onCancel,
      );
    }
    if (download.modelDownloaded) {
      return WpButton(
        label: l10n.actionDelete,
        variant: WpButtonVariant.secondary,
        tone: WpButtonTone.danger,
        icon: LucideIcons.trash2,
        onPressed: onDelete,
      );
    }
    return WpButton(
      label: l10n.smartModeDownload,
      variant: WpButtonVariant.secondary,
      icon: LucideIcons.download,
      onPressed: onDownload,
    );
  }
}

class _ProgressInfo extends StatelessWidget {
  const _ProgressInfo({required this.download, required this.l10n});

  final SmartModeDownloadState download;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final isVerifying = download.phase == SmartModeDownloadPhase.verifying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(WpRadius.full),
          child: LinearProgressIndicator(
            value: isVerifying ? null : download.progressPercent / 100,
            minHeight: 3,
            backgroundColor: WpColors.borderSubtle,
            valueColor: const AlwaysStoppedAnimation(WpColors.accent),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isVerifying ? l10n.modelVerifying : _downloadingText(),
          style: const TextStyle(
            fontSize: WpTypography.caption,
            color: WpColors.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _downloadingText() {
    final parts = <String>[
      '${formatModelSizeLabel(download.bytesDownloaded)} / '
          '${formatModelSizeLabel(download.totalBytes)}',
    ];
    if (download.speedBytesPerSec > 100) {
      parts.add('${formatModelSizeLabel(download.speedBytesPerSec.round())}/s');
    }
    return parts.join(' · ');
  }
}
