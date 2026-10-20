/// Local whisper-server transcriber that uses [SttServerStateNotifier].
///
/// Implements [Transcriber] using [SttServerStateNotifier].
/// The server lifecycle is managed exclusively through [localSttBundleProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stt_bundle.dart';

export '../transcription/transcriber.dart'
    show LanguageReportingTranscriber, Transcriber;
export '../transcription/transcriber_exception.dart';

/// Implements [Transcriber] by routing through the new [SttServerStateNotifier].
///
/// Ensures the server is running via [localSttBundleProvider], then issues
/// `POST /inference` through [SttServerStateNotifier.transcribeBytes].
class LocalSttTranscriber implements Transcriber, LanguageReportingTranscriber {
  const LocalSttTranscriber({required this.ref});

  final Ref ref;

  SttServerStateNotifier get _notifier =>
      ref.read(localSttBundleProvider.notifier);

  @override
  String? get lastDetectedLanguage => _notifier.lastDetectedLanguage;

  @override
  Future<void> prepare() async {
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
