/// Pipeline step infrastructure for the recording orchestrator.
///
/// Provides [StepResult<T>] (a sealed ADT) and [PipelineStepRunner<T>]
/// (a pure helper that wraps async steps with a timeout).
///
/// These types are introduced here (Issue 12) so that the orchestrator's
/// individual steps can be migrated to use them in Issue 13. The orchestrator
/// itself is not modified in this slice.
library;

import 'dart:async';

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

/// Wraps individual async pipeline steps with a timeout and uniform
/// error handling, returning a [StepResult<T>].
///
/// The runner is intentionally pure — it holds no Riverpod [Ref] and
/// owns no mutable state beyond the default [timeout] duration.
/// This makes it trivially testable without a provider container.
///
/// Usage:
/// ```dart
/// final runner = PipelineStepRunner(timeout: const Duration(seconds: 120));
///
/// final result = await runner.run(() => transcriber.transcribe(bytes));
/// switch (result) {
///   case Ok(:final value): // use value
///   case Timeout(): // handle pipeline_timeout
///   case FailedWith(:final error): // handle error
/// }
/// ```
///
/// A per-call [timeout] override can be passed to [run] for steps that
/// require a different budget than the runner's default.
class PipelineStepRunner {
  /// Creates a [PipelineStepRunner] with the given [timeout] as the
  /// default per-step budget.
  const PipelineStepRunner({required this.timeout});

  /// Default timeout applied to each call to [run] unless overridden.
  final Duration timeout;

  /// Executes [step] and returns a [StepResult<T>].
  ///
  /// - Returns [Ok] when the step completes within the deadline.
  /// - Returns [Timeout] when the deadline is exceeded.
  /// - Returns [FailedWith] when the step throws any error.
  ///
  /// The optional [timeout] parameter overrides the runner's default
  /// for this specific call.
  Future<StepResult<T>> run<T>(
    Future<T> Function() step, {
    Duration? timeout,
  }) async {
    final deadline = timeout ?? this.timeout;
    try {
      final value = await step().timeout(deadline);
      return Ok(value);
    } on TimeoutException {
      return const StepTimeout();
    } catch (e) {
      return FailedWith(e);
    }
  }
}
