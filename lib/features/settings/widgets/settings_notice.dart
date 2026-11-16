/// Feedback of the settings page, shown at the section that raised it.
///
/// A thin wrapper on the shared page notice ([WpPageNotice], page
/// [kSettingsNoticePage]); a settings notice names its section in
/// [WpPageNotice.area], so only that section shows it (#452).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_page_notice.dart';

/// Page id of the settings notice state.
const kSettingsNoticePage = WpNoticePage.settings;

/// How long a confirmation stays. An error stays until it is closed.
const Duration kSettingsConfirmationTime = Duration(seconds: 4);

/// Notice area of the overlay colour group, shared by the swatch picker that
/// raises the notice and the section that shows it.
const kOverlayNoticeArea = 'overlay';

/// Puts [message] in the notice slot of [area] and reads it out, replacing any
/// earlier settings notice. A [failed] one stays until it is closed; any other
/// closes itself after [confirmFor].
void showSettingsNotice(
  BuildContext context, {
  required String area,
  required String id,
  required String message,
  bool failed = false,
  Duration confirmFor = kSettingsConfirmationTime,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final open = container.read(wpPageNoticeProvider(kSettingsNoticePage));
  if (open != null && open.autoDismiss == null && !failed) {
    // A confirmation never pushes out an error that is still open.
    announce(View.of(context), message, Directionality.of(context));
    return;
  }
  showWpPageNotice(
    context,
    page: kSettingsNoticePage,
    notice: WpPageNotice(
      id: 'settings-$id',
      message: message,
      tone: failed ? WpBannerTone.error : WpBannerTone.info,
      area: area,
      autoDismiss: failed ? null : confirmFor,
    ),
  );
}

/// The place of [area]'s notice, directly below the section. Takes no room
/// while there is no notice for [area].
class SettingsNoticeSlot extends ConsumerWidget {
  const SettingsNoticeSlot({super.key, required this.area});

  final String area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(wpPageNoticeProvider(kSettingsNoticePage));
    if (notice?.area != area) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: WpPageNoticeSlot(page: kSettingsNoticePage, area: area),
    );
  }
}

/// Drops a confirmation left from an earlier visit. An open error stays until
/// the user closes it.
void dropStaleSettingsConfirmation(WidgetRef ref) {
  const page = kSettingsNoticePage;
  if (ref.read(wpPageNoticeProvider(page))?.autoDismiss == null) return;
  final notifier = ref.read(wpPageNoticeProvider(page).notifier);
  Future.microtask(notifier.dismiss);
}
