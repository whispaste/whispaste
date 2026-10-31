import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_shell_gate.dart';

/// ticket phase 2, plan items 2 and 3: the Dart side only sends a hide when the
/// shell actually needs one (a visible→hidden change, or a size change that
/// must reach the hidden shell), so an idle settings sync does not re-order
/// an already hidden panel.
void main() {
  FloatingOverlaySnapshot snap({
    required bool visible,
    OverlaySizeVariant size = OverlaySizeVariant.normal,
    OverlayBackground background = OverlayBackground.marine,
    OverlayWave wave = OverlayWave.cyan,
  }) => FloatingOverlaySnapshot(
    visible: visible,
    state: OverlayVisualState.recording,
    size: size,
    background: background,
    wave: wave,
    label: '',
  );

  group('OverlayShellGate', () {
    test('every visible snapshot is sent, including repeats', () {
      final gate = OverlayShellGate();
      expect(gate.shouldSend(snap(visible: true)), isTrue);
      expect(gate.shouldSend(snap(visible: true)), isTrue);
    });

    test('the first hide after a show is sent', () {
      final gate = OverlayShellGate();
      gate.shouldSend(snap(visible: true));

      expect(gate.shouldSend(snap(visible: false)), isTrue);
    });

    test('a repeated hide at the same size is suppressed', () {
      final gate = OverlayShellGate();
      gate.shouldSend(snap(visible: true));
      gate.shouldSend(snap(visible: false));

      expect(gate.shouldSend(snap(visible: false)), isFalse);
    });

    test(
      'a hide that changes the size is sent so the shell resizes off the hot path',
      () {
        final gate = OverlayShellGate();
        gate.shouldSend(snap(visible: true));
        gate.shouldSend(snap(visible: false));

        expect(
          gate.shouldSend(
            snap(visible: false, size: OverlaySizeVariant.compact),
          ),
          isTrue,
        );
      },
    );

    test('the very first hide (nothing shown yet) is sent once', () {
      final gate = OverlayShellGate();

      expect(gate.shouldSend(snap(visible: false)), isTrue);
      expect(gate.shouldSend(snap(visible: false)), isFalse);
    });

    test('a show after a suppressed hide is sent again', () {
      final gate = OverlayShellGate();
      gate.shouldSend(snap(visible: false));
      gate.shouldSend(snap(visible: false));

      expect(gate.shouldSend(snap(visible: true)), isTrue);
    });
    test(
      'a hide that changes the background preset is sent, not swallowed',
      () {
        final gate = OverlayShellGate();
        gate.shouldSend(snap(visible: true));
        gate.shouldSend(snap(visible: false));

        expect(
          gate.shouldSend(
            snap(visible: false, background: OverlayBackground.amber),
          ),
          isTrue,
        );
      },
    );

    test('a hide that changes the wave preset is sent, not swallowed', () {
      final gate = OverlayShellGate();
      gate.shouldSend(snap(visible: true));
      gate.shouldSend(snap(visible: false));

      expect(
        gate.shouldSend(snap(visible: false, wave: OverlayWave.amber)),
        isTrue,
      );
    });

    test('a repeated hide with the same presets stays suppressed', () {
      final gate = OverlayShellGate();
      gate.shouldSend(snap(visible: true, background: OverlayBackground.amber));
      gate.shouldSend(
        snap(visible: false, background: OverlayBackground.amber),
      );

      expect(
        gate.shouldSend(
          snap(visible: false, background: OverlayBackground.amber),
        ),
        isFalse,
      );
    });
  });
}
