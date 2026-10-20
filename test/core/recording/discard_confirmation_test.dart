/// Confirm-before-discard for long recordings: short recordings discard at
/// once; a long one arms a confirmation that the next press inside the window
/// completes, and that expires on its own.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/discard_confirmation.dart';

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('a short recording is discarded at once without arming', () {
    final container = makeContainer();
    final discard = container.read(discardConfirmProvider.notifier);

    final now = discard.onCancelPressed(const Duration(seconds: 29));

    expect(now, isTrue);
    expect(container.read(discardConfirmProvider), isFalse);
  });

  test('exactly the threshold counts as long and asks first', () {
    final container = makeContainer();
    final discard = container.read(discardConfirmProvider.notifier);

    final now = discard.onCancelPressed(longRecordingThreshold);

    expect(now, isFalse);
    expect(container.read(discardConfirmProvider), isTrue);
  });

  test('a second press inside the window discards and disarms', () {
    FakeAsync().run((async) {
      final container = makeContainer();
      final discard = container.read(discardConfirmProvider.notifier);

      expect(discard.onCancelPressed(const Duration(seconds: 40)), isFalse);
      async.elapse(confirmWindow - const Duration(milliseconds: 100));
      expect(discard.onCancelPressed(const Duration(seconds: 40)), isTrue);
      expect(container.read(discardConfirmProvider), isFalse);
    });
  });

  test('the armed confirmation expires after the window', () {
    FakeAsync().run((async) {
      final container = makeContainer();
      final discard = container.read(discardConfirmProvider.notifier);

      discard.onCancelPressed(const Duration(seconds: 40));
      async.elapse(confirmWindow + const Duration(milliseconds: 1));
      expect(container.read(discardConfirmProvider), isFalse);

      // A press after expiry arms again instead of discarding.
      expect(discard.onCancelPressed(const Duration(seconds: 40)), isFalse);
    });
  });
}
