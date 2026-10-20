import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio_service.dart';

void main() {
  group('AudioStatus.hasLiveSamples', () {
    test('an opened capture has no live samples until one arrives', () {
      const opened = AudioStatus(
        captureState: AudioCaptureState.recording,
        filePath: '/tmp/a.wav',
      );
      expect(opened.hasLiveSamples, isFalse);
    });

    test('withLiveSamples keeps the capture and sets the flag', () {
      const opened = AudioStatus(
        captureState: AudioCaptureState.recording,
        filePath: '/tmp/a.wav',
      );
      final live = opened.withLiveSamples();
      expect(live.hasLiveSamples, isTrue);
      expect(live.captureState, AudioCaptureState.recording);
      expect(live.filePath, '/tmp/a.wav');
    });
  });
}
