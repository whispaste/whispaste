/// Dictation has priority over imports: an import's transcription waits while
/// a recording or a dictation transcription holds the transcriber.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';

class _FakeRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();

  void setPhase(RecordingPhase phase) => state = state.copyWith(phase: phase);
}

void main() {
  late ProviderContainer container;
  late _FakeRecording fake;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        recordingProvider.overrideWith(() {
          fake = _FakeRecording();
          return fake;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(recordingProvider);
  });

  test('busy phases hold the import back, idle and done do not', () {
    expect(dictationBusy(const RecordingState()), isFalse);
    expect(
      dictationBusy(const RecordingState(phase: RecordingPhase.done)),
      isFalse,
    );
    expect(
      dictationBusy(const RecordingState(phase: RecordingPhase.recording)),
      isTrue,
    );
    expect(
      dictationBusy(const RecordingState(phase: RecordingPhase.transcribing)),
      isTrue,
    );
    expect(
      dictationBusy(const RecordingState(phase: RecordingPhase.refining)),
      isTrue,
    );
  });

  test('returns at once when no dictation is running', () async {
    await waitForDictationIdle(container).timeout(const Duration(seconds: 1));
  });

  test(
    'waits while a dictation transcribes and resumes when it ends',
    () async {
      fake.setPhase(RecordingPhase.transcribing);
      var finished = false;
      final wait = waitForDictationIdle(container).then((_) => finished = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, isFalse, reason: 'import must yield to the dictation');

      fake.setPhase(RecordingPhase.done);
      await wait.timeout(const Duration(seconds: 1));
      expect(finished, isTrue);
    },
  );
}
