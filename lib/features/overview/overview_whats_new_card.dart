import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_info.dart' show appVersion;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';
import 'overview_navigation.dart';
import 'overview_providers.dart';

/// W16: "Neu in dieser Version" for the running version. Shown until closed,
/// once per version; the nav entry carries a dot until the page was opened.
class OverviewWhatsNewCard extends ConsumerWidget {
  const OverviewWhatsNewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(overviewWhatsNewProvider);
    if (view.items.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return WpCard(
      key: const ValueKey('overview-whats-new'),
      title: l10n.overviewWhatsNewTitle,
      trailing: WpIconButton.ghost(
        testId: 'overview-whats-new-close',
        icon: LucideIcons.x,
        tooltip: l10n.overviewWhatsNewClose,
        onPressed: () =>
            ref.read(overviewPrefsProvider.notifier).closeWhatsNew(appVersion),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, item) in view.items.indexed) ...[
            if (i > 0) const SizedBox(height: WpSpacing.md),
            Text(item.title(l10n), style: WpTextStyles.rowTitle),
            const SizedBox(height: WpSpacing.xxs),
            Text(item.body(l10n), style: WpTextStyles.rowNote),
            const SizedBox(height: WpSpacing.xs),
            WpTextLink(
              testID: 'overview-whats-new-try-${item.id}',
              label: l10n.overviewTipTry,
              icon: LucideIcons.arrowRight,
              iconAfter: true,
              onPressed: () => overviewOpenTarget(ref, item.target),
            ),
          ],
        ],
      ),
    );
  }
}
