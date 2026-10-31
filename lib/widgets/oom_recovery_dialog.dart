library;

import 'package:flutter/material.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';

import 'dialog.dart';

/// Key of the notice under the cloud action: the recordings leave the device.
const Key kOomRecoveryCloudNoticeKey = Key('oomRecoveryCloudNotice');

enum WpOomRecoveryChoice {
  trySmallerModel,
  switchToCloud,
  openSettings,
  cancel,
}

/// The one primary action of the recovery dialog (UX-019): the smaller model
/// when it is offered, otherwise the cloud switch, otherwise the settings
/// route. Every other choice renders as secondary.
WpOomRecoveryChoice oomRecoveryPrimaryChoice({
  required bool isPermanentFail,
  required bool hasModel,
  required bool hasCloudConfigured,
}) {
  if (!isPermanentFail && hasModel) return WpOomRecoveryChoice.trySmallerModel;
  if (hasCloudConfigured) return WpOomRecoveryChoice.switchToCloud;
  return WpOomRecoveryChoice.openSettings;
}

/// Shows the recovery dialog. Resolves to the chosen action, or `null` when
/// the dialog is dismissed (Esc, a tap outside).
Future<WpOomRecoveryChoice?> showWpOomRecoveryDialog({
  required BuildContext context,
  required L10n l10n,
  required String? modelName,
  required bool hasCloudConfigured,
  required bool isPermanentFail,
  String? cloudProviderName,
}) {
  final showTrySmaller = !isPermanentFail && modelName != null;
  final showCloud = hasCloudConfigured;
  final showSettings = isPermanentFail || !hasCloudConfigured;
  final primary = oomRecoveryPrimaryChoice(
    isPermanentFail: isPermanentFail,
    hasModel: modelName != null,
    hasCloudConfigured: hasCloudConfigured,
  );

  WpDialogAction<WpOomRecoveryChoice> choice(
    WpOomRecoveryChoice value,
    String label,
    String testId,
  ) => WpDialogAction(
    label: label,
    testId: testId,
    role: value == primary
        ? WpDialogActionRole.primary
        : WpDialogActionRole.alternative,
    value: value,
  );

  return showWpDialog<WpOomRecoveryChoice>(
    context: context,
    title: isPermanentFail
        ? l10n.oomRecoveryPermanentTitle
        : l10n.oomRecoveryTitle,
    content: _OomRecoveryBody(
      message: isPermanentFail
          ? l10n.oomRecoveryPermanentMessage
          : l10n.oomRecoveryMessage,
      trySmallerHint: !isPermanentFail && modelName != null
          ? l10n.oomRecoveryTrySmallerHint(modelName)
          : null,
      cloudHint: showCloud ? l10n.oomRecoverySwitchCloudHint : null,
      // The configured provider gets the audio, so say so right next to the
      // action that sends it there.
      cloudNotice: showCloud && cloudProviderName != null
          ? l10n.oomRecoveryCloudNotice(cloudProviderName)
          : null,
    ),
    actions: [
      if (showTrySmaller)
        choice(
          WpOomRecoveryChoice.trySmallerModel,
          l10n.oomRecoveryTrySmaller,
          'oom-recovery-try-smaller',
        ),
      if (showCloud)
        choice(
          WpOomRecoveryChoice.switchToCloud,
          l10n.oomRecoverySwitchCloud,
          'oom-recovery-switch-cloud',
        ),
      if (showSettings)
        choice(
          WpOomRecoveryChoice.openSettings,
          l10n.oomRecoveryPermanentCloud,
          'oom-recovery-open-settings',
        ),
      WpDialogAction(
        label: l10n.oomRecoveryCancel,
        testId: 'oom-recovery-cancel',
        role: WpDialogActionRole.cancel,
        value: WpOomRecoveryChoice.cancel,
      ),
    ],
  );
}

/// The explanation above the footer. Each offered action keeps its one-line
/// hint here, since the footer carries labels only.
class _OomRecoveryBody extends StatelessWidget {
  const _OomRecoveryBody({
    required this.message,
    required this.trySmallerHint,
    required this.cloudHint,
    required this.cloudNotice,
  });

  final String message;
  final String? trySmallerHint;
  final String? cloudHint;
  final String? cloudNotice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: theme.textTheme.bodyMedium),
        if (trySmallerHint != null) ...[
          const SizedBox(height: WpSpacing.sm),
          Text(trySmallerHint!, style: theme.textTheme.bodySmall),
        ],
        if (cloudHint != null) ...[
          const SizedBox(height: WpSpacing.sm),
          Text(cloudHint!, style: theme.textTheme.bodySmall),
        ],
        if (cloudNotice != null) ...[
          const SizedBox(height: WpSpacing.xxs),
          Text(
            cloudNotice!,
            key: kOomRecoveryCloudNoticeKey,
            style: theme.textTheme.bodySmall?.copyWith(color: WpColors.warning),
          ),
        ],
      ],
    );
  }
}
