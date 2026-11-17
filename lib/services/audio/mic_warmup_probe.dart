/// Start-up diagnostics of one capture (#1777): when the device delivered its
/// first chunk, when its first real sound, how many all-zero chunks came
/// before, and how loud that first sound was.
///
/// Some microphones (laptop microphone arrays behind an audio DSP) deliver
/// nothing or only digital zeros for a while after waking from idle. The
/// dead-mic guard gives that start-up a grace period; this probe makes the
/// next case readable from the log alone: a slow start logs one line, a
/// dead-mic stop logs [diagnosis] with the reason.
///
/// Pure data, no platform calls. After the first sound, [observe] is a single
/// bool check, so the PCM hot path pays nothing for the rest of the recording.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/logging/mic_start_trace.dart';

/// Why a capture never became live, as written to the log.
enum MicWarmupState {
  /// No PCM chunk arrived at all: the device did not start delivering.
  noData('no data from the device', 'no_data'),

  /// Chunks arrived, but every sample was digital zero.
  onlySilence('only digital silence from the device', 'digital_silence'),

  /// Real sound arrived; a later stop means the signal went away again.
  live('sound arrived, then the signal stopped before speech', 'signal_lost');

  const MicWarmupState(this.reason, this.id);

  /// The log wording.
  final String reason;

  /// Fixed id for the usage statistics (no content, no device name).
  final String id;
}

/// What made a capture reopen its stream once (#1784).
enum MicReopenTrigger {
  /// No PCM chunk for [micStallReopenAfter]: the platform stream stalled
  /// without telling anyone (Linux, a Windows read that was not re-armed).
  stalled('no PCM chunk for 2 s', 'stalled'),

  /// The recorder reported `stop` although nobody stopped it (Windows stops
  /// natively after a read error, the macOS engine after a conversion error).
  platformStop('the recorder stopped by itself', 'stopped');

  const MicReopenTrigger(this.reason, this.id);

  /// The log wording.
  final String reason;

  /// Fixed id for the usage statistics (no content, no device name).
  final String id;
}

/// How long a running capture may deliver no PCM chunk at all before it is
/// reopened once (#1784). A working device delivers every 10-200 ms on all
/// three systems, digital silence included, so only a stalled stream gets
/// here.
const Duration micStallReopenAfter = Duration(seconds: 2);

/// Coarse class of a start-up time for the usage statistics (#1777): the
/// upper bound in milliseconds as `le<ms>`, `gt7000` beyond. Never the exact
/// time.
String warmupBucket(int ms) {
  for (final bound in const [500, 1000, 2000, 3000, 5000, 7000]) {
    if (ms <= bound) return 'le$bound';
  }
  return 'gt7000';
}

/// Watches the PCM chunks of one capture from the moment the stream is
/// requested.
class MicWarmupProbe {
  /// [elapsedMs] reads the milliseconds since the stream was requested; the
  /// default is a stopwatch started now. Tests pass their own clock.
  MicWarmupProbe({int Function()? elapsedMs})
    : _elapsedMs = elapsedMs ?? _stopwatchReader();

  static int Function() _stopwatchReader() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  /// A first sound after at least this many milliseconds counts as a slow
  /// start and is logged ([slowStart]). A warm microphone stays well below.
  static const int slowStartMs = 300;

  final int Function() _elapsedMs;
  final FirstSampleDetector _detector = FirstSampleDetector();

  int _chunks = 0;
  int _silentChunks = 0;
  MicReopenTrigger? _reopenTrigger;
  int? _reopenAtMs;
  int _chunksAtReopen = 0;
  bool? _reopenRunning;
  int? _firstChunkMs;
  int? _firstSoundMs;
  double? _firstSoundPeakDbFs;

  /// Feeds one 16-bit little-endian PCM chunk. Returns true exactly once: for
  /// the first chunk with real sound (same rule as [FirstSampleDetector]).
  bool observe(Uint8List chunk) {
    if (_detector.seen) return false;
    _chunks++;
    _firstChunkMs ??= _elapsedMs();
    if (!_detector.observe(chunk)) {
      _silentChunks++;
      return false;
    }
    _firstSoundMs = _elapsedMs();
    _firstSoundPeakDbFs = _peakDbFs(chunk);
    return true;
  }

  /// Where the capture stands.
  MicWarmupState get state => _firstSoundMs != null
      ? MicWarmupState.live
      : _chunks == 0
      ? MicWarmupState.noData
      : MicWarmupState.onlySilence;

  /// Milliseconds from the stream request to the first real sound, or null.
  int? get firstSoundMs => _firstSoundMs;

  /// What reopened this capture, or null when it ran on its first stream.
  MicReopenTrigger? get reopenTrigger => _reopenTrigger;

  /// Whether the reopened stream was confirmed as recording; null before
  /// the reopen finished or without one.
  bool? get reopenRunning => _reopenRunning;

  /// Notes that the capture is being reopened (at most once per capture).
  void noteReopen(MicReopenTrigger trigger) {
    _reopenTrigger = trigger;
    _reopenAtMs = _elapsedMs();
    _chunksAtReopen = _chunks;
  }

  /// Notes whether the reopened stream runs, as the recorder reports it.
  void noteReopenResult({required bool running}) => _reopenRunning = running;

  /// Whether the first sound took at least [slowStartMs].
  bool get slowStart => (_firstSoundMs ?? 0) >= slowStartMs;

  /// One line for a slow but successful start.
  String warmupLine() =>
      'Mic warm-up: first chunk after ${_ms(_firstChunkMs)}, '
      'first sound after ${_ms(_firstSoundMs)} '
      '($_silentChunks silent chunks before, peak ${_db(_firstSoundPeakDbFs)})';

  /// The state at a dead-mic stop: reason, chunk counts, timings and level.
  String diagnosis() =>
      'reason: ${state.reason} | chunks: $_chunks ($_silentChunks silent'
      ' before sound) | first chunk: ${_ms(_firstChunkMs)}'
      ' | first sound: ${_ms(_firstSoundMs)}'
      ' | first-sound peak: ${_db(_firstSoundPeakDbFs)}'
      ' | open for: ${_elapsedMs()} ms'
      ' | reopened: ${_reopenText()}';

  String _reopenText() {
    final trigger = _reopenTrigger;
    if (trigger == null) return 'no';
    final running = switch (_reopenRunning) {
      true => 'running',
      false => 'not running',
      null => 'unconfirmed',
    };
    return 'after ${_ms(_reopenAtMs)} (${trigger.reason}), $running,'
        ' ${_chunks - _chunksAtReopen} chunks since';
  }

  static String _ms(int? ms) => ms == null ? 'none' : '$ms ms';

  static String _db(double? db) =>
      db == null ? 'none' : '${db.toStringAsFixed(1)} dBFS';

  static double _peakDbFs(Uint8List chunk) {
    var peak = 0;
    final whole = chunk.length & ~1;
    for (var i = 0; i < whole; i += 2) {
      var sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final abs = sample.abs();
      if (abs > peak) peak = abs;
    }
    if (peak == 0) return double.negativeInfinity;
    return 20 * math.log(peak / 32768) / math.ln10;
  }
}
