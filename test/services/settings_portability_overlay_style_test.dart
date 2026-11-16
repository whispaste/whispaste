/// Import of an export file from before the overlay presets (ticket, ADR 0024).
///
/// A file that still carries `overlay_style` must map it onto the preset keys
/// instead of silently keeping the current look.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/settings_portability_service.dart';

String _file(Map<String, String> settings) =>
    '{"format_version":2,"settings":${_json(settings)},"replacements":[]}';

String _json(Map<String, String> settings) =>
    '{${settings.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}';

void main() {
  group('settings import of overlay_style', () {
    final current = AppSettings.fromStorageMap({
      'overlay_background': 'graphit',
      'overlay_wave': 'violett',
    });

    test('an old glass or solid file maps to marine with cyan', () {
      const service = SettingsPortabilityService();
      for (final style in ['glass', 'solid']) {
        final bundle = service.decode(_file({'overlay_style': style}));
        final merged = mergeImportedSettings(current, bundle.settings);
        expect(merged.overlay.overlayBackground, 'marine', reason: style);
        expect(merged.overlay.overlayWave, 'cyan', reason: style);
        expect(merged.toStorageMap().containsKey('overlay_style'), isFalse);
      }
    });

    test('a file with explicit preset keys wins over overlay_style', () {
      const service = SettingsPortabilityService();
      final bundle = service.decode(
        _file({'overlay_style': 'solid', 'overlay_background': 'gletscher'}),
      );
      final merged = mergeImportedSettings(current, bundle.settings);
      expect(merged.overlay.overlayBackground, 'gletscher');
    });

    test('an unknown legacy style falls back to marine and cyan', () {
      const service = SettingsPortabilityService();
      final bundle = service.decode(_file({'overlay_style': 'mint'}));
      final merged = mergeImportedSettings(current, bundle.settings);
      expect(merged.overlay.overlayBackground, 'marine');
      expect(merged.overlay.overlayWave, 'cyan');
    });
  });
}
