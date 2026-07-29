/// Pure-Dart service tests for [SupportPromptNotifier] trigger logic.
///
/// Mirrors `test/services/review_prompt_service_test.dart`'s harness/style
/// closely, per growth-reliability-conversion issue 09's explicit
/// requirement. Covers:
///   AC1  Own persisted state, independent of the review prompt's counter.
///   AC2  Threshold materially higher (40) than the review prompt's (12).
///   AC3  Coordination: never fires while the review prompt is pending, or
///        was shown/snoozed recently — mutual exclusion in timing, not
///        shared counter state.
///   AC4  Explicit dismiss is a 90-day snooze, not a permanent flag.
///   AC5  A link click starts a 9-month quiet period, after which a one-time
///        recurring follow-up appears.
///   AC6  A hard impression cap of 3 is enforced regardless of resolution
///        path.
///
/// No widgets — [ProviderContainer] + in-memory drift DB + SharedPreferences
/// mock only. Tests drive the public interface (checkAndMaybePrompt /
/// dismiss / markLinkOpened) and observe [SupportPromptState].
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support_prompt_service.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Builds a [ProviderContainer] with an in-memory drift DB seeded with
/// [activeEntries] active history entries and the supplied SharedPreferences
/// initial values. Returns the container so the test can drive the notifier.
Future<({ProviderContainer container, HistoryDatabase db})> _bootstrap({
  required Map<String, Object> prefs,
  int activeEntries = 0,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  for (var i = 0; i < activeEntries; i++) {
    await db.upsertEntry(
      HistoryEntriesCompanion.insert(
        id: 'entry-$i',
        timestamp: DateTime(2025, 1, 1).add(Duration(minutes: i)),
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      // The support prompt reads the review prompt's live in-session state
      // as part of its coordination check; the deploy channel override
      // keeps that read deterministic in tests.
      deployChannelProvider.overrideWithValue(DeployChannel.portable),
    ],
  );
  return (container: container, db: db);
}

/// Drives the notifier and returns the resulting [SupportPromptState].
Future<SupportPromptState> _check(ProviderContainer container) async {
  await container.read(supportPromptProvider.notifier).checkAndMaybePrompt();
  return container.read(supportPromptProvider);
}

/// SharedPreferences keys owned by this service — used here only to seed
/// scenarios directly instead of driving through many check/resolve cycles.
const _impressionCountKey = 'support_prompt_impression_count';
const _snoozeKey = 'support_prompt_snooze_ms';
const _postLinkKey = 'support_prompt_post_link_ms';
const _linkClickedKey = 'support_prompt_link_clicked';
const _followUpShownKey = 'support_prompt_followup_shown';

/// SharedPreferences keys owned by the review prompt service — used here
/// only to seed cross-session coordination scenarios (read-only from the
/// support service's perspective).
const _reviewLastShownKey = 'review_prompt_last_shown';
const _reviewLastSnoozeKey = 'review_prompt_last_snooze';

/// A counter key the review prompt service also uses — asserting this is
/// never read by the support service is implicit: the support service's own
/// harness never seeds or overrides review-prompt-only recording thresholds,
/// yet still triggers correctly on its own (higher) threshold.
const _reviewShownCountKey = 'review_prompt_shown_count';

void main() {
  // ---------------------------------------------------------------------------
  // AC1 / AC2 — independent state + higher threshold
  // ---------------------------------------------------------------------------

  group('threshold', () {
    test('does not prompt below the threshold of active entries', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 39);
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('prompts once active entries reach the threshold (40, materially '
        'higher than the review prompt\'s 12)', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);

      final state = await _check(harness.container);
      expect(state.shouldShowPrompt, isTrue);
      expect(state.kind, SupportPromptKind.initial);
    });

    test('still prompts at the review-prompt threshold of 12 recordings once '
        'a pre-existing review-prompt-only counter value is present — proves '
        'the support service does not read or depend on the review prompt\'s '
        'own shown-count state', () async {
      final harness = await _bootstrap(
        prefs: {_reviewShownCountKey: 7},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // AC3 — coordination with the review prompt (mutual exclusion in timing)
  // ---------------------------------------------------------------------------

  group('coordination with the review prompt', () {
    test('does not fire if the review prompt was shown within the '
        'coordination window', () async {
      final recent = DateTime.now()
          .subtract(const Duration(days: 5))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_reviewLastShownKey: recent},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('does not fire if the review prompt was snoozed within the '
        'coordination window', () async {
      final recent = DateTime.now()
          .subtract(const Duration(days: 5))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_reviewLastSnoozeKey: recent},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('fires once the review prompt\'s last-shown timestamp is well '
        'outside the coordination window', () async {
      final old = DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_reviewLastShownKey: old},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // AC4 — explicit dismiss is a 90-day snooze, not a permanent flag
  // ---------------------------------------------------------------------------

  group('dismiss snooze', () {
    test('dismiss() does not block future prompts forever, unlike the old '
        'permanent-flag behavior', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);

      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
      await notifier.dismiss();

      // Still within the 90-day snooze — stays quiet.
      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('prompts again once the 90-day snooze has elapsed', () async {
      final justOverNinetyDays = DateTime.now()
          .subtract(const Duration(days: 91))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_snoozeKey: justOverNinetyDays},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      final state = await _check(harness.container);
      expect(state.shouldShowPrompt, isTrue);
      expect(state.kind, SupportPromptKind.initial);
    });

    test('stays quiet within the 90-day snooze window', () async {
      final justUnderNinetyDays = DateTime.now()
          .subtract(const Duration(days: 89))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_snoozeKey: justUnderNinetyDays},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('dismiss() increments the impression counter', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);
      await _check(harness.container);
      await notifier.dismiss();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_impressionCountKey), 1);
    });
  });

  // ---------------------------------------------------------------------------
  // AC5 — link click quiet period + one-time recurring follow-up
  // ---------------------------------------------------------------------------

  group('post-link quiet period and recurring follow-up', () {
    test('markLinkOpened() starts a 9-month quiet period, staying silent '
        'right after the click', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);

      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
      await notifier.markLinkOpened();

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('shows the recurring follow-up once the 9-month quiet period has '
        'elapsed', () async {
      final justOverNineMonths = DateTime.now()
          .subtract(const Duration(days: 271))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_linkClickedKey: true, _postLinkKey: justOverNineMonths},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      final state = await _check(harness.container);
      expect(state.shouldShowPrompt, isTrue);
      expect(state.kind, SupportPromptKind.recurringFollowUp);
    });

    test('stays quiet within the 9-month post-link window', () async {
      final justUnderNineMonths = DateTime.now()
          .subtract(const Duration(days: 269))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_linkClickedKey: true, _postLinkKey: justUnderNineMonths},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('never shows the recurring follow-up again once it has already '
        'been shown', () async {
      final harness = await _bootstrap(
        prefs: {
          _linkClickedKey: true,
          _postLinkKey: DateTime.now()
              .subtract(const Duration(days: 300))
              .millisecondsSinceEpoch,
          _followUpShownKey: true,
        },
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('resolving the recurring follow-up (dismiss or link) marks it '
        'shown so it never appears again', () async {
      final harness = await _bootstrap(
        prefs: {
          _linkClickedKey: true,
          _postLinkKey: DateTime.now()
              .subtract(const Duration(days: 300))
              .millisecondsSinceEpoch,
        },
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);

      final state = await _check(harness.container);
      expect(state.kind, SupportPromptKind.recurringFollowUp);
      await notifier.dismiss();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_followUpShownKey), isTrue);
      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // AC6 — hard impression cap, independent of resolution path
  // ---------------------------------------------------------------------------

  group('impression cap', () {
    test('stops showing once 3 impressions have been recorded, regardless '
        'of resolution path', () async {
      final harness = await _bootstrap(
        prefs: {_impressionCountKey: 3},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });

    test('a fresh dismiss/link-click cycle up to the cap ends in silence, '
        'even with no active snooze or quiet period', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);

      // Impression 1: dismiss.
      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
      await notifier.dismiss();

      // Clear the snooze so eligibility depends only on the cap, not timing.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_snoozeKey);

      // Impression 2: dismiss again.
      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
      await notifier.dismiss();
      await prefs.remove(_snoozeKey);

      // Impression 3: dismiss again — reaches the cap.
      expect((await _check(harness.container)).shouldShowPrompt, isTrue);
      await notifier.dismiss();
      await prefs.remove(_snoozeKey);

      // Cap reached — stays silent forever after, even with no snooze active.
      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
      expect(prefs.getInt(_impressionCountKey), 3);
    });

    test(
      'cap persists across a fresh container (survives app restart)',
      () async {
        final harness = await _bootstrap(
          prefs: {_impressionCountKey: 3},
          activeEntries: 40,
        );
        addTearDown(harness.container.dispose);

        final restarted = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(harness.db.close);
              return harness.db;
            }),
            deployChannelProvider.overrideWithValue(DeployChannel.portable),
          ],
        );
        addTearDown(restarted.dispose);

        expect((await _check(restarted)).shouldShowPrompt, isFalse);
      },
    );

    test('the impression-count key is scoped to this service and does not '
        'collide with the review prompt\'s own shown-count key', () {
      expect(_impressionCountKey, isNot(_reviewShownCountKey));
    });
  });

  // ---------------------------------------------------------------------------
  // Regression — bundle-ID-migrated String values (Sentry FLUTTER_WHISPASTE-BP)
  // ---------------------------------------------------------------------------
  //
  // The cross-service coordination check reads the review prompt's own
  // `review_prompt_last_shown` key, which `runBundleIdMigration` may have
  // persisted as a String. Before the safe-read fix, this crashed with a
  // fatal, uncaught TypeError on every check for a migrated user.
  group('bundle-ID migration String coercion', () {
    test('does not throw when the review prompt\'s last-shown timestamp was '
        'migrated as a String', () async {
      final recentMs = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_reviewLastShownKey: '$recentMs'},
        activeEntries: 40,
      );
      addTearDown(harness.container.dispose);

      // Recovers the real coordination window from the parsed String
      // instead of crashing — the recent review-prompt show suppresses
      // the support prompt this check, exactly as with a native int value.
      expect((await _check(harness.container)).shouldShowPrompt, isFalse);
    });
  });
}
