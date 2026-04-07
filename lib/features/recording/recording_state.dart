/// Re-export from canonical location.
///
/// `RecordingState`, `RecordingNotifier`, and all recording providers now live
/// in `core/recording/` because they are shared across services, screens,
/// widgets, and features. This barrel export keeps existing imports working.
library;

export '../../core/recording/recording_state.dart';
