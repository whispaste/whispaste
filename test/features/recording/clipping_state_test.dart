/// Unit tests for [ClippingStateNotifier].
///
/// Public-interface only: state transitions in response to
/// [ClippingStateNotifier.reportRecordingFinished] and
/// [ClippingStateNotifier.dismiss]. No widget / no recording pipeline.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/recording/clipping_state.dart';

ProviderContainer makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ClippingState', () {
    test('default state has count 0 and no banner', () {
      const s = ClippingState();
      expect(s.count, 0);
      expect(s.recordingFinishedAt, isNull);
      expect(s.shouldShowBanner, isFalse);
    });

    test('positive count means banner should be shown', () {
      final s = ClippingState(count: 5, recordingFinishedAt: DateTime.now());
      expect(s.shouldShowBanner, isTrue);
    });
  });

  group('ClippingStateNotifier', () {
    test('initial state has count 0', () {
      final container = makeContainer();
      expect(container.read(clippingStateProvider).count, 0);
      expect(container.read(clippingStateProvider).shouldShowBanner, isFalse);
    });

    test('reportRecordingFinished with positive count surfaces the banner', () {
      final container = makeContainer();
      container
          .read(clippingStateProvider.notifier)
          .reportRecordingFinished(42);

      final state = container.read(clippingStateProvider);
      expect(state.count, 42);
      expect(state.recordingFinishedAt, isNotNull);
      expect(state.shouldShowBanner, isTrue);
    });

    test('dismiss resets count to 0 and hides the banner', () {
      final container = makeContainer();
      final notifier = container.read(clippingStateProvider.notifier);

      notifier.reportRecordingFinished(100);
      expect(container.read(clippingStateProvider).count, 100);

      notifier.dismiss();
      final state = container.read(clippingStateProvider);
      expect(state.count, 0);
      expect(state.shouldShowBanner, isFalse);
    });

    test('a clean follow-up recording (count=0) clears a previous banner', () {
      final container = makeContainer();
      final notifier = container.read(clippingStateProvider.notifier);

      notifier.reportRecordingFinished(7);
      expect(container.read(clippingStateProvider).shouldShowBanner, isTrue);

      // A new recording finishes cleanly — no clipping.
      notifier.reportRecordingFinished(0);

      final state = container.read(clippingStateProvider);
      expect(state.count, 0);
      expect(state.shouldShowBanner, isFalse);
    });

    test(
      'a subsequent clipping recording re-surfaces the banner after dismiss',
      () {
        final container = makeContainer();
        final notifier = container.read(clippingStateProvider.notifier);

        notifier.reportRecordingFinished(3);
        notifier.dismiss();
        expect(container.read(clippingStateProvider).shouldShowBanner, isFalse);

        notifier.reportRecordingFinished(8);
        final state = container.read(clippingStateProvider);
        expect(state.count, 8);
        expect(state.shouldShowBanner, isTrue);
      },
    );
  });
}
