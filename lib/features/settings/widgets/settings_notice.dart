/// Feedback of the settings page, shown at the section that raised it.
///
/// A thin wrapper on the shared page notice ([WpPageNotice], page
/// [kSettingsNoticePage]); a settings notice names its section in
/// [WpPageNotice.area], so only that section shows it (#452).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_page_notice.dart';
import '../../../widgets/wp_notice_bar.dart';

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
  if (!failed) {
    // A short confirmation stands at the bottom like every other (#1903);
    // an open error at the section stays.
    showWpConfirmation(
      context,
      id: 'settings-$id',
      message: message,
      duration: confirmFor,
    );
    return;
  }
  showWpPageNotice(
    context,
    page: kSettingsNoticePage,
    notice: WpPageNotice(id: 'settings-$id', message: message, area: area),
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
