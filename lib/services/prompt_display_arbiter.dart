/// Single display arbiter for the post-recording nudges (review, support,
/// GitHub invitation).
///
/// The nudges never open concurrently, and at most one of them opens per app
/// session. A prompt claims the arbiter at the moment its dialog is actually
/// about to open, not when its state flag flips, so a prompt whose claim is
/// refused stays silent and is re-evaluated after the next recording.
///
/// A hotkey press closes the open prompt through [closeOpenPrompt]. The close
/// is a cancel, not a dismissal, so it does not start a snooze.
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The nudge dialogs that compete for the same display window.
enum PromptOwner { review, support, githubInvite }

final class PromptDisplayArbiter {
  PromptOwner? _open;
  VoidCallback? _closeOpen;
  bool _nudgeShownThisSession = false;

  /// Claims the display window for [owner]. Returns `false` when another
  /// prompt is open or a nudge has already been shown in this session.
  bool tryClaim(PromptOwner owner, {required VoidCallback close}) {
    if (_open != null || _nudgeShownThisSession) return false;
    _open = owner;
    _closeOpen = close;
    _nudgeShownThisSession = true;
    return true;
  }

  /// Releases the window if [owner] still holds it.
  void release(PromptOwner owner) {
    if (_open != owner) return;
    _open = null;
    _closeOpen = null;
  }

  /// Closes the open prompt, if any, without recording a dismissal.
  void closeOpenPrompt() {
    _closeOpen?.call();
  }
}

/// App-wide arbiter. One instance per session, shared by every nudge watcher.
final promptDisplayArbiterProvider = Provider<PromptDisplayArbiter>(
  (ref) => PromptDisplayArbiter(),
);
