/// Unit tests for [OomRecoveryHandler].
///
/// Decision-table coverage:
///   - TryNextModel: attempts < maxRetries AND next model exists
///   - SwitchToConfiguredCloud: no local fallback, cloud configured
///   - GiveUp: no local fallback, no cloud configured
///   - Retry exhaustion: attempts == maxRetries → falls through to cloud/give-up
///   - reset(): resets counter so subsequent attempts start fresh
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording/oom_recovery_handler.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a handler with a linear fallback chain [chain].
///
/// [currentModelId] is the model at index 0; each subsequent element is the
/// next fallback.  Passing an empty [chain] means no fallback is available.
///
/// [hasCloud] controls whether the cloud-configured callback returns true.
OomRecoveryHandler _makeHandler({
  required List<String> chain,
  bool hasCloud = false,
  int maxRetries = 3,
}) {
  return OomRecoveryHandler(
    maxRetries: maxRetries,
    nextModelIdForCurrent: (id) {
      final idx = chain.indexOf(id);
      if (idx == -1 || idx + 1 >= chain.length) return null;
      return chain[idx + 1];
    },
    hasCloudConfigured: () => hasCloud,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OomRecoveryHandler', () {
    // ── TryNextModel decisions ───────────────────────────────────────────────

    group('TryNextModel', () {
      test('first OOM on model with a lighter fallback → TryNextModel', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium', 'whisper-small'],
        );

        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-large-v3-turbo',
        );

        expect(decision, isA<TryNextModel>());
        expect((decision as TryNextModel).nextModelId, 'whisper-medium');
      });

      test(
        'second OOM on intermediate model → TryNextModel with next in chain',
        () {
          final handler = _makeHandler(
            chain: [
              'whisper-large-v3-turbo',
              'whisper-medium',
              'whisper-small',
            ],
          );

          // First OOM: large-turbo → medium
          handler.attemptRecovery(currentModelId: 'whisper-large-v3-turbo');
          // Second OOM: medium → small
          final decision = handler.attemptRecovery(
            currentModelId: 'whisper-medium',
          );

          expect(decision, isA<TryNextModel>());
          expect((decision as TryNextModel).nextModelId, 'whisper-small');
        },
      );

      test('attempt count increments for each TryNextModel decision', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium', 'whisper-small'],
        );

        expect(handler.attemptCount, 0);
        handler.attemptRecovery(currentModelId: 'whisper-large-v3-turbo');
        expect(handler.attemptCount, 1);
        handler.attemptRecovery(currentModelId: 'whisper-medium');
        expect(handler.attemptCount, 2);
      });
    });

    // ── SwitchToConfiguredCloud decisions ────────────────────────────────────

    group('SwitchToConfiguredCloud', () {
      test('no local fallback, cloud configured → SwitchToConfiguredCloud', () {
        final handler = _makeHandler(
          chain: ['whisper-small'], // no model after small
          hasCloud: true,
        );

        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-small',
        );

        expect(decision, isA<SwitchToConfiguredCloud>());
      });

      test('retries exhausted, cloud configured → SwitchToConfiguredCloud', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium', 'whisper-small'],
          hasCloud: true,
          maxRetries: 2,
        );

        // Exhaust the 2 retries.
        handler.attemptRecovery(currentModelId: 'whisper-large-v3-turbo');
        handler.attemptRecovery(currentModelId: 'whisper-medium');
        // Third call: retries exhausted even though chain has a next model.
        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-small',
        );

        expect(decision, isA<SwitchToConfiguredCloud>());
      });

      test('SwitchToConfiguredCloud does not increment attempt count', () {
        final handler = _makeHandler(chain: ['whisper-small'], hasCloud: true);

        final before = handler.attemptCount;
        handler.attemptRecovery(currentModelId: 'whisper-small');
        expect(handler.attemptCount, before); // count unchanged
      });
    });

    // ── GiveUp decisions ─────────────────────────────────────────────────────

    group('GiveUp', () {
      test('no fallback, no cloud → GiveUp', () {
        final handler = _makeHandler(chain: ['whisper-small'], hasCloud: false);

        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-small',
        );

        expect(decision, isA<GiveUp>());
      });

      test('retries exhausted, no cloud → GiveUp', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium'],
          hasCloud: false,
          maxRetries: 1,
        );

        // Exhaust the 1 retry.
        handler.attemptRecovery(currentModelId: 'whisper-large-v3-turbo');
        // Second call: retries exhausted, no cloud.
        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-medium',
        );

        expect(decision, isA<GiveUp>());
      });

      test('unknown model id (not in chain) → GiveUp when no cloud', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium'],
          hasCloud: false,
        );

        final decision = handler.attemptRecovery(
          currentModelId: 'some-unknown-model',
        );

        expect(decision, isA<GiveUp>());
      });
    });

    // ── reset() behaviour ─────────────────────────────────────────────────────

    group('reset()', () {
      test('reset() clears attempt count so recovery restarts from zero', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium', 'whisper-small'],
          maxRetries: 2,
        );

        // Exhaust 2 retries.
        handler.attemptRecovery(currentModelId: 'whisper-large-v3-turbo');
        handler.attemptRecovery(currentModelId: 'whisper-medium');
        expect(handler.attemptCount, 2);

        // Simulate a successful transcription → reset.
        handler.reset();
        expect(handler.attemptCount, 0);

        // New OOM should yield TryNextModel again (not exhaust immediately).
        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-large-v3-turbo',
        );
        expect(decision, isA<TryNextModel>());
      });
    });

    // ── Boundary: maxRetries = 0 ──────────────────────────────────────────────

    group('maxRetries = 0', () {
      test(
        'maxRetries=0, cloud configured → SwitchToConfiguredCloud immediately',
        () {
          final handler = _makeHandler(
            chain: ['whisper-large-v3-turbo', 'whisper-medium'],
            hasCloud: true,
            maxRetries: 0,
          );

          final decision = handler.attemptRecovery(
            currentModelId: 'whisper-large-v3-turbo',
          );

          expect(decision, isA<SwitchToConfiguredCloud>());
        },
      );

      test('maxRetries=0, no cloud → GiveUp immediately', () {
        final handler = _makeHandler(
          chain: ['whisper-large-v3-turbo', 'whisper-medium'],
          hasCloud: false,
          maxRetries: 0,
        );

        final decision = handler.attemptRecovery(
          currentModelId: 'whisper-large-v3-turbo',
        );

        expect(decision, isA<GiveUp>());
      });
    });

    // ── Chain traversal ───────────────────────────────────────────────────────

    group('full chain traversal', () {
      test(
        'traverses the full 2-step chain before falling through to GiveUp',
        () {
          final chain = [
            'whisper-large-v3-turbo',
            'whisper-medium',
            'whisper-small',
          ];
          final handler = _makeHandler(chain: chain, maxRetries: 10);

          // Steps through large-turbo → medium → small.
          final d1 = handler.attemptRecovery(
            currentModelId: 'whisper-large-v3-turbo',
          );
          final d2 = handler.attemptRecovery(currentModelId: 'whisper-medium');
          // Small is last in chain → no next model, no cloud.
          final d3 = handler.attemptRecovery(currentModelId: 'whisper-small');

          expect((d1 as TryNextModel).nextModelId, 'whisper-medium');
          expect((d2 as TryNextModel).nextModelId, 'whisper-small');
          expect(d3, isA<GiveUp>());
        },
      );
    });
  });
}
