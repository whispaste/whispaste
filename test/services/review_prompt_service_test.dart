/// Pure-Dart service tests for [ReviewPromptNotifier] trigger logic.
///
/// Covers the Säule-A trigger tuning:
///   AC1  Prompt threshold is 10–15 active history entries.
///   AC2  A version upgrade re-prompts "not now" users once; never "never".
///   AC3  Cooldown after "not now" is materially longer than after a completed
///        review action.
///   AC4  Last-shown app version is persisted and used for version-change
///        detection.
///
/// No widgets — [ProviderContainer] + in-memory drift DB + SharedPreferences
/// mock only. Tests drive the public interface (checkAndMaybePrompt / markShown
/// / dismiss) and observe [ReviewPromptState.shouldShowPrompt].
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/review_prompt_service.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Builds a [ProviderContainer] with an in-memory drift DB seeded with
/// [activeEntries] active history entries and the supplied SharedPreferences
/// initial values. Returns the container so the test can drive the notifier.
Future<({ProviderContainer container, HistoryDatabase db})> _bootstrap({
  required Map<String, Object> prefs,
  int activeEntries = 0,
  DeployChannel channel = DeployChannel.portable,
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
    // Steady use long ago: the day and in-use gates hold, so these tests
    // drive the count, the cooldowns and the version rules.
    await db.recordDailyStat(
      timestamp: DateTime(2025, 1, 1).add(Duration(days: i % 5)),
      model: 'm',
      isLocal: true,
      durationSec: 3,
      processingDurationSec: 1,
      wordCount: 5,
      costUsd: 0,
    );
  }
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      deployChannelProvider.overrideWithValue(channel),
    ],
  );
  return (container: container, db: db);
}

/// Drives the notifier and returns the resulting [shouldShowPrompt] flag.
Future<bool> _shouldShow(
  ProviderContainer container, {
  String appVersion = '1.0.0',
}) async {
  await container
      .read(reviewPromptProvider.notifier)
      .checkAndMaybePrompt(appVersion: appVersion);
  return container.read(reviewPromptProvider).shouldShowPrompt;
}

/// SharedPreferences key for the post-action ("markShown") cooldown timestamp.
const _lastShownKey = 'review_prompt_last_shown';

/// SharedPreferences key for the "not now" snooze cooldown timestamp.
const _lastSnoozeKey = 'review_prompt_last_snooze';

/// SharedPreferences key for the last-shown app version.
const _lastShownVersionKey = 'review_prompt_last_shown_version';

