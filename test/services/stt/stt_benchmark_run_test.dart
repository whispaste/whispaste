/// Unit tests for the user-visible benchmark run state (`sttBenchmarkRunProvider`).
///
/// The settings row renders this state inline (progress, cancel, error with
/// retry, done). These tests pin the transitions the row depends on.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/quality_tier.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('sttBenchmarkRunProvider', () {
    test('starts idle with nothing running and no error', () {
      final s = makeContainer().read(sttBenchmarkRunProvider);
      expect(s.phase, BenchmarkRunPhase.idle);
      expect(s.isRunning, isFalse);
      expect(s.error, isNull);
      expect(s.cancelRequested, isFalse);
    });

    test('begin -> step -> finish walks running then done with the count', () {
      final c = makeContainer();
      final n = c.read(sttBenchmarkRunProvider.notifier);

      n.begin(total: 3);
      var s = c.read(sttBenchmarkRunProvider);
      expect(s.phase, BenchmarkRunPhase.running);
      expect(s.isRunning, isTrue);
      expect(s.done, 0);
      expect(s.total, 3);

      n.step(done: 1, tier: QualityTier.compact);
      s = c.read(sttBenchmarkRunProvider);
      expect(s.done, 1);
      expect(s.tier, QualityTier.compact);

      n.finish(cancelled: false);
      s = c.read(sttBenchmarkRunProvider);
      expect(s.phase, BenchmarkRunPhase.done);
      expect(s.isRunning, isFalse);
      expect(s.cancelled, isFalse);
      expect(s.error, isNull);
    });

    test('a cancelled run finishes as done with cancelled set', () {
      final c = makeContainer();
      final n = c.read(sttBenchmarkRunProvider.notifier);
      n.begin(total: 2);
      n.requestCancel();
      expect(c.read(sttBenchmarkRunProvider).cancelRequested, isTrue);
      n.finish(cancelled: true);
      final s = c.read(sttBenchmarkRunProvider);
      expect(s.phase, BenchmarkRunPhase.done);
      expect(s.cancelled, isTrue);
      expect(s.cancelRequested, isFalse);
    });

    test('fail records the error and stops running', () {
      final c = makeContainer();
      final n = c.read(sttBenchmarkRunProvider.notifier);
      n.begin(total: 2);
      n.fail(BenchmarkRunError.failed);
      final s = c.read(sttBenchmarkRunProvider);
      expect(s.phase, BenchmarkRunPhase.failed);
      expect(s.error, BenchmarkRunError.failed);
      expect(s.isRunning, isFalse);
    });

    test('begin clears a previous error (retry)', () {
      final c = makeContainer();
      final n = c.read(sttBenchmarkRunProvider.notifier);
      n.fail(BenchmarkRunError.busy);
      n.begin(total: 1);
      final s = c.read(sttBenchmarkRunProvider);
      expect(s.error, isNull);
      expect(s.isRunning, isTrue);
    });
  });
}
