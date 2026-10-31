/// Carries the "hotkey could not be restored" notice from [HotkeyService] to
/// the UI toast layer. Same shape as the other notifiers the UI listens to:
/// each raised notice increments the counter, so a repeated notice is seen as
/// a change.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
