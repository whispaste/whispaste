/// Persistence of the overlay theme presets (WP-75, ADR 0024).
///
/// The old `overlay_style` (glass/solid) key is no longer written. Both of
/// its values rendered the same opaque fill, so both map to marine (ADR 0024).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('overlay theme settings', () {
    test('defaults are amber background and ink wave (2026-10-29)', () {
      final settings = AppSettings.defaults;
      expect(settings.overlay.overlayBackground, 'amber');
      expect(settings.overlay.overlayWave, 'ink');
      expect(settings.overlayBackgroundType, OverlayBackground.amber);
      expect(settings.overlayWaveType, OverlayWave.ink);
    });

    test('upgrade: legacy glass and solid both map to marine with cyan', () {
      for (final style in ['glass', 'solid']) {
        final settings = AppSettings.fromStorageMap({'overlay_style': style});
        expect(settings.overlay.overlayBackground, 'marine', reason: style);
        expect(settings.overlay.overlayWave, 'cyan', reason: style);
      }
    });

    test('upgrade: an explicit overlay_background wins over overlay_style', () {
      final settings = AppSettings.fromStorageMap({
        'overlay_style': 'solid',
        'overlay_background': 'graphit',
      });
      expect(settings.overlay.overlayBackground, 'graphit');
      expect(settings.overlay.overlayWave, 'cyan');
    });

    test('upgrade: an unknown legacy style falls back to marine and cyan', () {
      final settings = AppSettings.fromStorageMap({'overlay_style': 'mint'});
      expect(settings.overlay.overlayBackground, 'marine');
      expect(settings.overlay.overlayWave, 'cyan');
    });

    test('the legacy key is not written any more', () {
      final map = AppSettings.fromStorageMap({
        'overlay_style': 'solid',
      }).toStorageMap();
      expect(map.containsKey('overlay_style'), isFalse);
      expect(map['overlay_background'], 'marine');
      expect(map['overlay_wave'], 'cyan');
    });

    test('new keys round-trip', () {
      final settings = AppSettings.fromStorageMap({
        'overlay_background': 'gletscher',
        'overlay_wave': 'violett',
      });
      expect(settings.overlayBackgroundType, OverlayBackground.gletscher);
      expect(settings.overlayWaveType, OverlayWave.violett);
      final map = settings.toStorageMap();
      expect(map['overlay_background'], 'gletscher');
      expect(map['overlay_wave'], 'violett');
    });

    test('an unknown stored value falls back to the default preset', () {
      final settings = AppSettings.fromStorageMap({
        'overlay_background': 'petrol',
        'overlay_wave': 'plaid',
      });
      expect(settings.overlayBackgroundType, OverlayBackground.marine);
      expect(settings.overlayWaveType, OverlayWave.cyan);
    });
  });
}
