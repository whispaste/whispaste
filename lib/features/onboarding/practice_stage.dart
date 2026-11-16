import '../../core/recording/recording_state.dart';

/// What the practice step shows of the dictation in progress. Derived only
/// from the shared [RecordingState], the same model the floating overlay
/// renders, so the two surfaces cannot disagree. The landed text and the
/// silence/paste answers stay with the step itself: they arrive through the
/// orchestrator's sink, not through this state.
enum PracticeStage { idle, listening, processing, failed }

PracticeStage practiceStageFor(RecordingState state) => switch (state.phase) {
  RecordingPhase.recording => PracticeStage.listening,
  RecordingPhase.transcribing ||
  RecordingPhase.refining => PracticeStage.processing,
  RecordingPhase.error => PracticeStage.failed,
  RecordingPhase.idle || RecordingPhase.done => PracticeStage.idle,
};
