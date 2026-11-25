/// Rules of the rating dialog (#2185): rating way per build, the Store's
/// answer, the run of good dictations and the moment it may open.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/review/review_ask.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/review_streak_provider.dart';

void main() {
  group('rating way per build', () {
    test('Mac App Store asks through Apple, whatever the channel says', () {
      expect(
        reviewRateWayFor(
          channel: DeployChannel.store,
          isMasBuild: true,
          isWindows: false,
        ),
        ReviewRateWay.appleSystemDialog,
      );
    });

    test('the Microsoft Store package uses the Store dialog', () {
      expect(
        reviewRateWayFor(
          channel: DeployChannel.store,
          isMasBuild: false,
          isWindows: true,
        ),
        ReviewRateWay.microsoftStoreDialog,
      );
    });

    test('every other channel asks for a GitHub star', () {
      for (final channel in [
        DeployChannel.installer,
        DeployChannel.portable,
        DeployChannel.packageManaged,
      ]) {
        for (final windows in [true, false]) {
          expect(
            reviewRateWayFor(
              channel: channel,
              isMasBuild: false,
              isWindows: windows,
            ),
            ReviewRateWay.githubStar,
          );
        }
      }
    });
  });

  group('Store answer', () {
    test('wire names parse, unknown ones are errors', () {
      expect(parseStoreRateOutcome('succeeded'), StoreRateOutcome.succeeded);
      expect(parseStoreRateOutcome('cancelled'), StoreRateOutcome.cancelled);
      expect(
        parseStoreRateOutcome('networkError'),
        StoreRateOutcome.networkError,
      );
      expect(
        parseStoreRateOutcome('unavailable'),
        StoreRateOutcome.unavailable,
      );
      expect(parseStoreRateOutcome('boom'), StoreRateOutcome.error);
      expect(parseStoreRateOutcome(null), StoreRateOutcome.error);
    });

    test('only a failed Store dialog falls back to the review page', () {
      expect(storeRateNeedsFallback(StoreRateOutcome.succeeded), isFalse);
      expect(storeRateNeedsFallback(StoreRateOutcome.cancelled), isFalse);
      expect(storeRateNeedsFallback(StoreRateOutcome.networkError), isTrue);
      expect(storeRateNeedsFallback(StoreRateOutcome.error), isTrue);
      expect(storeRateNeedsFallback(StoreRateOutcome.unavailable), isTrue);
    });
  });

  group('run of good dictations', () {
    final morning = DateTime(2026, 11, 24, 9);

    test('three in a row on one day meet it', () {
      final streak = ReviewStreak();
      for (var i = 0; i < kReviewStreakMin - 1; i++) {
        streak.noteSuccess(morning.add(Duration(minutes: i)));
      }
      expect(streak.metOn(morning), isFalse);
      streak.noteSuccess(morning.add(const Duration(minutes: 5)));
      expect(streak.metOn(morning), isTrue);
    });

    test('a setback starts over', () {
      final streak = ReviewStreak()
        ..noteSuccess(morning)
        ..noteSuccess(morning.add(const Duration(minutes: 1)))
        ..noteSetback()
        ..noteSuccess(morning.add(const Duration(minutes: 2)));
      expect(streak.countOn(morning), 1);
    });

    test('a quick re-dictation breaks it, a later dictation does not', () {
      final streak = ReviewStreak()
        ..noteSuccess(morning)
        ..noteDictationStarted(morning.add(const Duration(seconds: 5)));
      expect(streak.countOn(morning), 0);

      streak
        ..noteSuccess(morning)
        ..noteDictationStarted(morning.add(const Duration(minutes: 2)));
      expect(streak.countOn(morning), 1);
    });

    test('a new day starts at zero', () {
      final streak = ReviewStreak();
      for (var i = 0; i < kReviewStreakMin; i++) {
        streak.noteSuccess(morning.add(Duration(minutes: i)));
      }
      final tomorrow = morning.add(const Duration(days: 1));
      expect(streak.metOn(tomorrow), isFalse);
      streak.noteSuccess(tomorrow);
      expect(streak.countOn(tomorrow), 1);
    });

    test('failed dictations break it, cancels and silence do not', () {
      expect(reviewStreakBrokenBy('ok'), isFalse);
      expect(reviewStreakBrokenBy('cancelled'), isFalse);
      expect(reviewStreakBrokenBy('empty_transcript'), isFalse);
      expect(reviewStreakBrokenBy('stt_failed'), isTrue);
      expect(reviewStreakBrokenBy('quick_note_append_failed'), isTrue);
    });
  });

  group('moment', () {
    bool mayOpen({
      bool due = true,
      bool storeRated = false,
      bool streakMet = true,
      bool problemShown = false,
      bool onboardingActive = false,
      bool windowActive = true,
    }) => reviewAskMayOpen(
      due: due,
      storeRated: storeRated,
      streakMet: streakMet,
      problemShown: problemShown,
      onboardingActive: onboardingActive,
      windowActive: windowActive,
    );

    test('opens only when every condition holds', () {
      expect(mayOpen(), isTrue);
      expect(mayOpen(due: false), isFalse);
      expect(mayOpen(streakMet: false), isFalse);
      expect(mayOpen(problemShown: true), isFalse);
      expect(mayOpen(onboardingActive: true), isFalse);
      expect(mayOpen(windowActive: false), isFalse);
    });

    test('never again after a rating in the Microsoft Store', () {
      expect(mayOpen(storeRated: true), isFalse);
    });
  });
}
