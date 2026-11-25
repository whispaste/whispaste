/// The run of good dictations today, for the rating dialog's moment (#2185).
///
/// In memory only: a count, no text, no timestamps on disk. The recording
/// orchestrator reports successes and setbacks; the state is the run length
/// on today's date, so the `ReviewAskWatcher` reacts to every change.
library;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/review/review_ask.dart';

/// Pipeline outcomes that end a dictation without saying anything about its
/// quality: a cancel and a recording without speech.
const Set<String> _neutralOutcomes = {'ok', 'cancelled', 'empty_transcript'};

/// Whether a finished pipeline with [outcome] breaks the run of good
/// dictations (an error, a timeout, a failed append).
bool reviewStreakBrokenBy(String outcome) =>
    !_neutralOutcomes.contains(outcome);

class ReviewStreakNotifier extends Notifier<int> {
  final ReviewStreak _streak = ReviewStreak();

  @override
  int build() => 0;

  void _publish() => state = _streak.countOn(clock.now());

  /// A dictation reached its field.
  void noteSuccess() {
    _streak.noteSuccess(clock.now());
    _publish();
  }

  /// A failed paste, a failed dictation or an undo right after the paste.
  void noteSetback() {
    _streak.noteSetback();
    _publish();
  }

  /// A recording starts; a quick one after the last paste is a re-dictation.
  void noteDictationStarted() {
    _streak.noteDictationStarted(clock.now());
    _publish();
  }

  /// Whether today's run is long enough for the rating dialog.
  bool get met => _streak.metOn(clock.now());
}

final reviewStreakProvider = NotifierProvider<ReviewStreakNotifier, int>(
  ReviewStreakNotifier.new,
);
