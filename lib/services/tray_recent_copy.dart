/// Copy path for the recent-recordings submenu of the tray.
///
/// The menu lists recordings by id; the full text is kept here, out of the
/// menu, and only read when the user clicks an item. Locked history never
/// reaches this map, and a lock that engages clears it.
library;

import 'package:flutter/services.dart';

import 'clipboard_history/app_clipboard.dart';

/// Writes [text] to the OS clipboard the way paste does: first the native
/// history-excluded write (macOS concealed/transient type, Windows
/// `ExcludeClipboardContentFromMonitorProcessing`), then a plain write when
/// that is unavailable. The plain write is recorded by OS clipboard history
/// on platforms without an exclusion mechanism (Linux, see the ADR).
Future<void> writeTrayCopyTransient(
  String text, {
  Future<bool> Function(String text)? excludedWrite,
}) async {
  AppClipboard.markTransientWrite(text);
  final excluded = excludedWrite == null ? false : await excludedWrite(text);
  if (!excluded) await Clipboard.setData(ClipboardData(text: text));
}

/// Holds the texts behind the tray's recent-recording items.
class TrayRecentCopier {
  TrayRecentCopier({required this.isHidden, required this.write});

  /// Whether history text is withheld right now. Read again on every copy,
  /// so a lock that engaged after the last menu build still blocks it.
  final bool Function() isHidden;

  /// Performs the actual clipboard write for a copied text.
  final Future<void> Function(String text) write;

  Map<String, String> _content = const {};

  /// Replaces the listed texts by recording id. Nothing is kept while the
  /// history is hidden.
  void replace(Map<String, String> content) {
    _content = isHidden() ? const {} : Map.unmodifiable(content);
  }

  /// Drops every text, e.g. the moment the PIN lock engages.
  void clear() => _content = const {};

  /// Copies the text of recording [id]. Does nothing for an id that is not
  /// listed, and clears the texts instead when the history is hidden now.
  Future<void> copy(String id) async {
    if (isHidden()) {
      clear();
      return;
    }
    final text = _content[id];
    if (text == null) return;
    await write(text);
  }
}
