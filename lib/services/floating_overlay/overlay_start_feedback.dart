/// Start-feedback rule (briefing criterion 4, WP-84): the overlay must not
/// claim a live recording before the microphone is open.
///
/// `RecordingPhase.recording` is entered before the audio capture starts (the
/// paste target is primed and the capture opened afterwards). Until the first
/// non-silent sample arrives, the overlay shows the preparing state, which
/// reuses the transcribing composition, so that the live recording state
/// appears exactly when audio is really coming in.
library;

import '../../core/recording/recording_state.dart';

/// True while the overlay must show the preparing state instead of the live
/// recording state.
bool showsStartingFeedback({
  required RecordingPhase phase,
  required bool firstSampleSeen,
}) => phase == RecordingPhase.recording && !firstSampleSeen;
