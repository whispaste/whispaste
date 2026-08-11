library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';

import 'dialog.dart';
import 'wp_button.dart';

enum WpOomRecoveryChoice {
  trySmallerModel,
  switchToCloud,
  openSettings,
  cancel,
}

Future<WpOomRecoveryChoice?> showWpOomRecoveryDialog({
  required BuildContext context,
  required L10n l10n,
  required String? modelName,
  required bool hasCloudConfigured,
  required bool isPermanentFail,
}) {
  return showWpFormDialog<WpOomRecoveryChoice>(
    context: context,
    builder: (context, animation) {
      return _OomRecoveryDialog(
        animation: animation,
        l10n: l10n,
        modelName: modelName,
        hasCloudConfigured: hasCloudConfigured,
        isPermanentFail: isPermanentFail,
      );
    },
  );
}

class _OomRecoveryDialog extends StatelessWidget {
  const _OomRecoveryDialog({
    required this.animation,
    required this.l10n,
    required this.modelName,
    required this.hasCloudConfigured,
    required this.isPermanentFail,
  });

  final Animation<double> animation;
  final L10n l10n;
  final String? modelName;
  final bool hasCloudConfigured;
  final bool isPermanentFail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    const surface = WpColorsDark.surfaceElevated;
    const border = WpColorsDark.borderDefault;
    const titleColor = WpColorsDark.textPrimary;
    const bodyColor = WpColorsDark.textSecondary;
    const warningColor = WpColorsDark.warning;

    return Center(
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(WpSpacing.xl),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: WpRadius.borderLg,
                  border: Border.all(color: border),
                  boxShadow: WpShadows.elevated,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: warningColor.withValues(alpha: 0.14),
                            borderRadius: WpRadius.borderMd,
                          ),
                          child: const Icon(
                            LucideIcons.triangleAlert,
                            color: warningColor,
                            size: WpIconSize.lg,
                          ),
                        ),
                        const SizedBox(width: WpSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPermanentFail
                                    ? l10n.oomRecoveryPermanentTitle
                                    : l10n.oomRecoveryTitle,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: WpSpacing.xs),
                              Text(
                                isPermanentFail
                                    ? l10n.oomRecoveryPermanentMessage
                                    : l10n.oomRecoveryMessage,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: bodyColor,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: WpSpacing.xl),
                    if (!isPermanentFail && modelName != null) ...[
                      // loam-ignore: a11y-interactive-semantics – semantics provided by the WpButton in _RecoveryChoice.build
                      _RecoveryChoice(
                        label: l10n.oomRecoveryTrySmaller,
                        hint: l10n.oomRecoveryTrySmallerHint(modelName!),
                        variant: WpButtonVariant.primary,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(WpOomRecoveryChoice.trySmallerModel),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    if (hasCloudConfigured) ...[
                      // loam-ignore: a11y-interactive-semantics – semantics provided by the WpButton in _RecoveryChoice.build
                      _RecoveryChoice(
                        label: l10n.oomRecoverySwitchCloud,
                        hint: l10n.oomRecoverySwitchCloudHint,
                        variant: isPermanentFail
                            ? WpButtonVariant.primary
                            : WpButtonVariant.secondary,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(WpOomRecoveryChoice.switchToCloud),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    if (isPermanentFail || !hasCloudConfigured) ...[
                      // loam-ignore: a11y-interactive-semantics – semantics provided by the WpButton in _RecoveryChoice.build
                      _RecoveryChoice(
                        label: l10n.oomRecoveryPermanentCloud,
                        hint: null,
                        variant: hasCloudConfigured
                            ? WpButtonVariant.secondary
                            : WpButtonVariant.primary,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(WpOomRecoveryChoice.openSettings),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: WpButton(
                        label: l10n.oomRecoveryCancel,
                        variant: WpButtonVariant.ghost,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(WpOomRecoveryChoice.cancel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One recovery choice: a full-width [WpButton] with an optional line of
/// explanation beneath it.
///
/// The hint sits *outside* the button rather than as a second line inside it.
/// A [WpButton] label is single-line by design, and this dialog is the only
/// place in the app that ever wanted a two-storey button — so the exception
/// lives here as a composite instead of widening the shared component. Keeping
/// the hint a sibling also leaves it readable to screen readers rather than
/// hidden behind the button's own accessible name.
class _RecoveryChoice extends StatelessWidget {
  const _RecoveryChoice({
    required this.label,
    required this.hint,
    required this.variant,
    required this.onPressed,
  });

  final String label;
  final String? hint;
  final WpButtonVariant variant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WpButton(
          label: label,
          variant: variant,
          onPressed: onPressed,
          expanded: true,
        ),
        if (hint != null) ...[
          const SizedBox(height: WpSpacing.xxs),
          Text(
            hint!,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
