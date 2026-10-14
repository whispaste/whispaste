/// Classifies why `AudioRecorder.startStream` failed (Sentry 123116227):
/// a machine without any input device is an expected user condition, not
/// a defect, and must surface a "no microphone" message instead of being
/// escalated to Sentry as an error.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio_service.dart';

void main() {
  final recordError = PlatformException(
    code: 'Record',
    // Localized OS text (Hungarian Windows) — must not matter.
    message: 'Nem található hangrögzítő eszköz.',
  );

  test('no input device + recorder error → no microphone', () {
    expect(
      classifyRecordingStartFailure(recordError, inputDeviceCount: 0),
      RecordingStartFailure.noMicrophone,
    );
  });

  test('input devices present → genuine start failure', () {
    expect(
      classifyRecordingStartFailure(recordError, inputDeviceCount: 2),
      RecordingStartFailure.startFailed,
    );
  });

  test('device enumeration unavailable → genuine start failure', () {
    expect(
      classifyRecordingStartFailure(recordError, inputDeviceCount: null),
      RecordingStartFailure.startFailed,
    );
  });

  test('non-recorder exception stays a genuine start failure', () {
    expect(
      classifyRecordingStartFailure(
        const FileSystemExceptionStub(),
        inputDeviceCount: 0,
      ),
      RecordingStartFailure.startFailed,
    );
  });

  test('error codes map to the localized pipeline keys', () {
    expect(RecordingStartFailure.noMicrophone.errorCode, 'no_microphone');
    expect(
      RecordingStartFailure.startFailed.errorCode,
      'recording_start_failed',
    );
  });
}

class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub();
}
