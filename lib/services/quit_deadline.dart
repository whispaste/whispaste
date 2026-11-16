/// Hard deadline shared by every quit path: SIGTERM/SIGINT, tray "Beenden",
/// Cmd+Q / Dock Quit, the window's X when close means quit, "Quit" in the
/// first-run close dialog and "Quit" on a start screen (#1609). The orderly
/// shutdown runs first; if it has not finished after [kQuitHardDeadline], the
/// process ends without waiting for it. Otherwise a hung shutdown keeps the
/// old process alive and a new launch only focuses it.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/logging/app_logger.dart';
import 'graceful_shutdown.dart';

final _log = AppLogger('QuitDeadline');

/// How long an orderly shutdown may take before the process is ended anyway.
/// Normal quits finish in well under a second; the deadline only cuts off a
/// shutdown that is stuck.
const Duration kQuitHardDeadline = Duration(seconds: 3);

/// Runs [orderlyShutdown]. If it has not completed after [deadline], logs a
/// warning and calls [hardExit]. A failing orderly shutdown is logged and
/// completes normally: an error must not end the process by itself.
Future<void> shutdownWithHardDeadline({
  required Future<void> Function() orderlyShutdown,
  required void Function() hardExit,
  Duration deadline = kQuitHardDeadline,
}) {
  final done = Completer<void>();
  final timer = Timer(deadline, () {
    if (done.isCompleted) return;
    _log.warning(
      'Orderly shutdown did not finish within ${deadline.inMilliseconds} ms: '
      'ending the process',
    );
    hardExit();
    if (!done.isCompleted) done.complete();
  });
  Future<void>.sync(orderlyShutdown)
      .catchError((Object e) {
        _log.warning('Orderly shutdown failed (non-fatal): $e');
      })
      .whenComplete(() {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      });
  return done.future;
}

/// Runs one quit under the hard deadline at a time: a second request while a
/// quit is running (a second click on the X, tray "Beenden" during a window
/// quit) joins the running one instead of starting a second shutdown.
class QuitOnce {
  Future<void>? _running;

  /// True while a quit started through this instance has not finished.
  bool get isRunning => _running != null;

  Future<void> run({
    required Future<void> Function() orderlyShutdown,
    required void Function() hardExit,
    Duration deadline = kQuitHardDeadline,
  }) {
    return _running ??= shutdownWithHardDeadline(
      orderlyShutdown: orderlyShutdown,
      hardExit: hardExit,
      deadline: deadline,
    ).whenComplete(() => _running = null);
  }
}

/// The one in-app quit (tray, window X, first-run dialog, start screens).
/// Signals and the macOS Cmd+Q bridge keep their own deadline call: the
/// native terminate that `windowManager.destroy()` can trigger on macOS must
/// not join the quit that is waiting for it.
final QuitOnce appQuit = QuitOnce();

/// Quit from a window (the X when close means quit, "Quit" in the first-run
/// close dialog, "Quit" on a start screen): engines stop, then the window is
/// destroyed, all under the hard deadline. Same on macOS, Windows and Linux.
Future<void> quitFromWindow(ProviderContainer container) => appQuit.run(
  orderlyShutdown: () async {
    await runGracefulEngineShutdown(container);
    await windowManager.destroy();
  },
  hardExit: endProcessWithoutDestructors,
);
