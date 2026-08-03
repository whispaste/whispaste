/// Pure-Dart service tests for [shouldShowStoreThankYou] gating logic and
/// [StoreThankYouNotifier] state transitions / SharedPreferences persistence.
///
/// No widgets — [ProviderContainer] + in-memory drift DB + SharedPreferences
/// mock only.
///
/// Covers:
///   AC1  Hint renders ONLY for [DeployChannel.store] + unset flag + enough
///        real recordings (Guideline 5.6.3 — never on first launch/onboarding).
///   AC2  All other channels (installer/portable) never show the hint.
///   AC3  Flag unset + onboarding incomplete → no-op.
///   AC4  After [markShown]: flag persisted → subsequent check is a no-op.
///   AC5  Below the recording threshold → no-op regardless of channel/flag.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/store_thank_you_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Recording count comfortably above the gate's threshold, used by tests
/// that don't care about the exact boundary.
const _aboveThreshold = 20;

Future<({ProviderContainer container, HistoryDatabase db})> _makeContainer({
  required DeployChannel channel,
  Map<String, Object> prefs = const {},
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
      deployChannelProvider.overrideWithValue(channel),
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
    ],
  );
  return (container: container, db: db);
}

// ---------------------------------------------------------------------------
// shouldShowStoreThankYou — pure gating predicate
// ---------------------------------------------------------------------------

void main() {
  group('shouldShowStoreThankYou — gating predicate', () {
    test('store + flag unset + enough recordings → true', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.store,
          flagAlreadySet: false,
          recordingCount: _aboveThreshold,
        ),
        isTrue,
      );
    });

    test('store + flag set → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.store,
          flagAlreadySet: true,
          recordingCount: _aboveThreshold,
        ),
        isFalse,
      );
    });

    test('store + flag unset + below recording threshold → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.store,
          flagAlreadySet: false,
          recordingCount: 0,
        ),
        isFalse,
      );
    });

    test('installer + flag unset → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.installer,
          flagAlreadySet: false,
          recordingCount: _aboveThreshold,
        ),
        isFalse,
      );
    });

    test('portable + flag unset → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.portable,
          flagAlreadySet: false,
          recordingCount: _aboveThreshold,
        ),
        isFalse,
      );
    });

    test('installer + flag set → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.installer,
          flagAlreadySet: true,
          recordingCount: _aboveThreshold,
        ),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // StoreThankYouNotifier — state transitions
  // ---------------------------------------------------------------------------

  group('StoreThankYouNotifier — checkAndMaybeShow', () {
    test('store channel + unset flag + onboarding done + enough recordings '
        '→ shouldShow = true', () async {
      final harness = await _makeContainer(
        channel: DeployChannel.store,
        activeEntries: _aboveThreshold,
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(harness.container.read(storeThankYouProvider).shouldShow, isTrue);
    });

    test(
      'onboarding done but below recording threshold → shouldShow stays false '
      '(Guideline 5.6.3 — never on first launch/onboarding)',
      () async {
        final harness = await _makeContainer(channel: DeployChannel.store);
        addTearDown(harness.container.dispose);

        await harness.container
            .read(storeThankYouProvider.notifier)
            .checkAndMaybeShow(onboardingCompleted: true);

        expect(
          harness.container.read(storeThankYouProvider).shouldShow,
          isFalse,
        );
      },
    );

    test('onboarding not completed → shouldShow stays false', () async {
      final harness = await _makeContainer(
        channel: DeployChannel.store,
        activeEntries: _aboveThreshold,
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: false);

      expect(harness.container.read(storeThankYouProvider).shouldShow, isFalse);
    });

    test('installer channel → shouldShow stays false', () async {
      final harness = await _makeContainer(
        channel: DeployChannel.installer,
        activeEntries: _aboveThreshold,
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(harness.container.read(storeThankYouProvider).shouldShow, isFalse);
    });

    test('portable channel → shouldShow stays false', () async {
      final harness = await _makeContainer(
        channel: DeployChannel.portable,
        activeEntries: _aboveThreshold,
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(harness.container.read(storeThankYouProvider).shouldShow, isFalse);
    });

    test('flag already set in prefs → shouldShow stays false', () async {
      final harness = await _makeContainer(
        channel: DeployChannel.store,
        prefs: const {'store_thank_you_shown': true},
        activeEntries: _aboveThreshold,
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(harness.container.read(storeThankYouProvider).shouldShow, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // StoreThankYouNotifier — markShown + no-repeat guarantee
  // ---------------------------------------------------------------------------

  group('StoreThankYouNotifier — markShown persistence', () {
    test(
      'markShown resets shouldShow and persists flag; subsequent check is no-op',
      () async {
        final harness = await _makeContainer(
          channel: DeployChannel.store,
          activeEntries: _aboveThreshold,
        );
        addTearDown(harness.container.dispose);

        // Show once.
        await harness.container
            .read(storeThankYouProvider.notifier)
            .checkAndMaybeShow(onboardingCompleted: true);
        expect(
          harness.container.read(storeThankYouProvider).shouldShow,
          isTrue,
        );

        // Dismiss — persists flag, resets state.
        await harness.container
            .read(storeThankYouProvider.notifier)
            .markShown();
        expect(
          harness.container.read(storeThankYouProvider).shouldShow,
          isFalse,
        );

        // Subsequent check must be a no-op (flag now persisted in prefs).
        await harness.container
            .read(storeThankYouProvider.notifier)
            .checkAndMaybeShow(onboardingCompleted: true);
        expect(
          harness.container.read(storeThankYouProvider).shouldShow,
          isFalse,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('store_thank_you_shown'), isTrue);
      },
    );

    test('markShown is idempotent — second call does not throw', () async {
      final harness = await _makeContainer(channel: DeployChannel.store);
      addTearDown(harness.container.dispose);

      await harness.container.read(storeThankYouProvider.notifier).markShown();
      await harness.container.read(storeThankYouProvider.notifier).markShown();

      expect(harness.container.read(storeThankYouProvider).shouldShow, isFalse);
    });
  });
}
