/// Explains a login item that macOS holds back until the user approves it, and
/// offers the one action that fixes it: opening System Settings at Login Items.
///
/// Renders nothing unless [autostartApprovalNeededProvider] says approval is
/// pending, so it can sit under the autostart toggle on both the onboarding
/// page and the Settings interface section.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/autostart_service.dart';
import 'wp_button.dart';

class WpAutostartApprovalHint extends ConsumerWidget {
  const WpAutostartApprovalHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(autostartApprovalNeededProvider)) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context);
    return Padding(
      key: const ValueKey('autostart-approval-hint'),
      padding: const EdgeInsetsDirectional.only(
        start: WpSpacing.xl,
        top: WpSpacing.xs,
        bottom: WpSpacing.xs,
      ),
      child: Wrap(
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              l10n.autostartApprovalBody,
              style: TextStyle(
                fontSize: WpTypography.small,
                height: 1.4,
                color: WpColors.warning,
              ),
            ),
          ),
          WpButton(
            key: const ValueKey('autostart-approval-action'),
            label: l10n.autostartApprovalAction,
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.neutral,
            onPressed: () => unawaited(
              ref.read(autostartServiceProvider.notifier).openLoginItems(),
            ),
          ),
        ],
      ),
    );
  }
}
