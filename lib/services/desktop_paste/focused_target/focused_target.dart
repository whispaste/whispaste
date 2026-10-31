/// Which window has focus on the Linux desktop (V1 Wayland).
///
/// Under X11 the native paste host reads `_NET_ACTIVE_WINDOW`. Under
/// Wayland no client may read another client's focus, so each compositor
/// answers through its own interface (Sway IPC, Hyprland IPC, niri IPC,
/// KWin scripting, the optional GNOME Shell extension). Terminal detection,
/// the Auto-Paste block list and app profiles (WP-33a) all read the same
/// [FocusedTarget], whichever source produced it.
library;

/// The kind of client behind the focused window. Wayland windows report an
/// app id (`org.gnome.Ptyxis`, `foot`); XWayland and X11 windows a WM_CLASS.
enum FocusedClientType { wayland, x11, unknown }

class FocusedTarget {
  FocusedTarget._(this.identifiers, this.clientType, this.source);

  /// Builds a target from the names a source reported, most specific first.
  /// Empty and duplicate names are dropped; with none left there is no
  /// usable target and the result is null.
  static FocusedTarget? from(
    Iterable<String?> names, {
    required String source,
    FocusedClientType clientType = FocusedClientType.unknown,
  }) {
    final seen = <String>{};
    final identifiers = <String>[];
    for (final name in names) {
      final trimmed = name?.trim() ?? '';
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      identifiers.add(trimmed);
    }
    if (identifiers.isEmpty) return null;
    return FocusedTarget._(List.unmodifiable(identifiers), clientType, source);
  }

  /// Names for the window's app, most specific first and never empty. For
  /// X11 clients the WM_CLASS instance comes first, the value the native
  /// host reports, so block-list and profile rules written under X11 keep
  /// matching.
  final List<String> identifiers;
  final FocusedClientType clientType;

  /// Which source answered (`sway`, `kwin`, …), for logs and the status row.
  final String source;

  /// The single id the block list and app profiles compare.
  String get id => identifiers.first;

  @override
  String toString() =>
      'FocusedTarget($source, ${clientType.name}, ${identifiers.join('|')})';
}

/// One way to ask the desktop which window has focus.
abstract interface class FocusedTargetSource {
  /// Short name for logs and the status row (`sway`, `gnome-extension`).
  String get name;

  /// The focused window, or null when nothing has focus or the source cannot
  /// answer. Never throws; a source that fails reports null.
  Future<FocusedTarget?> focusedTarget();
}
