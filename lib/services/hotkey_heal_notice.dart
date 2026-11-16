/// Carries the "hotkey could not be restored" notice from [HotkeyService] to
/// the UI toast layer. Same shape as the other notifiers the UI listens to:
/// each raised notice increments the counter, so a repeated notice is seen as
/// a change.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hotkey_observer_health.dart';

class HotkeyHealNoticeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void raise() => state = state + 1;
}

/// Riverpod handle for [HotkeyHealNoticeNotifier].
final hotkeyHealNoticeProvider =
    NotifierProvider<HotkeyHealNoticeNotifier, int>(
      HotkeyHealNoticeNotifier.new,
    );

/// Carries "the hotkey recorder ran out of its listening time" (#113) from
/// [HotkeyService] to the UI toast layer, as a counter like the notifier above.
class HotkeyCaptureTimeoutNoticeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void raise() => state = state + 1;
}

/// Riverpod handle for [HotkeyCaptureTimeoutNoticeNotifier].
final hotkeyCaptureTimeoutNoticeProvider =
    NotifierProvider<HotkeyCaptureTimeoutNoticeNotifier, int>(
      HotkeyCaptureTimeoutNoticeNotifier.new,
    );

/// One "the single-key hotkey was given up" notice (#773). A new instance per
/// raise, so a repeated notice with the same reason still counts as a change.
class HotkeyObserverLoss {
  const HotkeyObserverLoss(this.reason);

  final ObserverLossReason reason;
}

/// Carries [HotkeyObserverLoss] from [HotkeyService] to the UI toast layer:
/// the observer behind a modifier-only or fn hotkey stopped or lost its
/// permission, and the stored key combination listens in its place.
class HotkeyObserverLostNotifier extends Notifier<HotkeyObserverLoss?> {
  @override
  HotkeyObserverLoss? build() => null;

  void raise(ObserverLossReason reason) => state = HotkeyObserverLoss(reason);
}

/// Riverpod handle for [HotkeyObserverLostNotifier].
final hotkeyObserverLostNoticeProvider =
    NotifierProvider<HotkeyObserverLostNotifier, HotkeyObserverLoss?>(
      HotkeyObserverLostNotifier.new,
    );
