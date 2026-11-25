/// Hide rules of the recording overlay (overlay F, #194).
///
/// "Eine Stunde ausblenden" in the pill's context menu hides the pill for one
/// hour without switching the overlay off: hotkey, paste and sounds go on as
/// before, only the pill stays off screen. The deadline is a point in time
/// held in memory, so a restart shows the pill again. Error states (a plain
/// error frame, every notice card) still show while the hour runs; otherwise
/// a recording could go nowhere without the user noticing. A guided snippet
/// sequence also still shows, because its frames are the only guidance it
/// has.
///
/// The tray offers "Overlay wieder einblenden (bis HH:MM ausgeblendet)" while
/// the hour runs, and "Overlay einschalten" while the overlay is switched off.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [platform] can keep the overlay out of screen captures
/// ([OverlayCaptureExclusion]): macOS and Windows. Linux has no such switch,
/// so Settings does not offer it there.
bool overlayCaptureExclusionApplies(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.windows;

/// Context-menu id of "Eine Stunde ausblenden".
const overlayMenuHideHour = 'hide_hour';

/// Context-menu id of "Overlay ausschalten" (sets the overlay mode to off).
const overlayMenuTurnOff = 'turn_off';

/// How long "Eine Stunde ausblenden" keeps the pill off screen.
const Duration kOverlayHideDuration = Duration(hours: 1);

/// Wall-clock source of the hide rules; tests override it.
final overlayHideClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Whether a frame stays off screen while the overlay is hidden.
///
/// Only a plain pill frame is held back. A notice card, an error frame and a
/// guided-sequence frame always show (see the library comment).
bool overlayFrameHeldBack({
  required DateTime? hiddenUntil,
  required DateTime now,
  required bool hasNotice,
  required bool isError,
  required bool guidance,
}) {
  if (hiddenUntil == null || !now.isBefore(hiddenUntil)) return false;
  return !hasNotice && !isError && !guidance;
}

/// The end of the running hide hour, or null while the pill shows normally.
///
/// The state clears itself when the hour is over, so the tray entry leaves
/// with it. A frame never trusts that timer alone: [hidesAt] compares with
/// the clock, so a timer that fires late (sleep) cannot keep the pill away.
class OverlayHiddenUntilNotifier extends Notifier<DateTime?> {
  Timer? _expiry;

  @override
  DateTime? build() {
    ref.onDispose(() => _expiry?.cancel());
    return null;
  }

  DateTime _now() => ref.read(overlayHideClockProvider)();

  /// Hides the pill for [kOverlayHideDuration] from now. A second call starts
  /// the hour again.
  void hideForAnHour() {
    final until = _now().add(kOverlayHideDuration);
    _expiry?.cancel();
    _expiry = Timer(kOverlayHideDuration, () {
      if (state == until) state = null;
    });
    state = until;
  }

  /// Ends the hide hour at once ("Overlay wieder einblenden").
  void showAgain() {
    _expiry?.cancel();
    _expiry = null;
    state = null;
  }

  /// Whether the hour still runs at [now] (the clock when omitted).
  bool hidesAt([DateTime? now]) {
    final until = state;
    return until != null && (now ?? _now()).isBefore(until);
  }
}

final overlayHiddenUntilProvider =
    NotifierProvider<OverlayHiddenUntilNotifier, DateTime?>(
      OverlayHiddenUntilNotifier.new,
    );
