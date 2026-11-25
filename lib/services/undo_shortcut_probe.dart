/// Native watch for the user's own undo shortcut (Ctrl+Z, Cmd+Z) in another
/// app right after an auto-paste (#2078), for the model quality counters.
///
/// The native hosts only ever answer "an undo shortcut was pressed in
/// another app before the deadline" as one flag: no key, character or
/// timing leaves the host, and nothing is stored. Input is only looked at
/// between [UndoShortcutProbe.watch] and its deadline or
/// [UndoShortcutProbe.take], whichever comes first.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Answer of [UndoShortcutProbe.watch]: whether the new watch runs (false
/// where the platform cannot observe it: Wayland, no accessibility
/// permission, no keyboard hook) and whether the previous watch saw an undo.
typedef UndoShortcutWatchStart = ({bool watching, bool seen});

/// The native side of the undo shortcut watch.
abstract interface class UndoShortcutProbe {
  /// Arms a watch for [window] from now. Ends the previous one and reports
  /// what it saw, so a paste right after a paste loses nothing.
  Future<UndoShortcutWatchStart> watch(Duration window);

  /// Ends the running watch; whether it saw an undo shortcut.
  Future<bool> take();
}

/// [UndoShortcutProbe] over the desktop paste channel, the same on macOS,
/// Windows and Linux. A platform without the methods throws
/// [MissingPluginException]; the caller treats that as "not watched".
class ChannelUndoShortcutProbe implements UndoShortcutProbe {
  const ChannelUndoShortcutProbe([
    this._channel = const MethodChannel('com.whispaste.desktop_paste'),
  ]);

  final MethodChannel _channel;

  @override
  Future<UndoShortcutWatchStart> watch(Duration window) async {
    final answer = await _channel.invokeMapMethod<String, Object?>(
      'watchUndoShortcut',
      {'seconds': window.inSeconds},
    );
    return (
      watching: answer?['watching'] == true,
      seen: answer?['seen'] == true,
    );
  }

  @override
  Future<bool> take() async =>
      await _channel.invokeMethod<bool>('takeUndoShortcut') ?? false;
}

final undoShortcutProbeProvider = Provider<UndoShortcutProbe>(
  (_) => const ChannelUndoShortcutProbe(),
);
