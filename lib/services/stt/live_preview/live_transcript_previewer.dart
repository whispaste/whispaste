/// Drives the live-transcript-DURING-recording preview
/// (live-transcript-streaming ticket) — distinct from the existing
/// [PartialTranscriptSource]-based preview (`whisper_ffi_engine.dart`),
/// which only ever surfaces text for the POST-recording batch decode.
///
/// This class owns exactly the sliding-window buffering + fixed-timer/
/// debounce trigger logic; it knows nothing about FFI, whisper.cpp, or
/// Riverpod — [decode] is injected, so this is fully unit-testable with a
/// fake decode function.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../../core/logging/app_logger.dart';
import '../../audio/pcm_sliding_window.dart';
import '../../audio/pcm_wav_codec.dart' show pcm16BytesToFloat32;

final _log = AppLogger('LiveTranscriptPreviewer');

/// Buffers raw PCM from an active recording, keeps only a trailing sliding
/// window, and — on a fixed timer, debounced by [minDecodeInterval] —
/// decodes that window via the injected `decode` function and broadcasts
/// the result on [preview]. Each [preview] event REPLACES the previous one
/// (callers overwrite their displayed text, never append/accumulate).
///
/// Trigger note: the feature's architecture considered reusing the bundled
/// Silero-VAD model's pause detection to pick smarter decode moments instead
/// of a fixed timer. That VAD is wired only as whisper.cpp's own internal
/// PRE-DECODE trim (`whisper_full_params.vad`, see the "VAD-gated
/// hallucination hardening" comment in `whisper_ffi_engine.dart`) — there is
/// no separate, lightweight streaming silence-detector callback anywhere in
/// this app that fires independently of a full decode call (the amplitude-
/// based `SafetyGuard`/`autoStopSilence` auto-stop is a different,
/// RMS-threshold mechanism, not Silero VAD). Wiring a second, real-time
/// Silero pass purely to pick trigger moments would need new FFI
/// bindings/struct work beyond this ticket's scope (`whisper_vad_*`), for a
/// benefit (slightly better-placed decode boundaries) a fixed timer with a
/// hard debounce already gets most of the way to. This class therefore uses
/// the documented fixed-timer fallback explicitly permitted for this case.
class LiveTranscriptPreviewer {
  LiveTranscriptPreviewer({
    required Future<String> Function(Float32List samples) decode,
    this.windowSeconds = 25.0,
    this.triggerInterval = const Duration(seconds: 2),
    this.minDecodeInterval = const Duration(milliseconds: 1500),
    this.sampleRate = 16000,
    DateTime Function()? now,
  }) : // The public param name `decode` must stay descriptive at call
       // sites; `_decode` can't be used as a named parameter name (leading
       // underscore makes it library-private, unreachable from the calling
       // `stt_server_state_notifier.dart`), so this can't use an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _decode = decode,
       _now = now ?? DateTime.now;

  final Future<String> Function(Float32List samples) _decode;
  final DateTime Function() _now;

  /// Trailing window (seconds) of PCM kept for a preview decode — bounded
  /// so decode time never grows across a long dictation. The full recording
  /// is unaffected: it keeps accumulating in the WAV writer as always, this
  /// class only ever sees/keeps its own trimmed copy.
  final double windowSeconds;

  /// How often a decode is attempted while [isActive].
  final Duration triggerInterval;

  /// Hard cap: never decode more often than this, even if triggered more
  /// frequently (e.g. a future VAD-pause trigger firing in a burst).
  final Duration minDecodeInterval;

  final int sampleRate;

  Uint8List _buffer = Uint8List(0);
  Timer? _timer;
  DateTime? _lastDecodeAt;
  bool _decoding = false;
  bool _active = false;

  final StreamController<String> _previewController =
      StreamController<String>.broadcast();

  /// Broadcast stream of preview text — one event per completed decode.
  Stream<String> get preview => _previewController.stream;

  /// True between [start] and [stop]/[dispose] — while true, [addPcmChunk]
  /// buffers and the trigger timer runs; while false, both are no-ops. This
  /// is the performance guarantee: a caller that never calls [start] (e.g.
  /// because the user has `overlayShowLiveTranscript` off) pays nothing
  /// beyond holding this (inert) object.
  bool get isActive => _active;

  /// Starts buffering PCM and arms the trigger timer. No-op if already
  /// active.
  void start() {
    if (_active) return;
    _active = true;
    _buffer = Uint8List(0);
    _lastDecodeAt = null;
    _timer = Timer.periodic(triggerInterval, (_) => _maybeTrigger());
  }

  /// Appends a raw PCM chunk (16-bit mono LE, no WAV header) and trims the
  /// internal buffer back to [windowSeconds]. No-op while not [isActive].
  void addPcmChunk(Uint8List chunk) {
    if (!_active) return;
    final combined = Uint8List(_buffer.length + chunk.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
    _buffer = trimPcmToWindow(
      combined,
      sampleRate: sampleRate,
      windowSeconds: windowSeconds,
    );
  }

  /// Stops the trigger timer and clears the buffer. An in-flight decode (if
  /// any) is left to finish on its own; nothing new is triggered after this
  /// returns. Safe to call repeatedly / while not active.
  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _buffer = Uint8List(0);
    _lastDecodeAt = null;
  }

  void dispose() {
    stop();
    _previewController.close();
  }

  /// The timer callback body — also directly callable (e.g. from tests) so
  /// the debounce logic can be exercised without depending on real/fake
  /// timer plumbing.
  Future<void> onTriggerTick() => _maybeTrigger();

  Future<void> _maybeTrigger() async {
    if (!_active || _decoding) return;
    final now = _now();
    final last = _lastDecodeAt;
    if (last != null && now.difference(last) < minDecodeInterval) return;
    if (_buffer.isEmpty) return;

    _decoding = true;
    _lastDecodeAt = now;
    try {
      final samples = pcm16BytesToFloat32(_buffer);
      final text = await _decode(samples);
      if (!_previewController.isClosed) {
        _previewController.add(text);
      }
    } catch (e) {
      _log.debug('Live-preview decode failed: $e');
    } finally {
      _decoding = false;
    }
  }
}
