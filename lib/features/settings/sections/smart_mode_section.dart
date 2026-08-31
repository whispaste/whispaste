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
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/hotkey_service.dart';
import '../../../services/model_download_service.dart'
    show formatModelSizeLabel;
import '../../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../../services/smart_mode/smart_mode_presets.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../hotkey_flow.dart';
import '../settings_widgets.dart';
import '../smart_mode_hotkey_flow.dart';

/// Below this, [SmartModeSection] shows a soft warning before starting the
/// download — not a hard block (ticket 01, mirrors [hw.kMinRamMB]'s use for
/// STT, but Smart Mode's own threshold since it is a separate model class).
const int kSmartModeRamWarningThresholdMB = 8192;

const List<String> _kPresets = ['off', 'cleanup', 'concise', 'translate'];

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

    String targetLanguageLabel(SmartModeTargetLanguage lang) => switch (lang) {
      SmartModeTargetLanguage.german => l10n.smartModeTargetLanguageGerman,
      SmartModeTargetLanguage.english => l10n.smartModeTargetLanguageEnglish,
      // Ticket 09 adds a label for each remaining language once it clears
      // its own validation spike — until then smartModeValidatedTargetLanguages
      // only contains german/english, so no other branch is reachable.
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
            subtitle: presetDescription(settings.smartMode.standardPreset),
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
          const SizedBox(height: WpSpacing.md),
          SettingRow(
            icon: LucideIcons.cpu,
            label: l10n.settingsService,
            trailing: settingsDropdown(
              context: context,
              value: SmartModeProviderType.fromValue(
                settings.smartMode.provider,
              ).value,
              items: SmartModeProviderType.values.map((e) => e.value).toList(),
              labels: [l10n.settingsServiceOnDevicePrivate, 'OpenAI'],
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
            SettingRow(
              icon: LucideIcons.keyRound,
              label: l10n.settingsOpenAiApiKey,
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
          if (isLocal) ...[
            const SizedBox(height: WpSpacing.md),
            _ModelDownloadRow(download: download, l10n: l10n),
          ],
          _SmartModeHotkeyBlock(settings: settings),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Smart-Mode hotkey (ticket 04) — fourth, independently configurable hotkey,
// bound to one of the three presets, applied regardless of the standard
// preset above.
// ---------------------------------------------------------------------------

class _SmartModeHotkeyBlock extends ConsumerStatefulWidget {
  const _SmartModeHotkeyBlock({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_SmartModeHotkeyBlock> createState() =>
      _SmartModeHotkeyBlockState();
}

class _SmartModeHotkeyBlockState extends ConsumerState<_SmartModeHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordSmartModeHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final smartModeHotkey = widget.settings.smartModeHotkey;
    final enabled = smartModeHotkey.smartModeHotkeyEnabled;

    // `enabled &&` per the same reasoning as the quick-note/Snippet-Picker
    // blocks: the registration status is in-memory and only registration
    // attempts write it, so a hotkey the user just switched off must not
    // keep complaining that it is "not active".
    final registrationFailed =
        enabled &&
        ref.watch(smartModeHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;

    String presetLabel(String preset) => switch (preset) {
      'concise' => l10n.smartModePresetConcise,
      'translate' => l10n.smartModePresetTranslate,
      _ => l10n.smartModePresetCleanup,
    };

    String presetDescription(String preset) => switch (preset) {
      'concise' => l10n.smartModePresetConciseDescription,
      'translate' => l10n.smartModePresetTranslateDescription,
      _ => l10n.smartModePresetCleanupDescription,
    };

    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          settingsInlineBreak,
          Padding(
            padding: const EdgeInsetsDirectional.only(start: WpSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingRow(
                  icon: LucideIcons.keyboardMusic,
                  label: l10n.settingsSmartModeHotkeyEnabled,
                  subtitle: l10n.settingsSmartModeHotkeyHint,
                  semanticToggledValue: enabled,
                  trailing: settingsToggle(
                    key: const Key('smartModeHotkeyToggle'),
                    value: enabled,
                    onChanged: (v) {
                      clearHotkeyCollision();
                      unawaited(setSmartModeHotkeyEnabled(ref, enabled: v));
                    },
                  ),
                ),
                AnimatedOpacity(
                  opacity: enabled ? 1.0 : 0.4,
                  duration: WpMotion.durationFor(context, WpMotion.normal),
                  child: ExcludeFocus(
                    excluding: !enabled,
                    child: IgnorePointer(
                      ignoring: !enabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SettingRow(
                            icon: LucideIcons.sparkles,
                            label: l10n.settingsSmartModeHotkeyPreset,
                            subtitle: presetDescription(
                              smartModeHotkey.smartModeHotkeyPreset,
                            ),
                            trailing: settingsDropdown(
                              context: context,
                              value: smartModeHotkey.smartModeHotkeyPreset,
                              items: const ['cleanup', 'concise', 'translate'],
                              labels: const [
                                'cleanup',
                                'concise',
                                'translate',
                              ].map(presetLabel).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                unawaited(
                                  setSmartModeHotkeyPreset(ref, preset: v),
                                );
                              },
                            ),
                          ),
                          HotkeyComboLine(
                            key: const Key('smartModeHotkeyComboLine'),
                            label: l10n.settingsSmartModeCurrentHotkey,
                            hotkeyKey: smartModeHotkey.smartModeHotkeyKey,
                            hotkeyModifiers:
                                smartModeHotkey.smartModeHotkeyModifiers,
                            hotkeyKeyDisplay:
                                smartModeHotkey.smartModeHotkeyKeyDisplay,
                            changeButtonKey: const Key('smartModeHotkeyChange'),
                            onChange: () => unawaited(_record()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (collidingAction != null)
                  _SmartModeHotkeyNotice(
                    noticeKey: const Key('smartModeHotkeyCollisionNotice'),
                    icon: LucideIcons.circleAlert,
                    color: WpColors.error,
                    text: l10n.settingsSmartModeHotkeyCollision(
                      collidingAction!,
                    ),
                  ),
                if (registrationFailed)
                  _SmartModeHotkeyNotice(
                    noticeKey: const Key('smartModeHotkeyInactiveNotice'),
                    icon: LucideIcons.triangleAlert,
                    color: WpColors.warning,
                    text: l10n.settingsSmartModeHotkeyInactive,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Local twin of the identically-shaped notice in `feedback_section.dart`
/// (quick-note/Snippet-Picker hotkey blocks) — same repo-wide per-file
/// duplication convention as the `*_hotkey_flow.dart` files, not accidental
/// duplication.
class _SmartModeHotkeyNotice extends StatelessWidget {
  const _SmartModeHotkeyNotice({
    required this.noticeKey,
    required this.icon,
    required this.color,
    required this.text,
  });

  final Key noticeKey;
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: noticeKey,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, WpSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: WpIconSize.sm, color: color),
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: WpTypography.caption,
                height: 1.4,
              ).copyWith(color: color),
            ),
          ),
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
              const SizedBox(height: 4),
              Text(
                l10n.smartModeMemoryFootprintInfo,
                style: const TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.smartModeSpeedExampleInfo,
                style: const TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.textMuted,
                  height: 1.4,
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
