library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';

import 'dialog.dart';

enum OomRecoveryChoice { trySmallerModel, switchToCloud, openSettings, cancel }

Future<OomRecoveryChoice?> showOomRecoveryDialog({
  required BuildContext context,
  required L10n l10n,
  required String? modelName,
  required bool hasCloudConfigured,
  required bool isPermanentFail,
}) {
  return showWpFormDialog<OomRecoveryChoice>(
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
    final isDark = theme.brightness == Brightness.dark;
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    final surface = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final border = isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;
    final titleColor = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final bodyColor = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final warningColor = isDark ? WpColorsDark.warning : WpColorsLight.warning;

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
                          child: Icon(
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
                      _ActionButton(
                        label: l10n.oomRecoveryTrySmaller,
                        hint: l10n.oomRecoveryTrySmallerHint(modelName!),
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(OomRecoveryChoice.trySmallerModel),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    if (hasCloudConfigured) ...[
                      _ActionButton(
                        label: l10n.oomRecoverySwitchCloud,
                        hint: l10n.oomRecoverySwitchCloudHint,
                        outlined: !isPermanentFail,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(OomRecoveryChoice.switchToCloud),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    if (isPermanentFail || !hasCloudConfigured) ...[
                      _ActionButton(
                        label: l10n.oomRecoveryPermanentCloud,
                        hint: null,
                        outlined: hasCloudConfigured,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(OomRecoveryChoice.openSettings),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            Navigator.of(context).pop(OomRecoveryChoice.cancel),
                        child: Text(l10n.oomRecoveryCancel),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.hint,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final String? hint;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final style = outlined
        ? OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(WpLayout.minTouchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
          )
        : FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(WpLayout.minTouchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
          );
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        if (hint != null) ...[
          const SizedBox(height: WpSpacing.xxs),
          Text(hint!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(onPressed: onPressed, style: style, child: child)
          : FilledButton(onPressed: onPressed, style: style, child: child),
    );
  }
}
