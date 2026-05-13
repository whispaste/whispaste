/// Unit tests for [PipelineStepRunner] and [StepResult].
///
/// Covers:
/// - Successful step → StepResult.ok(value)
/// - Timeout → StepResult.timeout
/// - Exception → StepResult.failedWith(err)
/// - StepResult ADT exhaustiveness (pattern matching)
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording/pipeline_step_runner.dart';

void main() {
  // =========================================================================
  // StepResult ADT
  // =========================================================================

  group('StepResult', () {
    test('Ok carries the value', () {
      const result = Ok<int>(42);
      expect(result.value, 42);
    });

    test('StepTimeout carries no value', () {
      const result = StepTimeout<int>();
      expect(result, isA<StepTimeout<int>>());
    });

    test('FailedWith carries the error', () {
      final err = Exception('boom');
      final result = FailedWith<int>(err);
      expect(result.error, err);
    });

    test('pattern matching on Ok', () {
      const StepResult<String> result = Ok('hello');
      final matched = switch (result) {
        Ok(:final value) => 'ok:$value',
        StepTimeout() => 'timeout',
        FailedWith() => 'failed',
      };
      expect(matched, 'ok:hello');
    });

    test('pattern matching on StepTimeout', () {
      const StepResult<String> result = StepTimeout();
      final matched = switch (result) {
        Ok() => 'ok',
        StepTimeout() => 'timeout',
        FailedWith() => 'failed',
      };
      expect(matched, 'timeout');
    });

    test('pattern matching on FailedWith', () {
      final StepResult<String> result = FailedWith(Exception('err'));
      final matched = switch (result) {
        Ok() => 'ok',
        StepTimeout() => 'timeout',
        FailedWith(:final error) => 'failed:$error',
      };
      expect(matched, startsWith('failed:'));
    });
  });

  // =========================================================================
  // PipelineStepRunner
  // =========================================================================

  group('PipelineStepRunner', () {
    test('run returns Ok when step completes within timeout', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final result = await runner.run<int>(() async => 99);

      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, 99);
    });

    test('run returns Ok for async step that returns a value', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final result = await runner.run<String>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'done';
      });

      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, 'done');
    });

    test('run returns Timeout when step exceeds the deadline', () async {
      const runner = PipelineStepRunner(timeout: Duration(milliseconds: 50));

      final result = await runner.run<int>(() async {
        // Takes much longer than the 50 ms timeout.
        await Future<void>.delayed(const Duration(seconds: 10));
        return 0;
      });

      expect(result, isA<StepTimeout<int>>());
    });

    test('run returns FailedWith when step throws an exception', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));
      final boom = Exception('step failed');

      final result = await runner.run<int>(() async => throw boom);

      expect(result, isA<FailedWith<int>>());
      expect((result as FailedWith<int>).error, boom);
    });

    test('run wraps non-Exception errors in FailedWith', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final result = await runner.run<int>(() async => throw StateError('bad'));

      expect(result, isA<FailedWith<int>>());
      expect((result as FailedWith<int>).error, isA<StateError>());
    });

    test('run treats TimeoutException from step as StepTimeout', () async {
      // A TimeoutException thrown by the step (whether from .timeout() or
      // explicitly) is caught by the on TimeoutException handler and
      // returned as StepTimeout — this matches the intended semantics of
      // "this step timed out" regardless of who triggered it.
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final result = await runner.run<int>(
        () async => throw TimeoutException('inner timeout', Duration.zero),
      );

      expect(result, isA<StepTimeout<int>>());
    });

    test('multiple sequential runs each return independent results', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final r1 = await runner.run<int>(() async => 1);
      final r2 = await runner.run<String>(() async => 'two');
      final r3 = await runner.run<bool>(() async => throw Exception('three'));

      expect(r1, isA<Ok<int>>());
      expect(r2, isA<Ok<String>>());
      expect(r3, isA<FailedWith<bool>>());
    });

    test('per-call timeout override takes precedence when provided', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 60));

      // Override with a very short timeout for this specific call.
      final result = await runner.run<int>(() async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return 0;
      }, timeout: const Duration(milliseconds: 30));

      expect(result, isA<StepTimeout<int>>());
    });
  });

  // =========================================================================
  // Snapshot: stopRecording pipeline behavior
  // =========================================================================
  //
  // These tests verify that the PipelineStepRunner correctly models the kinds
  // of outcomes that stopRecording() generates for each pipeline step.
  // They act as a characterisation snapshot that should remain green after
  // the orchestrator steps are migrated to use the runner (Issue 13).

  group('Snapshot: pipeline step outcomes', () {
    const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

    test('happy-path step produces Ok with transcript', () async {
      final result = await runner.run<String>(() async => 'Hello world');

      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, 'Hello world');
    });

    test('STT step that throws produces FailedWith', () async {
      final result = await runner.run<String>(
        () async => throw Exception('stt_server_failed'),
      );

      expect(result, isA<FailedWith<String>>());
      final err = (result as FailedWith<String>).error;
      expect('$err', contains('stt_server_failed'));
    });

    test('save step that throws produces FailedWith', () async {
      final result = await runner.run<String>(
        () async => throw Exception('db_write_failed'),
      );

      expect(result, isA<FailedWith<String>>());
      final err = (result as FailedWith<String>).error;
      expect('$err', contains('db_write_failed'));
    });

    test('paste step that throws produces FailedWith', () async {
      final result = await runner.run<bool>(
        () async => throw Exception('paste_failed'),
      );

      expect(result, isA<FailedWith<bool>>());
      final err = (result as FailedWith<bool>).error;
      expect('$err', contains('paste_failed'));
    });

    test('slow step that exceeds timeout produces Timeout', () async {
      const slowRunner = PipelineStepRunner(
        timeout: Duration(milliseconds: 30),
      );

      final result = await slowRunner.run<String>(() async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return 'late';
      });

      expect(result, isA<StepTimeout<String>>());
    });
  });
}
