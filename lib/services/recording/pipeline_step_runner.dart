/// Pipeline step infrastructure for the recording orchestrator.
///
/// Provides [StepResult<T>] (a sealed ADT) and [PipelineStepRunner<T>]
/// (a pure helper that wraps async steps with a timeout and Sentry breadcrumbs).
///
/// These types are introduced here (Issue 12) so that the orchestrator's
/// individual steps can be migrated to use them in Issue 13. The orchestrator
/// itself is not modified in this slice.
///
/// ## Sentry breadcrumbs (Issue 14)
///
/// [PipelineStepRunner.run] automatically emits three breadcrumbs per step:
///
/// 1. **step_start** — emitted before the step begins.
/// 2. **step_success** — emitted after a successful completion with elapsed ms.
/// 3. **step_failure** — emitted when the step throws or times out with elapsed ms.
///
/// Breadcrumb payloads contain only the step name and timing data. They never
/// include transcription text, file paths with user data, or API keys, so they
/// pass through the existing 4-layer PII-scrub pipeline without modification.
///
/// For testability the breadcrumb sink can be overridden via the
/// [breadcrumbSink] constructor parameter. The default sink calls
/// `Sentry.addBreadcrumb`.
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

// ---------------------------------------------------------------------------
// BreadcrumbSink — injectable abstraction over Sentry.addBreadcrumb
// ---------------------------------------------------------------------------

/// A function that accepts a single [Breadcrumb] for recording.
///
/// The default implementation calls [Sentry.addBreadcrumb]. Tests may
/// inject a capturing lambda to verify breadcrumb emission without
/// connecting to Sentry.
typedef BreadcrumbSink = void Function(Breadcrumb breadcrumb);

/// The default [BreadcrumbSink] that forwards to [Sentry.addBreadcrumb].
void _defaultBreadcrumbSink(Breadcrumb breadcrumb) =>
    Sentry.addBreadcrumb(breadcrumb);

// ---------------------------------------------------------------------------
// StepResult<T> — sealed ADT
// ---------------------------------------------------------------------------

/// The outcome of a single pipeline step.
///
/// Exhaustive pattern matching is enforced by the sealed hierarchy:
///
/// ```dart
/// final result = await runner.run(() => transcribe(bytes));
/// switch (result) {
///   case Ok(:final value):      // proceed with value
///   case StepTimeout():         // surface pipeline_timeout error
///   case FailedWith(:final error): // surface the specific error
/// }
/// ```
sealed class StepResult<T> {
  const StepResult();
}

/// The step completed successfully and produced [value].
final class Ok<T> extends StepResult<T> {
  const Ok(this.value);

  /// The value returned by the step.
  final T value;

  @override
  String toString() => 'Ok($value)';
}

/// The step exceeded its allotted time budget.
///
/// Named [StepTimeout] rather than `Timeout` to avoid a name collision with
/// `package:test`'s `Timeout` class in test files.
final class StepTimeout<T> extends StepResult<T> {
  const StepTimeout();

  @override
  String toString() => 'StepTimeout()';
}

/// The step threw an exception captured in [error].
final class FailedWith<T> extends StepResult<T> {
  const FailedWith(this.error);

  /// The error thrown by the step.
  final Object error;

  @override
  String toString() => 'FailedWith($error)';
}

// ---------------------------------------------------------------------------
// PipelineStepRunner — pure, no Riverpod ref
// ---------------------------------------------------------------------------

/// Wraps individual async pipeline steps with a timeout, uniform error
/// handling, and automatic Sentry breadcrumbs per step.
///
/// The runner is intentionally pure — it holds no Riverpod [Ref] and
/// owns no mutable state beyond the default [timeout] duration.
/// This makes it trivially testable without a provider container.
///
/// Usage:
/// ```dart
/// final runner = PipelineStepRunner(timeout: const Duration(seconds: 120));
///
/// final result = await runner.run('transcribe', () => transcriber.transcribe(bytes));
/// switch (result) {
///   case Ok(:final value): // use value
///   case StepTimeout(): // handle pipeline_timeout
///   case FailedWith(:final error): // handle error
/// }
/// ```
///
/// A per-call [timeout] override can be passed to [run] for steps that
/// require a different budget than the runner's default.
///
/// ## Breadcrumb injection for tests
///
/// Pass a custom [breadcrumbSink] to capture emitted breadcrumbs in tests:
///
/// ```dart
/// final captured = <Breadcrumb>[];
/// final runner = PipelineStepRunner(
///   timeout: const Duration(seconds: 5),
///   breadcrumbSink: captured.add,
/// );
/// ```
class PipelineStepRunner {
  /// Creates a [PipelineStepRunner] with the given [timeout] as the
  /// default per-step budget.
  ///
  /// The optional [breadcrumbSink] overrides where breadcrumbs are sent.
  /// When omitted, breadcrumbs are forwarded to [Sentry.addBreadcrumb].
  const PipelineStepRunner({
    required this.timeout,
    BreadcrumbSink? breadcrumbSink,
  }) : _breadcrumbSink = breadcrumbSink ?? _defaultBreadcrumbSink;

  /// Default timeout applied to each call to [run] unless overridden.
  final Duration timeout;

  final BreadcrumbSink _breadcrumbSink;

  /// Executes [step] and returns a [StepResult<T>].
  ///
  /// - Returns [Ok] when the step completes within the deadline.
  /// - Returns [StepTimeout] when the deadline is exceeded.
  /// - Returns [FailedWith] when the step throws any error.
  ///
  /// The [stepName] is included in the Sentry breadcrumbs for this call.
  /// It must not contain PII (e.g. transcription text or file paths).
  ///
  /// The optional [timeout] parameter overrides the runner's default
  /// for this specific call.
  Future<StepResult<T>> run<T>(
    String stepName,
    Future<T> Function() step, {
    Duration? timeout,
  }) async {
    final deadline = timeout ?? this.timeout;

    _breadcrumbSink(
      Breadcrumb(
        message: 'pipeline:$stepName:start',
        level: SentryLevel.info,
        category: 'pipeline',
        data: {'step': stepName},
      ),
    );

    final stopwatch = Stopwatch()..start();
    try {
      final value = await step().timeout(deadline);
      stopwatch.stop();

      _breadcrumbSink(
        Breadcrumb(
          message: 'pipeline:$stepName:success',
          level: SentryLevel.info,
          category: 'pipeline',
          data: {'step': stepName, 'elapsed_ms': stopwatch.elapsedMilliseconds},
        ),
      );

      return Ok(value);
    } on TimeoutException {
      stopwatch.stop();

      _breadcrumbSink(
        Breadcrumb(
          message: 'pipeline:$stepName:timeout',
          level: SentryLevel.warning,
          category: 'pipeline',
          data: {
            'step': stepName,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
            'outcome': 'timeout',
          },
        ),
      );

      return const StepTimeout();
    } catch (e) {
      stopwatch.stop();

      _breadcrumbSink(
        Breadcrumb(
          message: 'pipeline:$stepName:failure',
          level: SentryLevel.error,
          category: 'pipeline',
          data: {
            'step': stepName,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
            'outcome': 'error',
          },
        ),
      );

      return FailedWith(e);
    }
  }
}
