/// The place on the onboarding frame for messages [WpOnboardingHold] holds back.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/onboarding_hold.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';

/// Shows the newest held-back message as a banner, whoever raised it.
///
/// No message appears in the main window while onboarding is open, so a message the setup needs
/// lands here. Closing it brings up the one before, so none is lost.
class OnboardingHeldNotice extends StatelessWidget {
  const OnboardingHeldNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WpHeldMessage>>(
      valueListenable: WpOnboardingHold.held,
      builder: (context, held, _) {
        if (held.isEmpty) return const SizedBox.shrink();
        final notice = held.last;
        final onAction = notice.onAction;
        final actionLabel = notice.actionLabel;
        final actionId = notice.actionTestId ?? 'onboarding-notice-action';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.xl,
            WpSpacing.sm,
            WpSpacing.xl,
            WpSpacing.sm,
          ),
          child: WpBanner(
            key: const ValueKey('onboarding-notice'),
            tone: switch (notice.type) {
              WpMessageType.error => WpBannerTone.error,
              WpMessageType.warning => WpBannerTone.warning,
              WpMessageType.success || WpMessageType.info => WpBannerTone.info,
            },
            message: notice.message,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onAction != null && actionLabel != null)
                  WpTextLink(
                    key: ValueKey(actionId),
                    label: actionLabel,
                    testID: actionId,
                    onPressed: () {
                      WpOnboardingHold.dismiss(notice);
                      onAction();
                    },
                  ),
                WpIconButton(
                  key: const ValueKey('onboarding-notice-dismiss'),
                  icon: LucideIcons.x,
                  tooltip: L10n.of(context).actionDismiss,
                  testId: 'onboarding-notice-dismiss',
                  onPressed: () => WpOnboardingHold.dismiss(notice),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
