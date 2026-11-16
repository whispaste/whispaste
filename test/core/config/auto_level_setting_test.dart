/// Automatic level and manual input volume settings (#1611): the additive
/// `auto_level` key, its derivation for settings and exports written before
/// it, and the bounds of `input_gain` on read and import.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/settings_portability_service.dart';

AudioInputSettings _read(Map<String, String> map) =>
    AudioInputSettings.fromMap(map);

void main() {
  group('auto_level', () {
    test('is on for a new install', () {
      expect(AppSettings.defaults.audioInput.autoLevel, isTrue);
      expect(AppSettings.fromStorageMap({}).audioInput.autoLevel, isTrue);
    });

    test('is on for existing settings with the default 1.0', () {
      expect(_read({'input_gain': '1.0'}).autoLevel, isTrue);
    });

    test('stays off for existing settings with an own value', () {
      final read = _read({'input_gain': '1.6'});
      expect(read.autoLevel, isFalse);
      expect(read.inputGain, 1.6);
      expect(_read({'input_gain': '0.0'}).autoLevel, isFalse);
    });

    test('a stored value wins over the derivation and round-trips', () {
      expect(
        _read({'input_gain': '1.6', 'auto_level': 'true'}).autoLevel,
        isTrue,
      );
      expect(
        _read({'input_gain': '1.0', 'auto_level': 'false'}).autoLevel,
        isFalse,
      );
      final off = AppSettings.defaults.copyWithSections(
        audioInput: AudioInputSettings.defaults.copyWith(autoLevel: false),
      );
      expect(
        AppSettings.fromStorageMap(off.toStorageMap()).audioInput.autoLevel,
        isFalse,
      );
    });
  });

  group('input_gain bounds', () {
    test('NaN, infinity and garbage fall back to 1.0', () {
      for (final raw in ['NaN', 'Infinity', '-Infinity', 'loud', '']) {
        expect(readInputGain(raw), 1.0, reason: raw);
      }
      expect(readInputGain(null), 1.0);
    });

    test('zero and negative values become the minimum, never silence', () {
      final min = readInputGain('0.0');
      expect(min, closeTo(0.2512, 0.0001));
      expect(readInputGain('-2'), min);
    });

    test('a huge value becomes the +18 dB maximum', () {
      expect(readInputGain('50'), closeTo(7.943, 0.001));
    });

    test('values inside the range are kept as they are', () {
      expect(readInputGain('1.6'), 1.6);
      expect(readInputGain('0.5'), 0.5);
    });
  });

  group('import', () {
    test('an imported out-of-range gain is bounded', () {
      final merged = mergeImportedSettings(AppSettings.defaults, {
        'input_gain': 'NaN',
      });
      expect(merged.audioInput.inputGain, 1.0);
      final loud = mergeImportedSettings(AppSettings.defaults, {
        'input_gain': '50',
      });
      expect(loud.audioInput.inputGain, closeTo(7.943, 0.001));
    });

    test('an older file with an own gain imports the manual mode', () {
      final merged = mergeImportedSettings(AppSettings.defaults, {
        'input_gain': '2.0',
      });
      expect(merged.audioInput.autoLevel, isFalse);
      expect(merged.audioInput.inputGain, 2.0);
    });

    test('an older file with the default gain imports the automatic mode', () {
      final current = AppSettings.defaults.copyWithSections(
        audioInput: AudioInputSettings.defaults.copyWith(
          autoLevel: false,
          inputGain: 2.0,
        ),
      );
      final merged = mergeImportedSettings(current, {'input_gain': '1.0'});
      expect(merged.audioInput.autoLevel, isTrue);
    });

    test('a file with auto_level keeps its own choice', () {
      final merged = mergeImportedSettings(AppSettings.defaults, {
        'input_gain': '2.0',
        'auto_level': 'true',
      });
      expect(merged.audioInput.autoLevel, isTrue);
    });
  });
}
