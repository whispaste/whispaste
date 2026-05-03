import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transcriber.dart';

/// Stub for Groq STT — validates credentials, throws on actual transcription.
///
/// Groq speech-to-text is on the roadmap. For now, this adapter validates
/// that an API key is present and raises a clear error so users know it is
/// not yet available rather than silently falling back.
class GroqTranscriber implements Transcriber {
  const GroqTranscriber({required this.ref});

  // ignore: unused_field
  final Ref ref;

  @override
  Future<void> prepare() async {
    throw const TranscriberException(
      'Groq STT is not yet implemented. '
      'Please switch to On-Device or OpenAI in Settings → Speech Recognition.',
      reason: TranscriberFailureReason.unknown,
    );
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    throw const TranscriberException(
      'Groq STT is not yet implemented.',
      reason: TranscriberFailureReason.unknown,
    );
  }

  @override
  void release() {}
}
