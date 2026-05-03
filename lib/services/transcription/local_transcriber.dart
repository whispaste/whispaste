import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../stt_service.dart';
import 'transcriber.dart';

/// Delegates to the local whisper-server managed by [SttServiceNotifier].
class LocalTranscriber implements Transcriber {
  const LocalTranscriber({required this.ref});

  final Ref ref;

  SttServiceNotifier get _notifier => ref.read(sttServiceProvider.notifier);

  @override
  Future<void> prepare() async {
    // Let TimeoutException propagate unmodified so the orchestrator's
    // `.timeout()` handler fires as expected.
    try {
      await _notifier.ensureRunning();
    } on StateError catch (e) {
      throw TranscriberException(
        e.message,
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    // Let TimeoutException and connection errors propagate for the
    // orchestrator's per-error-type handlers.
    try {
      return await _notifier.transcribeBytes(wavBytes, language: language);
    } on StateError catch (e) {
      throw TranscriberException(
        e.message,
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  void release() {
    _notifier.notifyTranscriptionCompleted();
  }
}
