import 'paster.dart';

/// Auto-send (#564): one fixed extra key held while the recording shortcut is
/// released sends Enter after the paste. The key is Alt (Option on macOS), the
/// same on all three systems; there is no menu to pick another one.
const autoSendKeyName = 'alt';

/// The native side of auto-send, implemented by the desktop paster.
abstract interface class AutoSendKeys {
  /// Whether the extra key is physically down right now. False when the host
  /// cannot tell (e.g. a Wayland session): auto-send then never fires.
  Future<bool> extraKeyHeld();

  /// Sends one Enter to the frontmost app. False when nothing went out.
  Future<bool> sendEnter();
}

/// Whether the extra key is already part of the recording trigger and so
/// cannot be told apart from it: [hotkeyModifiers] is the stored `ctrl+shift`
/// style list, [doubleTapKey] the stored modifier-only trigger choice.
bool autoSendConflictsWithHotkey({
  required String hotkeyModifiers,
  String doubleTapKey = '',
}) {
  final parts = hotkeyModifiers.toLowerCase().split('+').map((p) => p.trim());
  if (parts.contains(autoSendKeyName) || parts.contains('option')) return true;
  return doubleTapKey == 'leftAlt' || doubleTapKey == 'rightAlt';
}

/// Whether Enter goes out now: the setting is on, the extra key was held at
/// the release, and the paste is *confirmed*. Every other outcome (blocked,
/// unconfirmed, target changed, …) never sends anything.
bool shouldSendEnterAfterPaste({
  required bool enabled,
  required bool extraKeyHeldAtRelease,
  required PasteOutcome outcome,
}) => enabled && extraKeyHeldAtRelease && outcome == PasteOutcome.success;
