/// Shared bounded-wait helper for the whisper/Parakeet worker-isolate
/// shutdown paths — both engines send a shutdown signal to their worker,
/// then must wait for a graceful ack before the caller can safely assume
/// native resources were freed (FLUTTER_WHISPASTE-BC: killing an isolate
/// does not free native GPU/FFI memory that isolate's calls allocated, so
/// a hard kill can only be a timeout fallback, never the primary path).
library;

import 'dart:async';

import '../../core/logging/app_logger.dart';

/// Awaits [completer] for up to [timeout]; on timeout, logs [timeoutMessage]
/// via [log] and invokes [onTimeout] (typically a hard isolate kill) so a
/// stuck worker can't hang the app forever.
Future<void> awaitGracefulShutdown({
  required Completer<void> completer,
  required Duration timeout,
  required AppLogger log,
  required String timeoutMessage,
  required void Function() onTimeout,
}) async {
  try {
    await completer.future.timeout(timeout);
  } on TimeoutException {
    log.warning(timeoutMessage);
    onTimeout();
  }
}
