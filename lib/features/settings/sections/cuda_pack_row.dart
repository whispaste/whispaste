import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../services/model_download_service.dart'
    show formatModelSizeLabel;
import '../../../services/stt/whisper/cuda_pack.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/dialog.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';
import 'cuda_eula_dialog.dart';

/// Settings row for the optional NVIDIA CUDA pack (see `cuda_pack.dart`):
/// download with progress and cancel, then an on/off switch and a remove
/// button. The caller decides visibility via [cudaPackOfferedProvider].
class CudaPackRow extends ConsumerWidget {
  const CudaPackRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final state = ref.watch(cudaPackProvider);
    final pack = state.pack;
    if (pack == null) return const SizedBox.shrink();
    // Store builds: the driver download is not allowed there (AR-19). The row
    // stays visible, disabled, with the reason (WP-23g).
    if (ref.watch(deployChannelProvider) == DeployChannel.store) {
      return WpSettingsRow(
        rowId: 'speech-cuda-pack',
        title: l10n.settingsCudaPackTitle,
        key: const ValueKey('settings-row-speech-cuda-pack'),
        subtitle: l10n.settingsStoreCudaUnavailable,
        trailing: WpButton(
          label: l10n.settingsCudaPackDownload,
          variant: WpButtonVariant.secondary,
          onPressed: null,
        ),
      );
    }
    final notifier = ref.read(cudaPackProvider.notifier);

    if (state.installed && !state.isBusy) {
      // Without a current consent the pack is not loaded (see
      // activeCudaPackDirFor), so offer the review instead of the switch.
      final consented = ref.watch(
        settingsProvider.select(
          (s) => isCudaEulaAcceptedFor(
            accepted: s.value?.behavior.cudaEulaAccepted ?? '',
            packId: pack.id,
          ),
        ),
      );
      if (!consented) {
        return WpSettingsRow(
          rowId: 'speech-cuda-pack',
          title: l10n.settingsCudaPackTitle,
          key: const Key('settings-cuda-pack-row'),
          subtitle: l10n.settingsCudaPackConsentRequired,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WpButton(
                key: const Key('settings-cuda-pack-consent'),
                label: l10n.settingsCudaPackConsentReview,
                variant: WpButtonVariant.secondary,
                onPressed: () => _reviewConsent(context, ref),
              ),
              Semantics(
                label: l10n.settingsCudaPackRemove,
                button: true,
                child: IconButton(
                  key: const Key('settings-cuda-pack-remove'),
                  icon: const Icon(LucideIcons.trash2, size: WpIconSize.sm),
                  tooltip: l10n.settingsCudaPackRemove,
                  onPressed: () => _confirmRemove(context, notifier),
                ),
              ),
            ],
          ),
        );
      }
      final enabled = ref.watch(
        settingsProvider.select(
          (s) => s.value?.behavior.cudaAcceleration ?? true,
        ),
      );
      return WpSettingsRow(
        rowId: 'speech-cuda-pack',
        title: l10n.settingsCudaPackTitle,
        key: const Key('settings-cuda-pack-row'),
        subtitle: l10n.settingsCudaPackInstalledSubtitle,
        semanticToggledValue: enabled,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: l10n.settingsCudaPackToggle,
              child: settingsToggle(
                key: const Key('settings-cuda-pack-toggle'),
                value: enabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        behavior: s.behavior.copyWith(cudaAcceleration: v),
                      ),
                    ),
              ),
            ),
            Semantics(
              label: l10n.settingsCudaPackRemove,
              button: true,
              child: IconButton(
                key: const Key('settings-cuda-pack-remove'),
                icon: const Icon(LucideIcons.trash2, size: WpIconSize.sm),
                tooltip: l10n.settingsCudaPackRemove,
                onPressed: () => _confirmRemove(context, notifier),
              ),
            ),
          ],
        ),
      );
    }

    final Widget trailing;
    if (state.isBusy) {
      final downloading = state.phase == CudaPackPhase.downloading;
      trailing = SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    downloading
                        ? l10n.settingsCudaPackDownloading(
                            (state.progress * 100).floor(),
                          )
                        : l10n.settingsCudaPackInstalling,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (downloading)
                  Semantics(
                    label: l10n.settingsCudaPackCancel,
                    button: true,
                    child: IconButton(
                      key: const Key('settings-cuda-pack-cancel'),
                      icon: const Icon(LucideIcons.x, size: WpIconSize.xs),
                      tooltip: l10n.settingsCudaPackCancel,
                      onPressed: notifier.cancel,
                    ),
                  ),
              ],
            ),
            LinearProgressIndicator(
              key: const Key('settings-cuda-pack-progress'),
              value: downloading ? state.progress : null,
            ),
          ],
        ),
      );
    } else {
      final error = switch (state.error) {
        CudaPackError.network => l10n.settingsCudaPackErrorNetwork,
        CudaPackError.verification => l10n.settingsCudaPackErrorVerification,
        CudaPackError.storage => l10n.settingsCudaPackErrorStorage,
        null => null,
      };
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Padding(
                padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
                child: Text(
                  error,
                  key: const Key('settings-cuda-pack-error'),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.error,
                  ),
                ),
              ),
            ),
          WpButton(
            key: const Key('settings-cuda-pack-download'),
            label: l10n.settingsCudaPackDownload,
            variant: WpButtonVariant.ghost,
            icon: LucideIcons.download,
            onPressed: () => _requestDownload(context, ref, pack),
          ),
        ],
      );
    }

    return WpSettingsRow(
      rowId: 'speech-cuda-pack',
      title: l10n.settingsCudaPackTitle,
      key: const Key('settings-cuda-pack-row'),
      subtitle: l10n.settingsCudaPackSubtitle(
        formatModelSizeLabel(pack.archiveSizeBytes),
      ),
      trailing: trailing,
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    CudaPackNotifier notifier,
  ) async {
    final l10n = L10n.of(context);
    final confirmed = await confirmDestructive(
      context: context,
      title: l10n.settingsCudaPackRemoveConfirm,
      message: l10n.settingsCudaPackRemoveConfirmMessage,
      confirmLabel: l10n.settingsCudaPackRemove,
      cancelLabel: l10n.actionCancel,
    );
    if (confirmed) notifier.remove();
  }

  /// Opens the licence dialog for an installed pack. Accepting only records
  /// the consent; nothing is downloaded here.
  Future<void> _reviewConsent(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCudaEulaDialog(context);
    if (!confirmed || !context.mounted) return;
    await ref.read(cudaPackProvider.notifier).recordEulaConsent();
  }

  /// Download entry point: the NVIDIA EULA must be accepted for this pack
  /// version first. Cancel in the dialog changes nothing.
  Future<void> _requestDownload(
    BuildContext context,
    WidgetRef ref,
    CudaPackInfo pack,
  ) async {
    final notifier = ref.read(cudaPackProvider.notifier);
    // Awaited: the settings may still be loading when the row is first used.
    final settings = await ref.read(settingsProvider.future);
    if (!context.mounted) return;
    final accepted = isCudaEulaAcceptedFor(
      accepted: settings.behavior.cudaEulaAccepted,
      packId: pack.id,
    );
    if (accepted) {
      await notifier.install();
      return;
    }
    final confirmed = await showCudaEulaDialog(context);
    if (!confirmed || !context.mounted) return;
    await notifier.acceptEulaAndInstall();
  }
}
