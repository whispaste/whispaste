/// Mic-start latency trace: how long after the hotkey the microphone really
/// delivers audio, split into the steps of `RecordingOrchestrator
/// .startRecording`. Debug log only — never telemetry.
///
/// The start tone and overlay fire on the phase change, before the capture is
/// open; this trace measures that gap so the decision whether to delay the
/// tone (handy-catchup ticket 19) rests on numbers per OS.
library;

import 'dart:typed_data';

/// Steps of a recording start, in the order they normally complete.
enum MicStartStage {
  phaseRecording('phase→recording'),
  pasterPrimed('paster primed'),
  captureStarted('capture started'),
  firstSample('first sample');

  const MicStartStage(this.label);

  final String label;
}

/// Monotonic-clock stamps for one recording start.
///
/// t₀ is the hotkey key-down when one is pending ([hotkeyMicros]), otherwise
/// the start request ([triggerMicros]; tray, CLI or automation trigger), or
/// the moment the trace was created when neither is given.
class MicStartTrace {
  MicStartTrace({
    required this.sessionId,
    required int Function() clock,
    int? hotkeyMicros,
    int? triggerMicros,
  }) : _clock = clock,
       _fromHotkey = hotkeyMicros != null,
       _t0 = hotkeyMicros ?? triggerMicros ?? clock();

  final String sessionId;
  final int Function() _clock;
  final bool _fromHotkey;
  final int _t0;
  final Map<MicStartStage, int> _stamps = {};

  /// Stamps [stage] now; later stamps of the same stage are ignored.
  void mark(MicStartStage stage) => _stamps.putIfAbsent(stage, _clock);

  /// Milliseconds from t₀ to [stage], or null while it has not happened.
  int? elapsedMs(MicStartStage stage) {
    final at = _stamps[stage];
    return at == null ? null : (at - _t0) ~/ 1000;
  }

  bool get isComplete => _stamps.containsKey(MicStartStage.firstSample);

  /// One greppable log line with every stage (`–` for stages that were
  /// skipped, e.g. no paster priming for a quick note).
  String summary() {
    final parts = MicStartStage.values.map((stage) {
      final ms = elapsedMs(stage);
      return '${stage.label} ${ms == null ? '–' : '${ms}ms'}';
    });
    final origin = _fromHotkey ? 'hotkey' : 'trigger';
    return '[PERF] [$sessionId] mic-start from $origin: ${parts.join(', ')}';
  }
}

/// Spots the first PCM chunk (16-bit little-endian) that carries real audio.
///
/// Some devices deliver digital silence (all-zero samples) while they warm
/// up; those chunks do not count as the microphone being live. Once a
/// non-zero sample has been seen, [observe] is a single bool check.
class FirstSampleDetector {
  bool _seen = false;

  bool get seen => _seen;

  /// Returns true exactly once: for the first chunk with a non-zero sample.
  bool observe(Uint8List chunk) {
    if (_seen) return false;
    final whole = chunk.length & ~1;
    for (var i = 0; i < whole; i++) {
      if (chunk[i] != 0) {
        _seen = true;
        return true;
      }
    }
    return false;
  }
}
