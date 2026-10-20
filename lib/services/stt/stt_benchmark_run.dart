/// User-visible state of a benchmark run ("Leistungstest" / re-run benchmark).
///
/// The run itself lives in `SttServerStateNotifier.runBenchmark`; this
/// notifier only holds what the settings row needs to render inline:
/// progress (x of n tiers), a cancel request, and an error to show with a
/// retry. The measured results themselves are persisted in settings
/// (`tierBenchmarkRtf`, `benchmarkTimestamp`, …), so they survive a restart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/quality_tier.dart';

enum BenchmarkRunPhase { idle, running, done, failed }

/// Why a run could not start or did not finish. Mapped to localized text in
/// the settings row, so the service never carries user-facing strings.
enum BenchmarkRunError {
  /// A dictation is in progress; the run would compete with it.
  busy,

  /// No quality tier is installed, so there is nothing to measure.
  noModel,

  /// Loading or measuring a model failed.
  failed,
}

class BenchmarkRunState {
  const BenchmarkRunState({
    this.phase = BenchmarkRunPhase.idle,
    this.done = 0,
    this.total = 0,
    this.tier,
    this.error,
    this.cancelRequested = false,
    this.cancelled = false,
  });

  final BenchmarkRunPhase phase;

  /// Tiers already measured in the current run.
  final int done;

  /// Tiers planned for the current run.
  final int total;

  /// The tier being measured right now, while [isRunning].
  final QualityTier? tier;

  final BenchmarkRunError? error;

  /// Set by the user; the run stops after the step in progress.
  final bool cancelRequested;

  /// The last finished run stopped early because of a cancel request.
  final bool cancelled;

  bool get isRunning => phase == BenchmarkRunPhase.running;

  BenchmarkRunState copyWith({
    BenchmarkRunPhase? phase,
    int? done,
    int? total,
    QualityTier? tier,
    bool clearTier = false,
    BenchmarkRunError? error,
    bool clearError = false,
    bool? cancelRequested,
    bool? cancelled,
  }) => BenchmarkRunState(
    phase: phase ?? this.phase,
    done: done ?? this.done,
    total: total ?? this.total,
    tier: clearTier ? null : (tier ?? this.tier),
    error: clearError ? null : (error ?? this.error),
    cancelRequested: cancelRequested ?? this.cancelRequested,
    cancelled: cancelled ?? this.cancelled,
  );
}

class BenchmarkRunNotifier extends Notifier<BenchmarkRunState> {
  @override
  BenchmarkRunState build() => const BenchmarkRunState();

  /// Starts a run over [total] tiers. Clears a previous error (retry).
  void begin({required int total}) =>
      state = BenchmarkRunState(phase: BenchmarkRunPhase.running, total: total);

  /// [done] tiers are measured; [tier] is the one now in progress.
  void step({required int done, required QualityTier tier}) =>
      state = state.copyWith(done: done, tier: tier);

  void requestCancel() => state = state.copyWith(cancelRequested: true);

  void finish({required bool cancelled}) => state = state.copyWith(
    phase: BenchmarkRunPhase.done,
    cancelled: cancelled,
    cancelRequested: false,
    clearTier: true,
  );

  void fail(BenchmarkRunError error) => state = state.copyWith(
    phase: BenchmarkRunPhase.failed,
    error: error,
    cancelRequested: false,
    clearTier: true,
  );
}

final sttBenchmarkRunProvider =
    NotifierProvider<BenchmarkRunNotifier, BenchmarkRunState>(
      BenchmarkRunNotifier.new,
    );
