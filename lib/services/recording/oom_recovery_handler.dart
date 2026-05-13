/// OOM recovery policy for the recording pipeline.
///
/// Encapsulates the retry-count and model-fallback logic that was previously
/// inlined in [RecordingOrchestrator._handleOomRecovery].  The orchestrator
/// now calls [OomRecoveryHandler.attemptRecovery] and acts on the returned
/// [RecoveryDecision] — it no longer owns the policy itself.
library;

// ---------------------------------------------------------------------------
// Decision ADT
// ---------------------------------------------------------------------------

/// The result of a single OOM recovery attempt.
sealed class RecoveryDecision {
  const RecoveryDecision();
}

/// Retry with [nextModelId] (a smaller/lighter local model).
final class TryNextModel extends RecoveryDecision {
  const TryNextModel(this.nextModelId);

  /// The model ID the orchestrator should switch to before retrying.
  final String nextModelId;

  @override
  String toString() => 'TryNextModel($nextModelId)';
}

/// Switch to the user's configured cloud STT provider.
///
/// Emitted when no local model fallback is available but a cloud API key
/// is present.
final class SwitchToConfiguredCloud extends RecoveryDecision {
  const SwitchToConfiguredCloud();

  @override
  String toString() => 'SwitchToConfiguredCloud';
}

/// No recovery path found — surface the error to the user.
///
/// Emitted when retries are exhausted, no smaller local model is available,
/// and no cloud provider is configured.
final class GiveUp extends RecoveryDecision {
  const GiveUp();

  @override
  String toString() => 'GiveUp';
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Encapsulates OOM retry policy for the recording pipeline.
///
/// Usage:
/// ```dart
/// final handler = OomRecoveryHandler(
///   maxRetries: 3,
///   nextModelIdForCurrent: (id) => _nextAvailableFallbackModelId(id),
///   hasCloudConfigured: () => _preferredCloudProvider(settings) != null,
/// );
///
/// final decision = handler.attemptRecovery(currentModelId: settings.effectiveModelId);
/// switch (decision) {
///   case TryNextModel(:final nextModelId): ...
///   case SwitchToConfiguredCloud(): ...
///   case GiveUp(): ...
/// }
/// ```
///
/// The retry count is fully encapsulated — callers cannot read or mutate it.
/// Call [reset] to clear the count after a successful transcription.
class OomRecoveryHandler {
  /// Creates an [OomRecoveryHandler].
  ///
  /// [maxRetries]           — maximum number of model-fallback attempts before
  ///                          giving up or switching to cloud.
  /// [nextModelIdForCurrent] — returns the next lighter model ID for a given
  ///                           model, or `null` if there is no lighter model.
  ///                           Delegates to `LocalSttServer.applyModelFallback`
  ///                           (or equivalent lookup) in production.
  /// [hasCloudConfigured]   — returns `true` when a cloud API key is available.
  OomRecoveryHandler({
    required int maxRetries,
    required String? Function(String currentModelId) nextModelIdForCurrent,
    required bool Function() hasCloudConfigured,
  }) : _maxRetries = maxRetries,
       _nextModelIdForCurrent = nextModelIdForCurrent,
       _hasCloudConfigured = hasCloudConfigured;

  final int _maxRetries;
  final String? Function(String currentModelId) _nextModelIdForCurrent;
  final bool Function() _hasCloudConfigured;

  int _attemptCount = 0;

  /// Evaluates the next recovery action for an OOM failure on [currentModelId].
  ///
  /// Decision table:
  ///
  /// | attempts < maxRetries | next model exists | cloud configured | decision                |
  /// |----------------------|-------------------|------------------|-------------------------|
  /// | true                 | true              | any              | TryNextModel            |
  /// | true                 | false             | true             | SwitchToConfiguredCloud |
  /// | true                 | false             | false            | GiveUp                  |
  /// | false (exhausted)    | any               | true             | SwitchToConfiguredCloud |
  /// | false (exhausted)    | any               | false            | GiveUp                  |
  RecoveryDecision attemptRecovery({required String currentModelId}) {
    final nextModelId = _nextModelIdForCurrent(currentModelId);
    final retriesLeft = _attemptCount < _maxRetries;

    if (retriesLeft && nextModelId != null) {
      _attemptCount++;
      return TryNextModel(nextModelId);
    }

    if (_hasCloudConfigured()) {
      return const SwitchToConfiguredCloud();
    }

    return const GiveUp();
  }

  /// Resets the internal retry counter.
  ///
  /// Call this after a successful transcription so that a subsequent OOM (on a
  /// new recording session) starts from zero retries again.
  void reset() => _attemptCount = 0;

  /// Current attempt count — exposed only for diagnostics/logging.
  /// Intentionally not part of the public decision API.
  int get attemptCount => _attemptCount;
}
