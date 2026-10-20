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

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/download_error_text.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_download_service.dart'
    show formatModelSizeLabel;
import '../../../services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;
import '../../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../../services/smart_mode/smart_mode_presets.dart';
import '../../../services/smart_mode/smart_mode_text_model.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

/// Below this, [SmartModeSection] shows a soft warning before starting the
/// download — not a hard block (ticket 01, mirrors [hw.kMinRamMB]'s use for
/// STT, but Smart Mode's own threshold since it is a separate model class).
const int kSmartModeRamWarningThresholdMB = 8192;

const List<String> _kPresets = ['off', 'cleanup', 'concise', 'translate'];

/// Shared by [SmartModeSection]'s standard-preset target-language row and
/// [SmartModeHotkeyBlock]'s hotkey-preset one — both dropdowns list the
/// same [smartModeValidatedTargetLanguages].
String Function(SmartModeTargetLanguage) smartModeTargetLanguageLabel(
  L10n l10n,
) =>
    (lang) => switch (lang) {
      SmartModeTargetLanguage.german => l10n.smartModeTargetLanguageGerman,
      SmartModeTargetLanguage.english => l10n.smartModeTargetLanguageEnglish,
      SmartModeTargetLanguage.spanish => l10n.smartModeTargetLanguageSpanish,
      SmartModeTargetLanguage.french => l10n.smartModeTargetLanguageFrench,
      SmartModeTargetLanguage.portuguese =>
        l10n.smartModeTargetLanguagePortuguese,
      SmartModeTargetLanguage.mandarin => l10n.smartModeTargetLanguageMandarin,
      SmartModeTargetLanguage.russian => l10n.smartModeTargetLanguageRussian,
    };

class SmartModeSection extends ConsumerStatefulWidget {
  const SmartModeSection({super.key});

  @override
  ConsumerState<SmartModeSection> createState() => _SmartModeSectionState();
}

class _SmartModeSectionState extends ConsumerState<SmartModeSection> {
  final _apiKeyCtrl = TextEditingController();
  bool _showKey = false;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final download = ref.watch(smartModeDownloadProvider);
    final isLocal = SmartModeProviderType.fromValue(
      settings.smartMode.provider,
    ).isLocal;
    final localAvailable = ref.watch(smartModeLocalEngineAvailableProvider);
    // Without a usable text model only "Off" can be picked (UIA-XP-7-05).
    final presetLockedReason = smartModeUnavailableReason(
      ref.watch(smartModeTextModelStatusProvider),
      l10n,
    );
    if (!isLocal) syncController(_apiKeyCtrl, settings.openAiApiKey);

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

    String presetDescription(String preset) => switch (preset) {
      'cleanup' => l10n.smartModePresetCleanupDescription,
      'concise' => l10n.smartModePresetConciseDescription,
      'translate' => l10n.smartModePresetTranslateDescription,
      _ => l10n.smartModePresetOffDescription,
    };

    final targetLanguageLabel = smartModeTargetLanguageLabel(l10n);

