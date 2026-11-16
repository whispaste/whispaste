import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_boot_state.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';

/// Handover contract between the native button shells and the button engine
/// (#977): the shells pass the last known render state as entrypoint
/// arguments, so a re-booted engine paints it in its first frame.
void main() {
  group('FloatingButtonBootState.parse', () {
    test('no boot arguments yield the empty state', () {
      final boot = FloatingButtonBootState.parse(['--floating-button']);

      expect(boot.state, isNull);
      expect(boot.diameter, isNull);
      expect(boot.theme, isNull);
    });

    test('state, diameter and theme from a re-boot are decoded', () {
      final boot = FloatingButtonBootState.parse([
        '--floating-button',
        '--button-boot-diameter=64',
        '--button-boot-state=recording',
        '--button-boot-background=marine',
        '--button-boot-wave=cyan',
        '--button-boot-shape=square',
        '--button-boot-ring=false',
        '--button-boot-idleOpacity=0.700000',
        '--button-boot-idleCapsule=true',
      ]);

      expect(boot.state, FloatingButtonVisualState.recording);
      expect(boot.diameter, 64);
      final theme = boot.theme!;
      expect(theme.background, OverlayBackground.fromValue('marine'));
      expect(theme.wave, OverlayWave.fromValue('cyan'));
      expect(theme.look.ring, isFalse);
      expect(theme.look.idleOpacity, '70');
      expect(theme.look.idleCapsule, isTrue);
    });

    test('without background and wave no theme is applied (#369 guard)', () {
      final boot = FloatingButtonBootState.parse([
        '--button-boot-state=recording',
        '--button-boot-diameter=56',
        '--button-boot-shape=square',
      ]);

      expect(boot.state, FloatingButtonVisualState.recording);
      expect(
        boot.theme,
        isNull,
        reason: 'the engine must not paint default colours before a theme',
      );
    });

    test('unknown keys and malformed values are ignored', () {
      final boot = FloatingButtonBootState.parse([
        '--button-boot-state=dancing',
        '--button-boot-diameter=wide',
        '--button-boot-future=1',
        '--button-boot-noequals',
      ]);

      expect(boot.state, isNull);
      expect(boot.diameter, isNull);
      expect(boot.theme, isNull);
    });

    test('a non-positive diameter is ignored', () {
      final boot = FloatingButtonBootState.parse(['--button-boot-diameter=0']);

      expect(boot.diameter, isNull);
    });
  });
}
