/// Stored wave choices that are invalid on the stored background migrate when
/// settings load (WP-75b), so the render path never sees a disabled pairing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

OverlaySettings _load(Map<String, String> raw) =>
    AppSettings.fromStorageMap(raw).overlay;

void main() {
  group('stored overlay pairings migrate on load', () {
    test('ink on marine becomes neutral', () {
      final s = _load({'overlay_background': 'marine', 'overlay_wave': 'ink'});
      expect(s.overlayWave, 'neutral');
      expect(s.overlayBackground, 'marine');
    });

    test('ink on graphit becomes neutral', () {
      final s = _load({'overlay_background': 'graphit', 'overlay_wave': 'ink'});
      expect(s.overlayWave, 'neutral');
    });

    test('ink on gletscher is kept, it is valid there', () {
      final s = _load({
        'overlay_background': 'gletscher',
        'overlay_wave': 'ink',
      });
      expect(s.overlayWave, 'ink');
    });

    test('a valid stored pairing is not changed', () {
      final s = _load({'overlay_background': 'amber', 'overlay_wave': 'amber'});
      expect(s.overlayWave, 'amber');
    });

    test('an unknown stored wave still falls back to cyan', () {
      final s = _load({
        'overlay_background': 'marine',
        'overlay_wave': 'plaid',
      });
      expect(s.overlayWave, 'cyan');
    });

    test('the migrated pairing is what the typed getters report', () {
      final s = _load({'overlay_background': 'marine', 'overlay_wave': 'ink'});
      final wave = OverlayWave.fromValue(s.overlayWave);
      expect(
        wave.isValidOn(OverlayBackground.fromValue(s.overlayBackground)),
        isTrue,
      );
    });
  });
}
