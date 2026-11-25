/// sherpa execution providers share the existing GPU setting. A provider is
/// eligible only after a model-specific speed/accuracy measurement; unknown
/// models (including imports) stay on CPU until the catalogue supplies evidence.
library;

import '../../core/logging/app_logger.dart';
import '../stt_parakeet/parakeet_gpu_policy.dart';

final _log = AppLogger('SherpaProviderPolicy');

enum SherpaProvider { cpu, coreml, directml }

SherpaProvider selectSherpaProvider({
  required String platform,
  required bool gpuAllowed,
  required Set<SherpaProvider> measuredFasterProviders,
}) {
  if (!gpuAllowed) return SherpaProvider.cpu;
  final candidate = switch (platform) {
    'macos' => SherpaProvider.coreml,
    'windows' => SherpaProvider.directml,
    _ => SherpaProvider.cpu,
  };
  return measuredFasterProviders.contains(candidate)
      ? candidate
      : SherpaProvider.cpu;
}

/// One native recognizer with a CPU retry and a crash-loop breaker. Use a
/// separate marker directory per model/provider so this cannot consume the
/// ggml Parakeet marker. All calls run on the worker isolate.
class SherpaProviderSession<T> {
  SherpaProviderSession({
    required SherpaProvider requested,
    required this.marker,
    required this.create,
    required this.dispose,
    required this.warmUp,
    this.shouldRetry,
  }) : provider = requested {
    if (provider != SherpaProvider.cpu) {
      try {
        if (marker.recoverFromPreviousLaunch() ||
            marker.readStrikes() >= parakeetGpuCrashStrikeThreshold) {
          provider = SherpaProvider.cpu;
        }
      } catch (_) {
        // No writable crash marker means no safe GPU attempt.
        provider = SherpaProvider.cpu;
      }
    }
    _load();
  }

  final ParakeetGpuCrashMarker marker;
  final T Function(SherpaProvider) create;
  final void Function(T) dispose;
  final void Function(T) warmUp;
  final bool Function(Object)? shouldRetry;
  SherpaProvider provider;
  T? _value;

  void _load() {
    if (provider == SherpaProvider.cpu) {
      _value = create(provider);
      return;
    }
    try {
      marker.markAttempt();
      _value = create(provider);
      warmUp(_value as T);
      marker.confirmHealthy();
    } catch (_) {
      _fallBack();
    }
  }

  void _fallBack() {
    final old = _value;
    _value = null;
    provider = SherpaProvider.cpu;
    // Clear only after native teardown returns: a teardown crash must still
    // leave the attempt marker for the next launch.
    if (old != null) dispose(old);
    try {
      marker.abandonAttempt();
    } catch (e) {
      // CPU does not depend on marker I/O.
      _log.debug('Provider marker not cleared before the CPU fallback', e);
    }
    _value = create(provider);
  }

  R run<R>(R Function(T) operation) {
    if (provider == SherpaProvider.cpu) return operation(_value as T);
    try {
      marker.markAttempt();
      final result = operation(_value as T);
      marker.confirmHealthy();
      return result;
    } catch (error) {
      if (shouldRetry?.call(error) == false) {
        try {
          marker.abandonAttempt();
        } catch (e) {
          // Preserve cancellation even when the marker cannot be removed.
          _log.debug('Provider marker not cleared on cancellation', e);
        }
        rethrow;
      }
      _fallBack();
      return operation(_value as T);
    }
  }

  void close() {
    final old = _value;
    _value = null;
    if (old == null) return;
    if (provider != SherpaProvider.cpu) {
      try {
        marker.markAttempt();
      } catch (e) {
        // Teardown still has to release the native object.
        _log.debug('Provider marker not set before teardown', e);
      }
    }
    dispose(old);
    if (provider != SherpaProvider.cpu) {
      try {
        marker.abandonAttempt();
      } catch (e) {
        // A leftover marker conservatively chooses CPU on the next launch.
        _log.debug('Provider marker not cleared after teardown', e);
      }
    }
  }
}
