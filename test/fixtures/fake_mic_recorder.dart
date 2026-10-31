/// Test double for [MicProbeRecorder] — shared between the probe unit tests
/// and the microphone-step widget tests so both exercise the same fake
/// behaviour.
library;

// The PCM controller is closed in `stop()` / `dispose()` once the consumer
// is done with the stream, but the lint can't see that across the
// `startStream` boundary.
// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';

class FakeMicRecorder implements MicProbeRecorder {
  FakeMicRecorder({
    this._hasPermission = true,
    this._throwOnPermission = false,
    this._throwOnStart = false,
    this._devices = const [],
    this._throwOnListDevices = false,
  });

  bool _hasPermission;
  final bool _throwOnPermission;
  final bool _throwOnStart;
  final List<InputDevice> _devices;
  final bool _throwOnListDevices;

  StreamController<Uint8List>? _streamController;

  RecordConfig? lastConfig;
  bool _recording = false;
  int stopCalls = 0;
  int disposeCalls = 0;

  void setPermission(bool granted) => _hasPermission = granted;

  void emitPcm(Uint8List bytes) {
    final controller = _streamController;
    if (controller == null) {
      throw StateError('emitPcm called before startStream subscription');
    }
    controller.add(bytes);
  }

  void emitStreamError() {
    _streamController?.addError(Exception('boom'));
  }

  @override
  Future<bool> hasPermission() async {
    if (_throwOnPermission) throw Exception('permission lookup failed');
    return _hasPermission;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    if (_throwOnStart) throw Exception('startStream failed');
    lastConfig = config;
    _recording = true;
    final controller = _streamController = StreamController<Uint8List>();
    return controller.stream;
  }

  @override
  Future<bool> isRecording() async => _recording;

  @override
  Future<String?> stop() async {
    stopCalls++;
    _recording = false;
    await _streamController?.close();
    _streamController = null;
    return null;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _streamController?.close();
    _streamController = null;
  }

  @override
  Future<List<InputDevice>> listInputDevices() async {
    if (_throwOnListDevices) throw Exception('listInputDevices failed');
    return _devices;
  }
}
