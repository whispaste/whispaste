/// Short confirmation at the overlay pill (#454).
///
/// A hotkey or tray action outside the window, such as switching the
/// dictation language or the profile, is confirmed for a moment at the pill,
/// where the user looks while dictating. With the overlay off the same text
/// shows as a short banner in the main window. A new hint replaces the one
/// on screen, so fast repeated presses never stack: only the last state stays.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/announce.dart';
import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_page_notice.dart';

/// How long the main window banner stays when the overlay is off.
const Duration kPillHintBannerTime = Duration(seconds: 4);

/// One confirmation for the pill. [serial] makes a repeated, identical hint
/// count as new.
@immutable
class OverlayPillHint {
  const OverlayPillHint({
    required this.id,
    required this.text,
    required this.serial,
    this.announced = false,
  });

  /// Stable name of the situation, for logs and tests.
  final String id;
  final String text;
  final int serial;

  /// The caller has read [text] out already; the overlay stays quiet (#633).
  final bool announced;
}

class OverlayPillHintNotifier extends Notifier<OverlayPillHint?> {
  @override
  OverlayPillHint? build() => null;

  void show({
    required String id,
    required String text,
    bool announced = false,
  }) {
    state = OverlayPillHint(
      id: id,
      text: text,
      serial: (state?.serial ?? 0) + 1,
      announced: announced,
    );
  }
}

/// The latest pill confirmation; the overlay service shows it.
final overlayPillHintProvider =
    NotifierProvider<OverlayPillHintNotifier, OverlayPillHint?>(
      OverlayPillHintNotifier.new,
    );

/// Whether hints reach the user at the overlay: on unless the user turned
/// the overlay off. Settings that are not loaded yet count as the default:
/// overlay on. The one rule for pill hints and microphone hints (#984).
bool overlayShowsHints(AppSettings? settings) =>
    settings?.effectiveOverlayMode != OverlayMode.off;

/// Confirms [text] at the pill, or in the main window when the overlay is
/// off. The text is read out here, once, either way; the overlay does not
/// read it again (#633).
void showOverlayPillHint(
  BuildContext context, {
  required String id,
  required String text,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final view = View.of(context);
  final direction = Directionality.of(context);
  final overlayOn = overlayShowsHints(container.read(settingsProvider).value);
  if (overlayOn) {
    container
        .read(overlayPillHintProvider.notifier)
        .show(id: id, text: text, announced: true);
  } else {
    container
        .read(wpPageNoticeProvider(kWpAppNoticePage).notifier)
        .show(
          WpPageNotice(
            id: 'pill-$id',
            message: text,
            tone: WpBannerTone.info,
            autoDismiss: kPillHintBannerTime,
          ),
        );
  }
  announce(view, text, direction);
}
