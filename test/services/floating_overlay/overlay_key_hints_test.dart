import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_key_hints.dart';

void main() {
  group('OverlayKeyHints.forRecording (which size shows hints)', () {
    test('the normal size with a live microphone shows both hints', () {
      final hints = OverlayKeyHints.forRecording(
        size: OverlaySizeVariant.normal,
        live: true,
        stopLabel: '⌥ Space',
        cancelLabel: 'Esc',
      );
      expect(hints?.stop, '⌥ Space');
      expect(hints?.cancel, 'Esc');
    });

    test('compact and mini never show hints', () {
      for (final size in [
        OverlaySizeVariant.compact,
        OverlaySizeVariant.mini,
      ]) {
        expect(
          OverlayKeyHints.forRecording(
            size: size,
            live: true,
            stopLabel: '⌥ Space',
            cancelLabel: 'Esc',
          ),
          isNull,
          reason: size.name,
        );
      }
    });

    test('no hints before the microphone is live', () {
      expect(
        OverlayKeyHints.forRecording(
          size: OverlaySizeVariant.normal,
          live: false,
          stopLabel: '⌥ Space',
        ),
        isNull,
      );
    });

    test('a hidden cancel glyph hides only the cancel hint', () {
      final hints = OverlayKeyHints.forRecording(
        size: OverlaySizeVariant.normal,
        live: true,
        stopLabel: '⌥ Space',
      );
      expect(hints?.stop, '⌥ Space');
      expect(hints?.cancel, isNull);
    });

    test('an empty stop label means no hints at all', () {
      expect(
        OverlayKeyHints.forRecording(
          size: OverlaySizeVariant.normal,
          live: true,
          stopLabel: '',
          cancelLabel: 'Esc',
        ),
        isNull,
      );
    });
  });

  group('fit rule', () {
    test('a waveform at the minimum width still fits, one below does not', () {
      expect(OverlayKeyHints.fitsWave(OverlayKeyHints.minWaveWidth), isTrue);
      expect(
        OverlayKeyHints.fitsWave(OverlayKeyHints.minWaveWidth - 0.5),
        isFalse,
      );
    });
  });

  group('snapshot hand-off', () {
    test('the hints survive the render-engine map round trip', () {
      const snapshot = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
        keyHints: OverlayKeyHints(stop: '⌥ Space', cancel: 'Esc'),
      );
      final restored = FloatingOverlaySnapshot.fromMap(snapshot.toMap());
      expect(
        restored.keyHints,
        const OverlayKeyHints(stop: '⌥ Space', cancel: 'Esc'),
      );
    });

    test('a snapshot without hints restores without hints', () {
      const snapshot = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
      );
      expect(
        FloatingOverlaySnapshot.fromMap(snapshot.toMap()).keyHints,
        isNull,
      );
    });
  });
}
