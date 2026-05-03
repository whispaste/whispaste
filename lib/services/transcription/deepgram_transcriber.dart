import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transcriber.dart';

/// Stub for Deepgram STT — raises a clear error rather than silently failing.
class DeepgramTranscriber implements Transcriber {
  const DeepgramTranscriber({required this.ref});

  // ignore: unused_field
  final Ref ref;

  @override
  Future<void> prepare() async {
    throw const TranscriberException(
      'Deepgram STT is not yet implemented. '
      'Please switch to On-Device or OpenAI in Settings → Speech Recognition.',
      reason: TranscriberFailureReason.unknown,
    );
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    throw const TranscriberException(
      'Deepgram STT is not yet implemented.',
      reason: TranscriberFailureReason.unknown,
    );
  }

  @override
  void release() {}
}
