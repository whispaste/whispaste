/// One-time hint for a hold-mode press that ended before its release could be
/// watched. A click on an on-screen keyboard presses and releases the key at
/// once, so holding cannot work with it. The app offers a one-click switch to
/// the "Tap or hold" option.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Longest press that counts as an on-screen keyboard click rather than a
/// hold. An on-screen keyboard presses and releases within a few milliseconds,
/// and a deliberate dictation hold lasts far longer than this, so the value
/// sits well between the two. The native hosts time the press from their event
/// timestamps, so a stalled UI thread does not change it.
const Duration shortPressMaxDuration = Duration(milliseconds: 150);

/// Holds the hint's due flag. The flag is set once per app session and cleared
/// when the UI has taken it.
class ShortPressHintNotifier extends Notifier<bool> {
  bool _shownThisSession = false;

  @override
  bool build() => false;

  /// Asks for the hint. Only a hold-to-talk setup can misfire this way, so
  /// nothing happens unless [holdModeOn]. A request outside hold mode does not
  /// use up the one-time hint.
  void request({required bool holdModeOn}) {
    if (!holdModeOn || _shownThisSession) return;
    _shownThisSession = true;
    state = true;
  }

  /// The UI has shown the hint.
  void consume() => state = false;
}

final shortPressHintProvider = NotifierProvider<ShortPressHintNotifier, bool>(
  ShortPressHintNotifier.new,
);
