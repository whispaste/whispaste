/// Pure rules of the rating dialog (#2185, maintainer decision 2026-11-24):
/// which rating way a build offers, when the dialog may open, and how a
/// streak of good dictations is counted. No I/O; the watcher in
/// `lib/features/review/review_ask_dialog.dart` wires it to the app.
library;

import '../../services/deploy_channel_service.dart';

/// How the rating part of the ask works on a build.
enum ReviewRateWay {
  /// Mac App Store: Apple's own rating dialog (StoreKit), requested by the
  /// app at the good moment. Our dialog itself asks for no rating there:
  /// guideline 5.6.1 allows review prompts only through the system API, and
  /// StoreKit must not be called from a button. Apple reports nothing back.
  appleSystemDialog,

  /// Microsoft Store package: "Bewerten" opens the Store's own
  /// rate-and-review dialog (`StoreContext.RequestRateAndReviewAppAsync`),
  /// which reports whether a rating was submitted.
  microsoftStoreDialog,

  /// Every other channel (installer, portable, package managers, Linux): a
  /// star on GitHub, the only public rating there is.
  githubStar,
}

/// The rating way of a build. [isMasBuild] wins; a store install on Windows
/// is the Microsoft Store package; everything else rates on GitHub.
ReviewRateWay reviewRateWayFor({
  required DeployChannel channel,
  required bool isMasBuild,
  required bool isWindows,
}) {
  if (isMasBuild) return ReviewRateWay.appleSystemDialog;
  if (channel == DeployChannel.store && isWindows) {
    return ReviewRateWay.microsoftStoreDialog;
  }
  return ReviewRateWay.githubStar;
}

/// Answer of the Microsoft Store rate-and-review dialog, as the Windows
/// runner reports it (`requestRateAndReview`).
enum StoreRateOutcome {
  /// A rating was submitted or updated: never ask again.
  succeeded,

  /// The user closed the Store dialog.
  cancelled,

  /// The Store could not be reached.
  networkError,

  /// The Store dialog failed for another reason.
  error,

  /// No Store context (unpackaged run, no Store on the device).
  unavailable,
}

/// Parses the wire name of a [StoreRateOutcome]; anything unknown is
/// [StoreRateOutcome.error].
StoreRateOutcome parseStoreRateOutcome(Object? raw) => switch (raw) {
  'succeeded' => StoreRateOutcome.succeeded,
  'cancelled' => StoreRateOutcome.cancelled,
  'networkError' => StoreRateOutcome.networkError,
  'unavailable' => StoreRateOutcome.unavailable,
  _ => StoreRateOutcome.error,
};

/// Whether the Store's review page should open instead: the native dialog
/// could not be shown. A cancel is an answer and opens nothing.
bool storeRateNeedsFallback(StoreRateOutcome outcome) => switch (outcome) {
  StoreRateOutcome.succeeded || StoreRateOutcome.cancelled => false,
  StoreRateOutcome.networkError ||
  StoreRateOutcome.error ||
  StoreRateOutcome.unavailable => true,
};

/// Good dictations in a row on one day before the dialog may open. Three is
/// a short, real run of success without making the ask rare: the usage
/// thresholds (20 dictations on 3 days) already lie behind it.
const int kReviewStreakMin = 3;

/// A new recording this soon after the last paste counts as a re-dictation:
/// the text was not good enough. Same window as `model/redictate`
/// (`kQuickRedictationWindow`).
const Duration kReviewRedictationWindow = Duration(seconds: 15);

/// Counts successful dictations in a row on the current day, in memory only.
///
/// A failed or unconfirmed paste, a WhisPaste undo right after the paste and
/// a quick re-dictation reset it; a new day starts at zero.
final class ReviewStreak {
  DateTime? _day;
  DateTime? _lastSuccessAt;
  int _count = 0;

  /// A dictation reached its field.
  void noteSuccess(DateTime at) {
    if (!_sameDay(_day, at)) _count = 0;
    _day = at;
    _lastSuccessAt = at;
    _count++;
  }

  /// Something went wrong (paste failed, the text was taken back).
  void noteSetback() {
    _count = 0;
    _lastSuccessAt = null;
  }

  /// A recording starts. Within [kReviewRedictationWindow] after the last
  /// success it is a re-dictation and breaks the run.
  void noteDictationStarted(DateTime at) {
    final last = _lastSuccessAt;
    if (last != null && at.difference(last) < kReviewRedictationWindow) {
      noteSetback();
    }
  }

  /// Successes in a row on [now]'s day.
  int countOn(DateTime now) => _sameDay(_day, now) ? _count : 0;

  /// Whether the run on [now]'s day is long enough for the ask.
  bool metOn(DateTime now) => countOn(now) >= kReviewStreakMin;

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Whether the rating dialog may open now. The review prompt service decides
/// [due] (thresholds, pauses, "Nicht mehr fragen"); this adds the moment:
/// never after a store rating ([storeRated]), only after a good run
/// ([streakMet]), never while the status line reports a problem, never during
/// onboarding, and only while the WhisPaste window is in front, so the ask
/// never covers another app.
bool reviewAskMayOpen({
  required bool due,
  required bool storeRated,
  required bool streakMet,
  required bool problemShown,
  required bool onboardingActive,
  required bool windowActive,
}) =>
    due &&
    !storeRated &&
    streakMet &&
    !problemShown &&
    !onboardingActive &&
    windowActive;
