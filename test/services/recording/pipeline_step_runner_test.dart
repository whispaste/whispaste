/// Unit tests for [PipelineStepRunner] and [StepResult].
///
/// Covers:
/// - Successful step → StepResult.ok(value)
/// - Timeout → StepResult.timeout
/// - Exception → StepResult.failedWith(err)
/// - StepResult ADT exhaustiveness (pattern matching)
/// - Sentry breadcrumb emission (Issue 14)
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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

      final result = await runner.run<int>('test_step', () async => 99);

      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, 99);
    });

    test('run returns Ok for async step that returns a value', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final result = await runner.run<String>('async_step', () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'done';
      });

      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, 'done');
    });

    test('run returns Timeout when step exceeds the deadline', () async {
      const runner = PipelineStepRunner(timeout: Duration(milliseconds: 50));

      final result = await runner.run<int>('slow_step', () async {
        // Takes much longer than the 50 ms timeout.
        await Future<void>.delayed(const Duration(seconds: 10));
        return 0;
      });

      expect(result, isA<StepTimeout<int>>());
    });

    test('run returns FailedWith when step throws an exception', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));
      final boom = Exception('step failed');

      final result = await runner.run<int>(
        'failing_step',
        () async => throw boom,
      );

      expect(result, isA<FailedWith<int>>());
      expect((result as FailedWith<int>).error, boom);
    });

    test('run wraps non-Exception errors in FailedWith', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final result = await runner.run<int>(
        'state_error_step',
        () async => throw StateError('bad'),
      );

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
        'timeout_exception_step',
        () async => throw TimeoutException('inner timeout', Duration.zero),
      );

      expect(result, isA<StepTimeout<int>>());
    });

    test('multiple sequential runs each return independent results', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 5));

      final r1 = await runner.run<int>('step_one', () async => 1);
      final r2 = await runner.run<String>('step_two', () async => 'two');
      final r3 = await runner.run<bool>(
        'step_three',
        () async => throw Exception('three'),
      );

      expect(r1, isA<Ok<int>>());
      expect(r2, isA<Ok<String>>());
      expect(r3, isA<FailedWith<bool>>());
    });

    test('per-call timeout override takes precedence when provided', () async {
      const runner = PipelineStepRunner(timeout: Duration(seconds: 60));

      // Override with a very short timeout for this specific call.
      final result = await runner.run<int>('overridden_timeout_step', () async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return 0;
      }, timeout: const Duration(milliseconds: 30));

      expect(result, isA<StepTimeout<int>>());
    });
  });

  // =========================================================================
  // Sentry breadcrumb emission (Issue 14)
  // =========================================================================

  group('PipelineStepRunner breadcrumbs', () {
    /// Returns a runner that captures emitted breadcrumbs into [captured].
    PipelineStepRunner runnerWithCapture(List<Breadcrumb> captured) =>
        PipelineStepRunner(
          timeout: const Duration(seconds: 5),
          breadcrumbSink: captured.add,
        );

    test('successful step emits start and success breadcrumbs', () async {
      final captured = <Breadcrumb>[];
      final runner = runnerWithCapture(captured);

      await runner.run<int>('transcribe', () async => 42);

      expect(captured, hasLength(2));

      final start = captured[0];
      expect(start.message, 'pipeline:transcribe:start');
      expect(start.level, SentryLevel.info);
      expect(start.category, 'pipeline');
      expect(start.data?['step'], 'transcribe');

      final success = captured[1];
      expect(success.message, 'pipeline:transcribe:success');
      expect(success.level, SentryLevel.info);
      expect(success.category, 'pipeline');
      expect(success.data?['step'], 'transcribe');
      expect(success.data?['elapsed_ms'], isA<int>());
    });

    test('failing step emits start and failure breadcrumbs', () async {
      final captured = <Breadcrumb>[];
      final runner = runnerWithCapture(captured);

      await runner.run<int>(
        'save_history',
        () async => throw Exception('db_write_failed'),
      );

      expect(captured, hasLength(2));

      final start = captured[0];
      expect(start.message, 'pipeline:save_history:start');
      expect(start.level, SentryLevel.info);

      final failure = captured[1];
      expect(failure.message, 'pipeline:save_history:failure');
      expect(failure.level, SentryLevel.error);
      expect(failure.data?['step'], 'save_history');
      expect(failure.data?['elapsed_ms'], isA<int>());
      expect(failure.data?['outcome'], 'error');
    });

    test('timed-out step emits start and timeout breadcrumbs', () async {
      final captured = <Breadcrumb>[];
      final runner = PipelineStepRunner(
        timeout: const Duration(milliseconds: 30),
        breadcrumbSink: captured.add,
      );

      await runner.run<int>('paste', () async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return 0;
      });

      expect(captured, hasLength(2));

      final start = captured[0];
      expect(start.message, 'pipeline:paste:start');

      final timeout = captured[1];
      expect(timeout.message, 'pipeline:paste:timeout');
      expect(timeout.level, SentryLevel.warning);
      expect(timeout.data?['outcome'], 'timeout');
      expect(timeout.data?['elapsed_ms'], isA<int>());
    });

    test('breadcrumb data never contains transcription text', () async {
      // Verify that the step return value (which could be transcribed text)
      // is never included in any breadcrumb payload.
      final captured = <Breadcrumb>[];
      final runner = runnerWithCapture(captured);
      const piiText = 'My secret transcription with PII';

      await runner.run<String>('transcribe', () async => piiText);

      for (final crumb in captured) {
        expect(crumb.message, isNot(contains(piiText)));
        for (final val in (crumb.data ?? {}).values) {
          expect('$val', isNot(contains(piiText)));
        }
      }
    });

    test('step name appears in all emitted breadcrumbs', () async {
      final captured = <Breadcrumb>[];
      final runner = runnerWithCapture(captured);

      await runner.run<bool>('desktop_paste', () async => true);

      expect(captured, hasLength(2));
      for (final crumb in captured) {
        expect(crumb.data?['step'], 'desktop_paste');
      }
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
    // Use a no-op breadcrumb sink to avoid hitting Sentry in snapshot tests.
    final runner = PipelineStepRunner(
      timeout: const Duration(seconds: 5),
      breadcrumbSink: (_) {},
    );

    test('happy-path step produces Ok with transcript', () async {
      final result = await runner.run<String>(
        'transcribe',
        () async => 'Hello world',
      );

      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, 'Hello world');
    });

    test('STT step that throws produces FailedWith', () async {
      final result = await runner.run<String>(
        'transcribe',
        () async => throw Exception('stt_server_failed'),
      );

      expect(result, isA<FailedWith<String>>());
      final err = (result as FailedWith<String>).error;
      expect('$err', contains('stt_server_failed'));
    });

    test('save step that throws produces FailedWith', () async {
      final result = await runner.run<String>(
        'save_history',
        () async => throw Exception('db_write_failed'),
      );

      expect(result, isA<FailedWith<String>>());
      final err = (result as FailedWith<String>).error;
      expect('$err', contains('db_write_failed'));
    });

    test('paste step that throws produces FailedWith', () async {
      final result = await runner.run<bool>(
        'desktop_paste',
        () async => throw Exception('paste_failed'),
      );

      expect(result, isA<FailedWith<bool>>());
      final err = (result as FailedWith<bool>).error;
      expect('$err', contains('paste_failed'));
    });

    test('slow step that exceeds timeout produces Timeout', () async {
      final slowRunner = PipelineStepRunner(
        timeout: const Duration(milliseconds: 30),
        breadcrumbSink: (_) {},
      );

      final result = await slowRunner.run<String>('slow_step', () async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return 'late';
      });

      expect(result, isA<StepTimeout<String>>());
    });
  });
}
