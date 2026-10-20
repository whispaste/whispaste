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
  // ---------------------------------------------------------------------------
  // AC1 — threshold
  // ---------------------------------------------------------------------------

  group('threshold', () {
    test('does not prompt below the threshold of active entries', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 11);
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container), isFalse);
    });

    test('prompts once active entries reach the threshold', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
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
        final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
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
      final sixtyOneDaysAgo = DateTime.now()
          .subtract(const Duration(days: 61))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastShownVersionKey: '1.0.0', _lastSnoozeKey: sixtyOneDaysAgo},
        activeEntries: 12,
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
          activeEntries: 12,
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
          activeEntries: 12,
        );
        addTearDown(harness.container.dispose);

        expect(
          await _shouldShow(harness.container, appVersion: '2.0.0'),
          isTrue,
        );
      },
    );

    test('a version upgrade after a completed review action waits for the '
        '30-day cooldown (R-03)', () async {
      final tenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 10))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastShownVersionKey: '1.0.0', _lastShownKey: tenDaysAgo},
        activeEntries: 12,
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
        final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
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
      final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
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
    test('after a completed review action, re-prompts once the 30-day cooldown '
        'elapses', () async {
      final backdated = DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastShownKey: backdated, _lastShownVersionKey: '1.0.0'},
        activeEntries: 12,
      );
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container, appVersion: '1.0.0'), isTrue);
    });

    test('after a "not now" snooze, still suppresses at 31 days — materially '
        'longer than the post-action cooldown', () async {
      final backdated = DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch;
      final harness = await _bootstrap(
        prefs: {_lastSnoozeKey: backdated, _lastShownVersionKey: '1.0.0'},
        activeEntries: 12,
      );
      addTearDown(harness.container.dispose);

      // 31 days elapsed: enough for the action cooldown, NOT enough for the
      // longer "not now" snooze.
      expect(
        await _shouldShow(harness.container, appVersion: '1.0.0'),
        isFalse,
      );
    });

    test(
      'after a "not now" snooze, re-prompts once 60 days have elapsed',
      () async {
        final backdated = DateTime.now()
            .subtract(const Duration(days: 61))
            .millisecondsSinceEpoch;
        final harness = await _bootstrap(
          prefs: {_lastSnoozeKey: backdated, _lastShownVersionKey: '1.0.0'},
          activeEntries: 12,
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
          activeEntries: 12,
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
        activeEntries: 12,
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
      'a failed-paste dictation is excluded from the 12-entry threshold',
      () async {
        final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
        addTearDown(harness.container.dispose);
        await harness.container
            .read(reviewPromptProvider.notifier)
            .countUnpastedDictation(entryId: 'entry-0');

        expect(await _shouldShow(harness.container), isFalse);
      },
    );

    test('only the unpasted dictations are excluded, not the others', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 13);
      addTearDown(harness.container.dispose);
      await harness.container
          .read(reviewPromptProvider.notifier)
          .countUnpastedDictation(entryId: 'entry-0');

      expect(await _shouldShow(harness.container), isTrue);
    });

    test(
      'the same entry is excluded once, however often it is counted',
      () async {
        final harness = await _bootstrap(prefs: const {}, activeEntries: 13);
        addTearDown(harness.container.dispose);
        final notifier = harness.container.read(reviewPromptProvider.notifier);
        await notifier.countUnpastedDictation(entryId: 'entry-0');
        await notifier.countUnpastedDictation(entryId: 'entry-0');

        expect(await _shouldShow(harness.container), isTrue);
      },
    );

    test('a missing entry id (nothing was saved) excludes nothing', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
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
        final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
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

        expect(await harness.db.countActive(), 12);
        expect(await _shouldShow(harness.container), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // GR-009 — at most 3 native store requests per 365 days
  // ---------------------------------------------------------------------------

  group('native store request cap (GR-009)', () {
    String daysAgoMs(int days) => DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch
        .toString();

    test('a first native request is allowed', () async {
      final harness = await _bootstrap(prefs: const {});
      addTearDown(harness.container.dispose);

      expect(
        await harness.container
            .read(reviewPromptProvider.notifier)
            .nativeRequestAllowed(),
        isTrue,
      );
    });

    test('the third request within 365 days is still allowed', () async {
      final harness = await _bootstrap(
        prefs: {
          _nativeRequestsKey: [daysAgoMs(40), daysAgoMs(100)],
        },
      );
      addTearDown(harness.container.dispose);

      expect(
        await harness.container
            .read(reviewPromptProvider.notifier)
            .nativeRequestAllowed(),
        isTrue,
      );
    });

    test('a fourth request within 365 days is blocked', () async {
      final harness = await _bootstrap(
        prefs: {
          _nativeRequestsKey: [daysAgoMs(40), daysAgoMs(100), daysAgoMs(200)],
        },
      );
      addTearDown(harness.container.dispose);

      expect(
        await harness.container
            .read(reviewPromptProvider.notifier)
            .nativeRequestAllowed(),
        isFalse,
      );
    });

    test('a request older than 365 days no longer counts', () async {
      final harness = await _bootstrap(
        prefs: {
          _nativeRequestsKey: [daysAgoMs(370), daysAgoMs(100), daysAgoMs(40)],
        },
      );
      addTearDown(harness.container.dispose);

      expect(
        await harness.container
            .read(reviewPromptProvider.notifier)
            .nativeRequestAllowed(),
        isTrue,
      );
    });

    test('markNativeRequested records the request and keeps the 30-day '
        'cooldown', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 12);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(reviewPromptProvider.notifier);

      await notifier.markNativeRequested();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_nativeRequestsKey), hasLength(1));
      expect(await _shouldShow(harness.container), isFalse);
    });

    test('only the last three request times are kept', () async {
      final harness = await _bootstrap(
        prefs: {
          _nativeRequestsKey: [daysAgoMs(300), daysAgoMs(200), daysAgoMs(100)],
        },
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(reviewPromptProvider.notifier)
          .markNativeRequested();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_nativeRequestsKey), hasLength(3));
    });
  });
}

/// SharedPreferences key for the native store request times (GR-009).
const _nativeRequestsKey = 'review_prompt_native_request_ms';
