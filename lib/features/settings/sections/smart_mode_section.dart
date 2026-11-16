/// Smart Mode section of the Smart Mode page — standard-preset dropdown plus
/// the local Gemma-4-E2B-it model download.
///
/// No live dictation behavior is wired up here — this section only owns
/// schema (`AppSettings.smartMode`), the download, and the soft RAM warning.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/smart_mode_labels.dart';
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
import '../../../widgets/wp_progress_bar.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_example_box.dart';
import '../search/settings_search_entry.dart'
    show SettingsRowArea, settingsRowAnchorFor;
import '../settings_widgets.dart';
import 'api_keys_section.dart' show ApiKeyProvider, ApiKeyStatusLinkRow;
import '../widgets/custom_endpoint_rows.dart';
import '../widgets/wp_settings_group.dart';

/// Below this, [SmartModeSection] shows a soft warning before starting the
/// download — not a hard block (ticket 01, mirrors [hw.kMinRamMB]'s use for
/// STT, but Smart Mode's own threshold since it is a separate model class).
const int kSmartModeRamWarningThresholdMB = 8192;

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

/// The result of [preset] on the shared sample sentence, or null when the
/// preset has no fixed sample (Translate depends on the target language).
/// `off` returns the raw sample: the text is used exactly as transcribed.
String? smartModePresetExampleAfter(String preset, L10n l10n) =>
    switch (preset) {
      'off' => l10n.smartModeOnboardingHintExampleBefore,
      'cleanup' => l10n.smartModeOnboardingHintExampleAfter,
      'concise' => l10n.smartModeExampleConciseAfter,
      _ => null,
    };

class SmartModeSection extends ConsumerStatefulWidget {
  const SmartModeSection({super.key});

  @override
  ConsumerState<SmartModeSection> createState() => _SmartModeSectionState();
}

