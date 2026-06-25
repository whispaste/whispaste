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
      're-prompts a snoozed "not now" user after a version upgrade',
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

        // Upgrade to v2.0.0 → prompt re-activates once.
        expect(
          await _shouldShow(harness.container, appVersion: '2.0.0'),
          isTrue,
        );
      },
    );

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
}
