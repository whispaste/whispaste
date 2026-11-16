/// ticket: persistence of the overlay customization keys.
///
/// Defaults must keep today's look, unknown stored values must fall back to
/// it, and every key must survive a round trip.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('OverlaySettings customization defaults', () {
    test('a fresh install has a fixed outline and the other look settings', () {
      const s = OverlaySettings.defaults;
      expect(s.overlayForm, 'pill');
      expect(s.overlayWaveStyle, 'bars');
      expect(s.overlayWaveFluid, isFalse);
      expect(s.overlayShowTimer, isTrue);
      expect(s.overlayShowCancel, isTrue);
      expect(s.overlayOpacity, '100');
    });

    test('an old config without the new keys reads as the defaults', () {
      final s = OverlaySettings.fromMap({
        'show_overlay': 'true',
        'overlay_background': 'graphit',
      });
      expect(s.overlayForm, OverlaySettings.defaults.overlayForm);
      expect(s.overlayWaveStyle, OverlaySettings.defaults.overlayWaveStyle);
      expect(s.overlayWaveFluid, OverlaySettings.defaults.overlayWaveFluid);
      expect(s.overlayShowTimer, OverlaySettings.defaults.overlayShowTimer);
      expect(s.overlayShowCancel, OverlaySettings.defaults.overlayShowCancel);
      expect(s.overlayOpacity, OverlaySettings.defaults.overlayOpacity);
      expect(s.overlayBackground, 'graphit');
    });
  });

  group('OverlaySettings customization persistence', () {
    test('every new key survives toMap and fromMap', () {
      const original = OverlaySettings(
        overlayForm: 'compact-circle',
        overlayWaveStyle: 'dots',
        overlayWaveFluid: false,
        overlayShowTimer: false,
        overlayShowCancel: false,
        overlayOpacity: '60',
      );
      final restored = OverlaySettings.fromMap(original.toMap());
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('the new keys are written under their persisted names', () {
      final map = OverlaySettings.defaults.toMap();
      expect(
        map.keys,
        containsAll(<String>[
          'overlay_form',
          'overlay_wave_style',
          'overlay_wave_fluid',
          'overlay_show_timer',
          'overlay_show_cancel',
          'overlay_opacity',
        ]),
      );
    });

    test('copyWith changes only the given customization field', () {
      final changed = OverlaySettings.defaults.copyWith(
        overlayForm: 'edge-bar',
      );
      expect(changed.overlayForm, 'edge-bar');
      expect(
        changed.overlayWaveStyle,
        OverlaySettings.defaults.overlayWaveStyle,
      );
      expect(changed.overlayOpacity, OverlaySettings.defaults.overlayOpacity);
    });

    test('a changed customization field makes the settings unequal', () {
      expect(
        OverlaySettings.defaults.copyWith(overlayShowTimer: false),
        isNot(OverlaySettings.defaults),
      );
    });
  });
}