class _SmartModeSectionState extends ConsumerState<SmartModeSection> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final download = ref.watch(smartModeDownloadProvider);
    final provider = SmartModeProviderType.fromValue(
      settings.smartMode.provider,
    );
    final isLocal = provider.isLocal;
    final isOpenAi = provider == SmartModeProviderType.openAI;
    final localAvailable = ref.watch(smartModeLocalEngineAvailableProvider);
    // Without a usable text model only "Off" can be picked (UIA-XP-7-05).
    final textModelStatus = ref.watch(smartModeTextModelStatusProvider);
    final presetLockedReason = smartModeUnavailableReason(
      textModelStatus,
      l10n,
    );

    ref.listen<SmartModeDownloadState>(smartModeDownloadProvider, (
      previous,
      next,
    ) {
      if (next.phase != SmartModeDownloadPhase.done) return;
      if (previous?.phase == SmartModeDownloadPhase.done) return;
      if (!context.mounted) return;
      // The model row shows it is ready; a screen reader hears when.
      announce(
        View.of(context),
        l10n.smartModeDownloadComplete,
        Directionality.of(context),
      );
    });

    final presets = smartModePresetValues(settings.smartMode);

    String presetDescription(String preset) => switch (preset) {
      _ when settings.smartMode.customPresetFor(preset) != null =>
        settings.smartMode.customPresetFor(preset)!.instruction,
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
            items: presets,
            labels: [
              for (final p in presets)
                smartModePresetDisplayName(
                  p,
                  l10n,
                  settings: settings.smartMode,
                ),
            ],
            keyPrefix: 'settings-smart-mode-preset',
            disabledItems: presetLockedReason == null
                ? null
                : {
                    for (final p in presets)
                      if (p != 'off') p,
                  },
            disabledTooltip: presetLockedReason,
            onLockedTap: (_) =>
                answerLockedSmartModePreset(context, ref, textModelStatus),
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
        // Part of the preset row: why the presets are locked, readable
        // without hover, with the way out (#1686).
        if (smartModeLockedNoticeShown(textModelStatus))
          const WpSettingsDetail(child: SmartModeLockedNotice()),
        if (smartModePresetExampleAfter(settings.smartMode.standardPreset, l10n)
            case final after?)
          // Part of the preset row (layout rule 4): no divider in front.
          WpSettingsDetail(
            child: Semantics(
              identifier: 'smart-mode-preset-example',
              child: _PresetExample(
                before: l10n.smartModeOnboardingHintExampleBefore,
                after: after,
                l10n: l10n,
              ),
            ),
          ),
        // Only the translate preset uses a target language: a dependent row
        // right under the preset (layout rule 2), not under the service.
        if (settings.smartMode.standardPreset == 'translate')
          WpSettingsRow(
            rowId: 'text-smart-mode-target',
            indent: true,
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
        WpSettingsRow(
          rowId: 'text-smart-mode-service',
          title: l10n.settingsService,
          trailing: settingsDropdown(
            context: context,
            value: SmartModeProviderType.fromValue(
              settings.smartMode.provider,
            ).value,
            items: SmartModeProviderType.values.map((e) => e.value).toList(),
            labels: [
              l10n.settingsServiceOnDevicePrivate,
              'OpenAI',
              l10n.settingsSttCustomEndpoint,
            ],
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
        if (provider == SmartModeProviderType.custom)
          const CustomEndpointRows(scope: CustomEndpointScope.smartMode),
        // The key status and the model only matter for the chosen service:
        // both are dependent rows under it (layout rule 2). The key itself is
        // entered in the API keys area (#208).
        if (isOpenAi)
          const ApiKeyStatusLinkRow(
            rowId: 'text-smart-mode-key',
            provider: ApiKeyProvider.openAi,
            linkTestId: 'settings-smart-mode-api-keys-link',
            indent: true,
          ),
        if (isLocal && !localAvailable)
          HotkeyNotice(
            noticeKey: const Key('smartModeLocalUnavailableHint'),
            icon: LucideIcons.info,
            color: WpColors.textMuted,
            text: l10n.smartModeLocalUnavailable,
          ),
        if (isLocal && localAvailable)
          SettingsRowFrame(
            rowId: 'text-smart-mode-model',
            indent: true,
            child: _ModelDownloadRow(download: download, l10n: l10n),
          ),
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
            testId: 'smart-mode-shortcut-change',
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
      // Same vertical inset as a WpSettingsRow; the dependent indent comes
      // from the row frame (layout rule 2 of WpSettingsGroup).
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
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
                const SizedBox(height: WpSpacing.xs),
                Text(
                  l10n.smartModeMemoryFootprintInfo,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                Text(
                  l10n.smartModeFactGuardHint,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
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
                  const SizedBox(height: WpSpacing.xs),
                  _ProgressInfo(download: download, l10n: l10n),
                ] else if (download.isError) ...[
                  const SizedBox(height: WpSpacing.xs),
                  Text(
                    downloadFailureText(
                      l10n,
                      message: download.errorMessage,
                      kind: download.errorKind,
                    ),
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
              final confirmed = await showWpConfirmDialog(
                context: context,
                title: l10n.modelDeleteConfirm,
                message: l10n.modelDeleteConfirmMessage,
                confirmLabel: l10n.actionDelete,
                cancelLabel: l10n.actionCancel,
                destructive: true,
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

/// The Settings row that unlocks the Smart Mode presets for [status]: the fix
/// row ([smartModeFixRowId]), else the service row, where a build without the
/// local engine switches to a cloud provider. Null when nothing is locked.
String? smartModeUnlockRowId(SmartModeTextModelStatus status) =>
    status == SmartModeTextModelStatus.ready
    ? null
    : smartModeFixRowId(status) ?? 'text-smart-mode-service';

/// Whether [SmartModeLockedNotice] has something to say for [status]: the
/// presets are locked and a fix exists (download, key or endpoint). A build
/// without the local engine already shows its own hint at the service row.
bool smartModeLockedNoticeShown(SmartModeTextModelStatus status) =>
    smartModeFixRowId(status) != null;

/// Opens and highlights the row that unlocks the presets (#1686), on the
/// Smart Mode page or in Settings, wherever that row lives.
void openSmartModeUnlockRow(WidgetRef ref, SmartModeTextModelStatus status) {
  final rowId = smartModeUnlockRowId(status);
  if (rowId == null) return;
  ref.read(settingsScrollTargetProvider.notifier).set(rowId);
  final onSmartModePage =
      settingsRowAnchorFor(rowId)?.area == SettingsRowArea.smartMode;
  ref
      .read(activePageProvider.notifier)
      .setPage(onSmartModePage ? 'smartMode' : 'settings');
}

/// The answer to a click on a locked preset (#1686): never silence. The page
/// scrolls to and highlights what unlocks it (the model's download button,
/// the key, the endpoint) and a screen reader hears why.
void answerLockedSmartModePreset(
  BuildContext context,
  WidgetRef ref,
  SmartModeTextModelStatus status,
) {
  final reason = smartModeUnavailableReason(status, L10n.of(context));
  if (reason == null) return;
  announce(View.of(context), reason, Directionality.of(context));
  openSmartModeUnlockRow(ref, status);
}

/// Says at the preset picker that Smart Mode needs its text model first, with
/// the fix as a button (#1686): the download itself for the local model, else
/// the way to the key or endpoint. While the model downloads it shows the
/// progress instead; the presets unlock by themselves when it is done.
class SmartModeLockedNotice extends ConsumerWidget {
  const SmartModeLockedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final status = ref.watch(smartModeTextModelStatusProvider);
    if (!smartModeLockedNoticeShown(status)) return const SizedBox.shrink();
    final local = status == SmartModeTextModelStatus.localModelMissing;
    final download = ref.watch(smartModeDownloadProvider);

    final Widget banner;
    if (local && download.isBusy) {
      banner = WpBanner(
        tone: WpBannerTone.info,
        message: l10n.smartModeLockedDownloading(download.progressPercent),
      );
    } else {
      banner = WpBanner(
        tone: WpBannerTone.info,
        message: l10n.smartModeLockedNotice,
        action: WpButton(
          testId: 'smart-mode-locked-action',
          label: local
              ? l10n.smartModeLockedDownloadAction
              : smartModeFixLabel(status, l10n)!,
          icon: local ? LucideIcons.download : null,
          variant: WpButtonVariant.secondary,
          onPressed: local
              ? () => startSmartModeDownloadWithRamCheck(
                  context: context,
                  notifier: ref.read(smartModeDownloadProvider.notifier),
                  l10n: l10n,
                )
              : () => openSmartModeUnlockRow(ref, status),
        ),
      );
    }
    return Semantics(
      identifier: 'smart-mode-locked-notice',
      container: true,
      liveRegion: true,
      child: banner,
    );
  }
}

/// Starts the Smart Mode model download, first showing a soft RAM warning
/// (not a hard block) when [hw.detectRamMB] reports less than
/// [kSmartModeRamWarningThresholdMB] — shared between [SmartModeSection] and
/// the onboarding discovery touchpoints
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
        testId: 'smart-mode-download-cancel',
        variant: WpButtonVariant.secondary,
        onPressed: onCancel,
      );
    }
    if (download.modelDownloaded) {
      return WpButton(
        label: l10n.actionDelete,
        testId: 'smart-mode-model-delete',
        variant: WpButtonVariant.secondary,
        tone: WpButtonTone.danger,
        icon: LucideIcons.trash2,
        onPressed: onDelete,
      );
    }
    return WpButton(
      label: l10n.smartModeDownload,
      testId: 'smart-mode-model-download',
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
        WpProgressBar(
          value: isVerifying ? null : download.progressPercent / 100,
        ),
        const SizedBox(height: WpSpacing.xxs),
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

/// Raw sample and what the standard preset makes of it, so the preset's
/// strength is visible without recording anything.
class _PresetExample extends StatelessWidget {
  const _PresetExample({
    required this.before,
    required this.after,
    required this.l10n,
  });

  final String before;
  final String after;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    TextStyle style(Color color) =>
        TextStyle(fontSize: WpTypography.caption, color: color, height: 1.4);
    return WpExampleBox(
      overline: l10n.smartModeExampleOverline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${l10n.smartModeOnboardingHintExampleBeforeLabel}: $before',
            style: style(WpColors.textMuted),
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            '${l10n.smartModeOnboardingHintExampleAfterLabel}: $after',
            style: style(WpColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
