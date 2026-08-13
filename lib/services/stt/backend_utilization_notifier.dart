/// Polls this process's CPU utilization for the status bar's backend
/// indicator (`_BackendUtilizationChip` in `status_bar.dart`).
///
/// Not a GPU-load meter — see `process_cpu_probe.dart`'s file doc comment
/// for why no portable, sudo-free GPU percentage exists across
/// NVIDIA/AMD/Apple. Polling is entirely self-governed via [Notifier.build]
/// watching [localSttBundleProvider] (only meaningful once a model is
/// loaded — see `SttStatus.backend`) and the
/// `interface.showBackendUtilization` setting: no caller needs to remember
/// to start or stop it.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'process_cpu_probe.dart';
import 'stt_bundle.dart';

/// Seam over [ProcessCpuProbe] so tests can drive predictable samples
/// without depending on real FFI call timing.
abstract class CpuSampler {
  ProcessCpuSample sample();
}

class _RealCpuSampler implements CpuSampler {
  const _RealCpuSampler();

  static const _probe = ProcessCpuProbe();

  @override
  ProcessCpuSample sample() => _probe.sample();
}

final cpuSamplerProvider = Provider<CpuSampler>(
  (ref) => const _RealCpuSampler(),
);

/// Poll interval — a `Provider` (not a constant) purely so tests can shrink
/// it to milliseconds instead of waiting out a real 3 s timer.
final backendUtilizationPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// Core count used to normalize the raw per-core reading from
/// [processCpuPercentBetween] into a 0..100 share of total machine capacity
/// — a `Provider` (not [Platform.numberOfProcessors] read directly) purely
/// so tests get a fixed, host-independent core count.
final processorCountProvider = Provider<int>(
  (ref) => Platform.numberOfProcessors,
);

/// Immutable snapshot of the polled utilization.
class BackendUtilizationState {
  const BackendUtilizationState({this.cpuPercent});

  /// This process's CPU utilization as a 0..100 share of total machine
  /// capacity (not per-core — a multi-threaded transcription saturating
  /// every core reads as 100, not e.g. 800 on an 8-core machine), or `null`
  /// while polling is inactive or hasn't yet collected two samples to diff.
  final double? cpuPercent;
}

/// Riverpod [Notifier] wrapping a [Timer.periodic] poll loop over
/// [ProcessCpuProbe].
class BackendUtilizationNotifier extends Notifier<BackendUtilizationState> {
  /// Samples kept before diffing against the oldest one — at the default 3 s
  /// poll interval this is a ~12 s smoothing window. [ProcessCpuProbe] only
  /// has whole-second precision on macOS/Linux (see its doc comment), so
  /// diffing two samples 3 s apart would let that quantization noise
  /// dominate the displayed percentage; diffing against a sample several
  /// polls back dilutes it to a few percent of the window instead.
  static const _historyLength = 4;

  Timer? _timer;
  final List<ProcessCpuSample> _history = [];

  @override
  BackendUtilizationState build() {
    final backendLoaded = ref.watch(
      localSttBundleProvider.select((s) => s.backend != null),
    );
    final enabled = ref.watch(
      settingsProvider.select(
        (s) => s.value?.interface_.showBackendUtilization ?? true,
      ),
    );
    ref.onDispose(_teardown);

    if (!backendLoaded || !enabled) {
      _teardown();
      return const BackendUtilizationState();
    }

    _ensurePolling();
    return const BackendUtilizationState();
  }

  /// Whether the poll timer is currently active.
  bool get isPolling => _timer != null;

  void _ensurePolling() {
    if (_timer != null) return;
    _poll();
    _timer = Timer.periodic(
      ref.read(backendUtilizationPollIntervalProvider),
      (_) => _poll(),
    );
  }

  /// Cancels the timer and drops history — idempotent, safe pre-[build] too.
  void _teardown() {
    _timer?.cancel();
    _timer = null;
    _history.clear();
  }

  void _poll() {
    if (!ref.mounted) return;
    final sample = ref.read(cpuSamplerProvider).sample();
    _history.add(sample);
    if (_history.length > _historyLength) _history.removeAt(0);
    if (_history.length < 2) return;
    final cores = ref.read(processorCountProvider);
    final perCorePercent = processCpuPercentBetween(
      _history.first,
      sample,
      coreCount: cores,
    );
    state = BackendUtilizationState(
      cpuPercent: (perCorePercent / cores).clamp(0.0, 100.0),
    );
  }
}

final backendUtilizationProvider =
    NotifierProvider<BackendUtilizationNotifier, BackendUtilizationState>(
      BackendUtilizationNotifier.new,
    );
