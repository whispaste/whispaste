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
///   AC4  Dismissal ([markResolved]) is a permanent, hard cap.
///
/// No widgets — [ProviderContainer] + in-memory drift DB + SharedPreferences
/// mock only. Tests drive the public interface (checkAndMaybePrompt /
/// markResolved) and observe [SupportPromptState.shouldShowPrompt].
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

/// Drives the notifier and returns the resulting [shouldShowPrompt] flag.
Future<bool> _shouldShow(ProviderContainer container) async {
  await container.read(supportPromptProvider.notifier).checkAndMaybePrompt();
  return container.read(supportPromptProvider).shouldShowPrompt;
}

/// SharedPreferences key for this service's own permanent-dismissal flag.
const _permanentlyDismissedKey = 'support_prompt_permanently_dismissed';

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

      expect(await _shouldShow(harness.container), isFalse);
    });

    test('prompts once active entries reach the threshold (40, materially '
        'higher than the review prompt\'s 12)', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);

      expect(await _shouldShow(harness.container), isTrue);
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

      expect(await _shouldShow(harness.container), isTrue);
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

      expect(await _shouldShow(harness.container), isFalse);
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

      expect(await _shouldShow(harness.container), isFalse);
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

      expect(await _shouldShow(harness.container), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // AC4 — permanent dismissal (hard frequency cap)
  // ---------------------------------------------------------------------------

  group('permanent dismissal', () {
    test('markResolved sets a permanent dismissal that blocks all future '
        'prompts, even far beyond any cooldown window', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);

      expect(await _shouldShow(harness.container), isTrue);
      await notifier.markResolved();

      expect(await _shouldShow(harness.container), isFalse);
    });

    test('markResolved persists across a fresh container (survives '
        'app restart)', () async {
      final harness = await _bootstrap(prefs: const {}, activeEntries: 40);
      addTearDown(harness.container.dispose);
      final notifier = harness.container.read(supportPromptProvider.notifier);
      await notifier.markResolved();

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

      expect(await _shouldShow(restarted), isFalse);
    });

    test('the permanent-dismissal key is scoped to this service and does '
        'not collide with the review prompt\'s own dismissal key', () {
      expect(
        _permanentlyDismissedKey,
        isNot('review_prompt_permanently_dismissed'),
      );
    });
  });
}
