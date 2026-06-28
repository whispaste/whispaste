/// Pure-Dart service tests for [shouldShowStoreThankYou] gating logic and
/// [StoreThankYouNotifier] state transitions / SharedPreferences persistence.
///
/// No widgets — [ProviderContainer] + SharedPreferences mock only.
///
/// Covers:
///   AC1  Hint renders ONLY for [DeployChannel.store] + unset flag.
///   AC2  All other channels (installer/portable) never show the hint.
///   AC3  Flag unset + onboarding incomplete → no-op.
///   AC4  After [markShown]: flag persisted → subsequent check is a no-op.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/store_thank_you_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required DeployChannel channel,
  Map<String, Object> prefs = const {},
}) {
  SharedPreferences.setMockInitialValues(prefs);
  return ProviderContainer(
    overrides: [deployChannelProvider.overrideWithValue(channel)],
  );
}

// ---------------------------------------------------------------------------
// shouldShowStoreThankYou — pure gating predicate
// ---------------------------------------------------------------------------

void main() {
  group('shouldShowStoreThankYou — gating predicate', () {
    test('store + flag unset → true', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.store,
          flagAlreadySet: false,
        ),
        isTrue,
      );
    });

    test('store + flag set → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.store,
          flagAlreadySet: true,
        ),
        isFalse,
      );
    });

    test('installer + flag unset → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.installer,
          flagAlreadySet: false,
        ),
        isFalse,
      );
    });

    test('portable + flag unset → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.portable,
          flagAlreadySet: false,
        ),
        isFalse,
      );
    });

    test('installer + flag set → false', () {
      expect(
        shouldShowStoreThankYou(
          channel: DeployChannel.installer,
          flagAlreadySet: true,
        ),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // StoreThankYouNotifier — state transitions
  // ---------------------------------------------------------------------------

  group('StoreThankYouNotifier — checkAndMaybeShow', () {
    test(
      'store channel + unset flag + onboarding done → shouldShow = true',
      () async {
        final container = _makeContainer(channel: DeployChannel.store);
        addTearDown(container.dispose);

        await container
            .read(storeThankYouProvider.notifier)
            .checkAndMaybeShow(onboardingCompleted: true);

        expect(container.read(storeThankYouProvider).shouldShow, isTrue);
      },
    );

    test('onboarding not completed → shouldShow stays false', () async {
      final container = _makeContainer(channel: DeployChannel.store);
      addTearDown(container.dispose);

      await container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: false);

      expect(container.read(storeThankYouProvider).shouldShow, isFalse);
    });

    test('installer channel → shouldShow stays false', () async {
      final container = _makeContainer(channel: DeployChannel.installer);
      addTearDown(container.dispose);

      await container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(container.read(storeThankYouProvider).shouldShow, isFalse);
    });

    test('portable channel → shouldShow stays false', () async {
      final container = _makeContainer(channel: DeployChannel.portable);
      addTearDown(container.dispose);

      await container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(container.read(storeThankYouProvider).shouldShow, isFalse);
    });

    test('flag already set in prefs → shouldShow stays false', () async {
      final container = _makeContainer(
        channel: DeployChannel.store,
        prefs: const {'store_thank_you_shown': true},
      );
      addTearDown(container.dispose);

      await container
          .read(storeThankYouProvider.notifier)
          .checkAndMaybeShow(onboardingCompleted: true);

      expect(container.read(storeThankYouProvider).shouldShow, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // StoreThankYouNotifier — markShown + no-repeat guarantee
  // ---------------------------------------------------------------------------

  group('StoreThankYouNotifier — markShown persistence', () {
    test(
      'markShown resets shouldShow and persists flag; subsequent check is no-op',
      () async {
        final container = _makeContainer(channel: DeployChannel.store);
        addTearDown(container.dispose);

        // Show once.
        await container
            .read(storeThankYouProvider.notifier)
            .checkAndMaybeShow(onboardingCompleted: true);
        expect(container.read(storeThankYouProvider).shouldShow, isTrue);

        // Dismiss — persists flag, resets state.
        await container.read(storeThankYouProvider.notifier).markShown();
        expect(container.read(storeThankYouProvider).shouldShow, isFalse);

        // Subsequent check must be a no-op (flag now persisted in prefs).
        await container
            .read(storeThankYouProvider.notifier)
            .checkAndMaybeShow(onboardingCompleted: true);
        expect(container.read(storeThankYouProvider).shouldShow, isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('store_thank_you_shown'), isTrue);
      },
    );

    test('markShown is idempotent — second call does not throw', () async {
      final container = _makeContainer(channel: DeployChannel.store);
      addTearDown(container.dispose);

      await container.read(storeThankYouProvider.notifier).markShown();
      await container.read(storeThankYouProvider.notifier).markShown();

      expect(container.read(storeThankYouProvider).shouldShow, isFalse);
    });
  });
}
