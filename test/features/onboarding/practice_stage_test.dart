/// The practice step's stage is a pure function of the shared recording state
/// (#291): the same phases the overlay renders, no second source.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/onboarding/practice_stage.dart';

void main() {
  test('each recording phase maps to one practice stage', () {
    PracticeStage stageOf(RecordingPhase phase) =>
        practiceStageFor(RecordingState(phase: phase));

    expect(stageOf(RecordingPhase.idle), PracticeStage.idle);
    expect(stageOf(RecordingPhase.recording), PracticeStage.listening);
    expect(stageOf(RecordingPhase.transcribing), PracticeStage.processing);
    expect(stageOf(RecordingPhase.refining), PracticeStage.processing);
    expect(stageOf(RecordingPhase.done), PracticeStage.idle);
    expect(stageOf(RecordingPhase.error), PracticeStage.failed);
  });
}
