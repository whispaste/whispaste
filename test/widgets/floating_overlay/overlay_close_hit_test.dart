import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/floating_overlay_render_entrypoint.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';

FloatingOverlaySnapshot _snap({
  OverlaySizeVariant size = OverlaySizeVariant.normal,
  bool showCancel = true,
  bool visible = true,
}) => FloatingOverlaySnapshot(
  visible: visible,
  state: OverlayVisualState.recording,
  label: '',
  size: size,
  appearance: OverlayAppearance(showCancel: showCancel),
);

void main() {
  // The X centre as the painter derives it: pill.left + padH + closeOffset.
  Offset xCenter(OverlaySizeVariant v) {
    final spec = OverlayDesignSpec.sizeFor(v);
    final layout = OverlayDesignSpec.layoutFor(v);
    return Offset(
      OverlayDesignSpec.shadowPadding + layout.padH + layout.closeOffset,
      OverlayDesignSpec.shadowPadding + spec.height / 2,
    );
  }

  group('isCloseTap', () {
    test('a tap on the X centre cancels, on every size with an X', () {
      for (final v in [OverlaySizeVariant.normal, OverlaySizeVariant.compact]) {
        expect(isCloseTap(_snap(size: v), xCenter(v)), isTrue, reason: '$v');
      }
    });

    test('the hit area is at least 32 x 32 around the X', () {
      final c = xCenter(OverlaySizeVariant.compact);
      final s = _snap(size: OverlaySizeVariant.compact);
      expect(isCloseTap(s, c + const Offset(15, 15)), isTrue);
      expect(isCloseTap(s, c + const Offset(-15, -15)), isTrue);
    });

    test('a tap on the pill body or far from the X toggles instead', () {
      final s = _snap();
      final size = OverlayDesignSpec.windowSizeFor(OverlaySizeVariant.normal);
      expect(isCloseTap(s, Offset(size.width / 2, size.height / 2)), isFalse);
      expect(isCloseTap(s, Offset(size.width - 20, size.height / 2)), isFalse);
    });

    test('no X: hidden look, disabled cancel, mini and nano stay toggles', () {
      final c = xCenter(OverlaySizeVariant.normal);
      expect(isCloseTap(_snap(showCancel: false), c), isFalse);
      expect(isCloseTap(_snap(visible: false), c), isFalse);
      for (final v in [OverlaySizeVariant.mini, OverlaySizeVariant.nano]) {
        expect(isCloseTap(_snap(size: v), xCenter(v)), isFalse, reason: '$v');
      }
    });
  });
}
