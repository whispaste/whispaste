/// Live preview of the transcript during recording with the system speech
/// engine (#1078). It only feeds the overlay: the final transcript always
/// comes from `SystemSpeechTranscriber` on the saved WAV, so an interim text
/// never replaces it. Nothing runs unless [start] is called, which the
/// recording only does when the setting and the overlay size ask for it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'system_speech_channel.dart';
import 'system_speech_status.dart';

final systemSpeechLivePreviewProvider = Provider<SystemSpeechLivePreview>((
  ref,
) {
  final preview = SystemSpeechLivePreview(ref.read(systemSpeechChannelProvider))
    ..attach();
  ref.onDispose(preview.dispose);
  return preview;
});

class SystemSpeechLivePreview {
  SystemSpeechLivePreview(this._channel);

  final SystemSpeechChannel _channel;
  final StreamController<String> _text = StreamController<String>.broadcast();

  /// Interim text of the running recording, full text so far on each event.
  Stream<String> get preview => _text.stream;

  /// Chunks that arrive while the host is still opening the analyzer.
  final List<Uint8List> _pending = [];
  bool _starting = false;
  bool _running = false;
  int _generation = 0;

  void attach() => _channel.onLivePartial((text) {
    if (_running && !_text.isClosed) _text.add(text);
  });

  Future<void> start(String locale) async {
    final generation = ++_generation;
    _starting = true;
    _pending.clear();
    final ok = await _channel.liveStart(locale);
    if (generation != _generation) return; // stopped meanwhile
    _starting = false;
    _running = ok;
    if (!ok) {
      _pending.clear();
      return;
    }
    for (final chunk in _pending) {
      unawaited(_channel.liveFeed(chunk));
    }
    _pending.clear();
  }

  void feed(Uint8List chunk) {
    if (_running) {
      unawaited(_channel.liveFeed(chunk));
    } else if (_starting) {
      _pending.add(chunk);
    }
  }

  Future<void> stop() async {
    _generation++;
    final wasActive = _running || _starting;
    _running = false;
    _starting = false;
    _pending.clear();
    if (wasActive) await _channel.liveStop();
  }

  void dispose() {
    unawaited(_text.close());
  }
}
