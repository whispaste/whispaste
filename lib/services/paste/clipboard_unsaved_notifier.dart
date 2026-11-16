/// One-shot notice that the previous clipboard content could not be kept
/// after a paste (macOS pasteboard privacy denied the read).
///
/// Raised at most once per app session, so a user who keeps dictating is not
/// nagged; the toast is calm and does not block the paste.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClipboardUnsavedNotifier extends Notifier<bool> {
  bool _raisedThisSession = false;

  @override
  bool build() => false;

  /// Raises the notice unless it already fired in this session.
  void report() {
    if (_raisedThisSession) return;
    _raisedThisSession = true;
    state = true;
  }

  /// Resets the visible flag once the toast has been shown.
  void clear() {
    state = false;
  }
}

final clipboardUnsavedNotifierProvider =
    NotifierProvider<ClipboardUnsavedNotifier, bool>(
      ClipboardUnsavedNotifier.new,
    );
