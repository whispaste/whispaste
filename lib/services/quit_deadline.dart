/// Hard deadline shared by every quit path (SIGTERM/SIGINT, tray "Beenden",
/// Cmd+Q). The orderly shutdown runs first; if it has not finished after
/// [kQuitHardDeadline], the process ends without waiting for it.
library;

import 'dart:async';

import '../core/logging/app_logger.dart';

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