    return WpSettingsGroup(
      heading: l10n.settingsSmartMode,
      children: [
        WpSettingsRow(
          rowId: 'text-smart-mode-preset',
          title: l10n.smartModeStandardPreset,
          subtitle: presetDescription(settings.smartMode.standardPreset),
          trailing: settingsDropdown(
            context: context,
            value: settings.smartMode.standardPreset,
            items: _kPresets,
            labels: _kPresets.map(presetLabel).toList(),
            keyPrefix: 'settings-smart-mode-preset',
            disabledItems: presetLockedReason == null
                ? null
                : {
                    for (final p in _kPresets)
                      if (p != 'off') p,
                  },
            disabledTooltip: presetLockedReason,
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
        const SizedBox(height: WpSpacing.md),
        WpSettingsRow(
          rowId: 'text-smart-mode-service',
          title: l10n.settingsService,
          trailing: settingsDropdown(
            context: context,
            value: SmartModeProviderType.fromValue(
              settings.smartMode.provider,
            ).value,
            items: SmartModeProviderType.values.map((e) => e.value).toList(),
            labels: [l10n.settingsServiceOnDevicePrivate, 'OpenAI'],
            // A build without the bundled local engine (e.g. a Linux dev
            // build that skipped scripts/build-libllama-linux.sh) can only
            // fail on-device — keep the option visible but unselectable.
            disabledItems: localAvailable
                ? null
                : {SmartModeProviderType.local.value},
            disabledTooltip: localAvailable
                ? null
                : l10n.smartModeLocalUnavailable,
            onChanged: (v) {
              if (v == null) return;
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      smartMode: s.smartMode.copyWith(provider: v),
                    ),
                  );
            },
          ),
        ),
        if (!isLocal) ...[
          const SizedBox(height: WpSpacing.xs),
          WpSettingsRow(
            rowId: 'text-smart-mode-key',
            title: l10n.settingsOpenAiApiKey,
            subtitle: l10n.settingsOpenAiApiKeySubtitle,
            trailing: settingsApiKeyField(
              context: context,
              controller: _apiKeyCtrl,
              obscure: !_showKey,
              onToggle: () => setState(() => _showKey = !_showKey),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(openAiApiKey: v)),
              semanticLabel: l10n.settingsOpenAiApiKey,
            ),
          ),
        ],
        if (settings.smartMode.standardPreset == 'translate') ...[
          const SizedBox(height: WpSpacing.md),
          WpSettingsRow(
            rowId: 'text-smart-mode-target',
            title: l10n.smartModeTargetLanguage,
            subtitle: l10n.smartModeTargetLanguageSubtitle,
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
        if (isLocal && !localAvailable) ...[
          const SizedBox(height: WpSpacing.md),
          HotkeyNotice(
            noticeKey: const Key('smartModeLocalUnavailableHint'),
            icon: LucideIcons.info,
            color: WpColors.textMuted,
            text: l10n.smartModeLocalUnavailable,
          ),
        ],
        if (isLocal && localAvailable) ...[
          const SizedBox(height: WpSpacing.md),
          SettingsRowFrame(
            rowId: 'text-smart-mode-model',
            child: _ModelDownloadRow(download: download, l10n: l10n),
          ),
        ],
        const SizedBox(height: WpSpacing.md),
        WpSettingsRow(
          rowId: 'text-smart-mode-shortcut',
          title: l10n.settingsSmartModeShortcutLink(
            formatHotkeyKeycap(
              settings.smartModeHotkey.smartModeHotkeyModifiers,
              settings.smartModeHotkey.smartModeHotkeyKey,
              l10n: l10n,
              displayOverride:
                  settings.smartModeHotkey.smartModeHotkeyKeyDisplay,
            ),
          ),
          // The Smart Mode and selection-edit hotkeys are configured in the
          // Keyboard shortcuts area; this row only points there.
          trailing: WpButton(
            key: const Key('smartModeShortcutChange'),
            label: l10n.settingsChangeHotkey,
            variant: WpButtonVariant.secondary,
            onPressed: () {
              ref
                  .read(settingsScrollTargetProvider.notifier)
                  .set('general-hotkey-smart-mode');
              ref.read(activePageProvider.notifier).setPage('settings');
            },
          ),
        ),
      ],
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

    return Padding(
      // Text edge of the SettingRows above, not the section edge: the model
      // copy is the Smart Mode dependency and reads under its row.
      padding: const EdgeInsetsDirectional.fromSTEB(
        kSettingRowTextInset,
        0,
        kSettingRowInset,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // The label is the display name; the quantisation tag
                  // stays in the id and file name.
                  '${smartModeModel.label} · ${smartModeModel.sizeLabel}',
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    color: WpColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.smartModeMemoryFootprintInfo,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.smartModeFactGuardHint,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                SettingsRowFrame(
                  rowId: 'text-smart-mode-speed',
                  child: Text(
                    l10n.smartModeSpeedExampleInfo,
                    style: TextStyle(
                      fontSize: WpTypography.caption,
                      color: WpColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ),
                if (download.isBusy) ...[
                  const SizedBox(height: 6),
                  _ProgressInfo(download: download, l10n: l10n),
                ] else if (download.isError) ...[
                  const SizedBox(height: 4),
                  Text(
                    localizedDownloadError(l10n, download.errorMessage),
                    style: TextStyle(
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
            onDelete: () async {
              final confirmed = await confirmDestructive(
                context: context,
                title: l10n.modelDeleteConfirm,
                message: l10n.modelDeleteConfirmMessage,
                confirmLabel: l10n.actionDelete,
                cancelLabel: l10n.actionCancel,
              );
              if (confirmed) notifier.deleteModel();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload(
    BuildContext context,
    SmartModeDownloadNotifier notifier,
  ) => startSmartModeDownloadWithRamCheck(
    context: context,
    notifier: notifier,
    l10n: l10n,
  );
}

/// Starts the Smart Mode model download, first showing a soft RAM warning
/// (not a hard block) when [hw.detectRamMB] reports less than
/// [kSmartModeRamWarningThresholdMB] — shared between [SmartModeSection] and
/// the onboarding discovery touchpoints (ticket 08 of `.scratch/smart-mode-v2/`)
/// so both surfaces apply the identical warning gate.
Future<void> startSmartModeDownloadWithRamCheck({
  required BuildContext context,
  required SmartModeDownloadNotifier notifier,
  required L10n l10n,
}) async {
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
            valueColor: AlwaysStoppedAnimation(WpColors.accent),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isVerifying ? l10n.modelVerifying : _downloadingText(),
          style: TextStyle(
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
