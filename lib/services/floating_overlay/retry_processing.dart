/// Whether a retry from the error card is transcribing the kept dictation
/// (#837).
///
/// The retry does not run through the recording state machine (a dictation
/// may start meanwhile), so the pill would stay idle. The orchestrator raises
/// this flag for the whole retry, and the overlay service shows the normal
/// processing frame while it is set. It is cleared in a `finally`, so a failed
/// or interrupted retry never leaves the pill stuck.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class RetryProcessingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool running) => state = running;
}

final retryProcessingProvider = NotifierProvider<RetryProcessingNotifier, bool>(
  RetryProcessingNotifier.new,
);
