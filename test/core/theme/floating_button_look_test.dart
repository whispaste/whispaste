// Unit tests for the ticket floating button look (overlay_customization.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';

void main() {
  group('FloatingButtonLook.fromValues', () {
    test('defaults match today\'s button', () {
      final look = FloatingButtonLook.fromValues();
      expect(look, FloatingButtonLook.defaults);
      expect(look.diameter, 56);
      expect(look.square, isFalse);
      expect(look.ring, isTrue);
      expect(look.idleAlpha, 1.0);
    });

    test('unknown stored values take the defaults', () {
      final look = FloatingButtonLook.fromValues(
        size: 'huge',
        shape: 'hexagon',
        idleOpacity: '55',
      );
      expect(look.size, 'medium');
      expect(look.square, isFalse);
      expect(look.idleOpacity, '100');
    });
  });

  group('theme payload', () {
    test(
      'toThemeMap sends shape, ring, the resting fraction and the capsule',
      () {
        final map = const FloatingButtonLook(
          square: true,
          ring: false,
          idleOpacity: '70',
        ).toThemeMap();
        expect(map, {
          'shape': 'square',
          'ring': false,
          'idleOpacity': 0.7,
          'idleCapsule': false,
        });
      },
    );

    test('fromThemeMap reads what toThemeMap writes', () {
      const look = FloatingButtonLook(
        square: true,
        ring: false,
        idleOpacity: '40',
      );
      final back = FloatingButtonLook.fromThemeMap(look.toThemeMap());
      expect(back.square, isTrue);
      expect(back.ring, isFalse);
      expect(back.idleOpacity, '40');
    });

    test('fromThemeMap reads the idle capsule', () {
      const look = FloatingButtonLook(idleCapsule: true);
      expect(
        FloatingButtonLook.fromThemeMap(look.toThemeMap()).idleCapsule,
        isTrue,
      );
    });

    test('fromThemeMap falls back for a missing or odd payload', () {
      final back = FloatingButtonLook.fromThemeMap({'idleOpacity': 'x'});
      expect(back.square, isFalse);
      expect(back.ring, isTrue);
      expect(back.idleOpacity, '100');
    });
  });

  group('OverlaySettings persistence', () {
    test('the four button keys round-trip through the map', () {
      const settings = OverlaySettings(
        floatingButtonSize: 'large',
        floatingButtonShape: 'square',
        floatingButtonRing: false,
        floatingButtonIdleOpacity: '70',
      );
      final back = OverlaySettings.fromMap(
        settings.toMap().map((k, v) => MapEntry(k, v)),
      );
      expect(back, settings);
    });

    test('missing keys keep the defaults', () {
      final s = OverlaySettings.fromMap(const {});
      expect(s.floatingButtonSize, 'medium');
      expect(s.floatingButtonShape, 'round');
      expect(s.floatingButtonRing, isTrue);
      expect(s.floatingButtonIdleOpacity, '100');
    });
  });
}