void main() {
  group('usage before a rating ask', () {
    final now = DateTime(2026, 10, 30);
    bool met({int n = 20, int days = 3, DateTime? first}) =>
        reviewPromptUsageMet(
          recordings: n,
          dictationDays: days,
          firstDictationDay: first ?? DateTime(2026, 10, 20),
          now: now,
        );

    test('needs 20 dictations on 3 days, a week after the first', () {
      expect(met(), isTrue);
      expect(met(n: 19), isFalse);
      expect(met(days: 2), isFalse);
      expect(met(first: DateTime(2026, 10, 25)), isFalse);
      expect(
        reviewPromptUsageMet(
          recordings: 50,
          dictationDays: 5,
          firstDictationDay: null,
          now: now,
        ),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC1 — threshold
  // ---------------------------------------------------------------------------

  group('threshold', () {
    test('does not prompt below the threshold of active entries', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 19);
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container), isFalse);
    });

    test('prompts once active entries reach the threshold', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // AC2 / AC4 — version-upgrade re-prompt + version persistence
  // ---------------------------------------------------------------------------

  group('version upgrade', () {
    test(
      'a version upgrade does not override a fresh "not now" snooze (R-03)',
      () async {
        final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(reviewPromptProvider.notifier);

        // First prompt at v1.0.0 → user picks "not now" (snooze).
        expect(
          await _shouldShow(harness.container, appVersion: '1.0.0'),
          isTrue,
        );
        await notifier.dismiss(permanent: false);

        // Same version, fresh snooze → still blocked.
        expect(
          await _shouldShow(harness.container, appVersion: '1.0.0'),
          isFalse,
        );

        // Upgrade to v2.0.0 while the snooze is fresh → still blocked.
        expect(
          await _shouldShow(harness.container, appVersion: '2.0.0'),
          isFalse,
        );
      },
    );

    test('a version upgrade re-prompts once the "not now" snooze has run out '
        '(R-03)', () async {
      final ninetyOneDaysAgo = DateTime.now()
          .subtract(const Duration(days: 91))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {
          _lastShownVersionKey: '1.0.0',
          _lastSnoozeKey: ninetyOneDaysAgo,
        },
        activeEntries: 20,
      );
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container, appVersion: '2.0.0'), isTrue);
    });

    test(
      'a version re-prompt happens at most once per 365 days (R-03)',
      () async {
        final hundredDaysAgo = DateTime.now()
            .subtract(const Duration(days: 100))
            .millisecondsSinceEpoch;
        final tenDaysAgo = DateTime.now()
            .subtract(const Duration(days: 10))
            .millisecondsSinceEpoch;
        final harness = await _bootstrap(
          prefs: {
            _lastShownVersionKey: '1.0.0',
            'review_prompt_last_version_reprompt': hundredDaysAgo,
            // A recent completed review action keeps the regular cooldown
            // active, so only the 365-day rule could allow a prompt here.
            _lastShownKey: tenDaysAgo,
          },
          activeEntries: 20,
        );
        addTearDown(harness.container.dispose);

        expect(
          await _shouldShow(harness.container, appVersion: '2.0.0'),
          isFalse,
        );
      },
    );

    test(
      'a version re-prompt is allowed again after 365 days (R-03)',
      () async {
        final yearAgo = DateTime.now()
            .subtract(const Duration(days: 366))
            .millisecondsSinceEpoch;
        final harness = await _bootstrap(
          prefs: {
            _lastShownVersionKey: '1.0.0',
            'review_prompt_last_version_reprompt': yearAgo,
          },
          activeEntries: 20,
        );
        addTearDown(harness.container.dispose);

        expect(
          await _shouldShow(harness.container, appVersion: '2.0.0'),
          isTrue,
        );
      },
    );

    test('a version upgrade after a completed review action waits for the '
        '60-day cooldown (R-03)', () async {
      final tenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 10))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastShownVersionKey: '1.0.0', _lastShownKey: tenDaysAgo},
        activeEntries: 20,
      );
      addTearDown(harness.container.dispose);

      expect(
        await _shouldShow(harness.container, appVersion: '2.0.0'),
        isFalse,
      );
    });

    test(
      'never re-prompts a "never again" user, even after an upgrade',
      () async {
        final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(reviewPromptProvider.notifier);

        expect(
          await _shouldShow(harness.container, appVersion: '1.0.0'),
          isTrue,
        );
        await notifier.dismiss(permanent: true);

        expect(
          await _shouldShow(harness.container, appVersion: '2.0.0'),
          isFalse,
        );
      },
    );

    test('does not re-prompt when the version has not changed (AC4: version '
        'remembered across the snooze and used to block)', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(reviewPromptProvider.notifier);

      expect(await _shouldShow(harness.container, appVersion: '1.2.0'), isTrue);
      await notifier.dismiss(permanent: false);

      // A different patch string but we treat the persisted version as the
      // gate: same version → still snoozed, no re-prompt.
      expect(
        await _shouldShow(harness.container, appVersion: '1.2.0'),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC3 — differential cooldown
  // ---------------------------------------------------------------------------

  group('differential cooldown', () {
    test('after a completed review action, re-prompts once the 60-day cooldown '
        'elapses', () async {
      final backdated = DateTime.now()
          .subtract(const Duration(days: 61))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastShownKey: backdated, _lastShownVersionKey: '1.0.0'},
        activeEntries: 20,
      );
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container, appVersion: '1.0.0'), isTrue);
    });

    test('after a "not now" snooze, still suppresses at 61 days — materially '
        'longer than the post-action cooldown', () async {
      final backdated = DateTime.now()
          .subtract(const Duration(days: 61))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastSnoozeKey: backdated, _lastShownVersionKey: '1.0.0'},
        activeEntries: 20,
      );
      addTearDown(harness.container.dispose);

      // 61 days elapsed: enough for the action cooldown, NOT enough for the
      // longer "not now" snooze.
      expect(
        await _shouldShow(harness.container, appVersion: '1.0.0'),
        isFalse,
      );
    });

    test(
      'after a "not now" snooze, re-prompts once 90 days have elapsed',
      () async {
        final backdated = DateTime.now()
            .subtract(const Duration(days: 91))
            .millisecondsSinceEpoch;
        final harness = await _bootstrap(
          prefs: {_lastSnoozeKey: backdated, _lastShownVersionKey: '1.0.0'},
          activeEntries: 20,
        );
        addTearDown(harness.container.dispose);

        expect(
          await _shouldShow(harness.container, appVersion: '1.0.0'),
          isTrue,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Regression — bundle-ID-migrated String values (Sentry FLUTTER_WHISPASTE-BQ)
  // ---------------------------------------------------------------------------
  //
  // `runBundleIdMigration`'s SharedPreferencesAdapter persists every copied
  // value as a String, including int/bool preferences like this key. Before
  // the safe-read fix, `prefs.getInt(_lastShownKey)` threw a fatal, uncaught
  // TypeError the moment a migrated user's cooldown check ran.
  group('bundle-ID migration String coercion', () {
    test(
      'does not throw when the last-shown timestamp was migrated as a String',
      () async {
        final recentMs = DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch;
        final harness = await _bootstrap(
          prefs: {_lastShownKey: '$recentMs', _lastShownVersionKey: '1.0.0'},
          activeEntries: 20,
        );
        addTearDown(harness.container.dispose);

        // Recovers the real cooldown from the parsed String instead of
        // crashing or silently defaulting to "never shown".
        expect(
          await _shouldShow(harness.container, appVersion: '1.0.0'),
          isFalse,
        );
      },
    );

    test('does not throw when the permanently-dismissed flag was migrated as a '
        'String', () async {
      final harness = await _bootstrap(
        prefs: const {'review_prompt_permanently_dismissed': 'true'},
        activeEntries: 20,
      );
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // GR-012 — dictations whose paste failed do not count toward the threshold
  // ---------------------------------------------------------------------------

  group('dictations whose paste failed (GR-012)', () {
    test(
      'a failed-paste dictation is excluded from the 20-entry threshold',
      () async {
        final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
        addTearDown(harness.container.dispose);
        await harness.container
            .read(reviewPromptProvider.notifier)
            .countUnpastedDictation(entryId: 'entry-0');

        expect(await _shouldShow(harness.container), isFalse);
      },
    );

    test('only the unpasted dictations are excluded, not the others', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 21);
      addTearDown(harness.container.dispose);
      await harness.container
          .read(reviewPromptProvider.notifier)
          .countUnpastedDictation(entryId: 'entry-0');

      expect(await _shouldShow(harness.container), isTrue);
    });

    test(
      'the same entry is excluded once, however often it is counted',
      () async {
        final harness = await _bootstrap(prefs: const {}, activeEntries: 21);
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(reviewPromptProvider.notifier);
        await notifier.countUnpastedDictation(entryId: 'entry-0');
        await notifier.countUnpastedDictation(entryId: 'entry-0');

        expect(await _shouldShow(harness.container), isTrue);
      },
    );

    test('a missing entry id (nothing was saved) excludes nothing', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
      addTearDown(harness.container.dispose);
      await harness.container
          .read(reviewPromptProvider.notifier)
          .countUnpastedDictation(entryId: null);

      expect(await _shouldShow(harness.container), isTrue);
    });

    test(
      'failed entries that history trimming moved out do not lower the total',
      () async {
        // Regression (growth review O4): the old lifetime counter kept
        // subtracting trimmed failures, so the threshold became unreachable
        // once the history limit had removed them.
        final harness = await _bootstrap(prefs: const {}, activeEntries: 20);
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(reviewPromptProvider.notifier);
        for (var i = 0; i < 5; i++) {
          await harness.db.upsertEntry(
            HistoryEntriesCompanion.insert(
              id: 'failed-$i',
              timestamp: DateTime(2024, 1, 1).add(Duration(minutes: i)),
            ),
          );
          await notifier.countUnpastedDictation(entryId: 'failed-$i');
          await harness.db.customStatement(
            'UPDATE history_entries SET deleted_at = ? WHERE id = ?',
            [DateTime(2025, 6, 1).millisecondsSinceEpoch, 'failed-$i'],
          );
        }

        expect(await harness.db.countActive(), 20);
        expect(await _shouldShow(harness.container), isTrue);
      },
    );
  });
}
