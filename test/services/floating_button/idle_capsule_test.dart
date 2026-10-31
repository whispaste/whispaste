import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/idle_capsule.dart';

void main() {
  group('IdleCapsule', () {
    test('expands on hover where hover is supported', () {
      final supported = IdleCapsule.hoverSupported(
        isLinux: false,
        isWayland: false,
      );
      expect(
        IdleCapsule.expands(hovered: true, hoverSupported: supported),
        isTrue,
      );
      expect(
        IdleCapsule.expands(hovered: false, hoverSupported: supported),
        isFalse,
      );
    });

    test('stays at rest under Wayland, where no hover is tracked', () {
      final supported = IdleCapsule.hoverSupported(
        isLinux: true,
        isWayland: true,
      );
      expect(supported, isFalse);
      expect(
        IdleCapsule.expands(hovered: true, hoverSupported: supported),
        isFalse,
      );
    });

    test('X11 on Linux keeps hover', () {
      expect(
        IdleCapsule.hoverSupported(isLinux: true, isWayland: false),
        isTrue,
      );
    });

    test('the pill is larger than the resting capsule in both dimensions', () {
      expect(IdleCapsule.hoverWidth, greaterThan(IdleCapsule.idleWidth));
      expect(IdleCapsule.hoverHeight, greaterThan(IdleCapsule.idleHeight));
    });
  });
}
