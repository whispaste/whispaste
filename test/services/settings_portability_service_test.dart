/// Tests for [SettingsPortabilityService] — encode/decode + file IO for the
/// Custom Vocabulary / Text Replacements / Hotkey export-import bundle.
///
/// Uses `MemoryFileSystem` (same seam as `FactoryResetCoordinator`) so no
/// real disk IO happens in tests.
library;

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/settings_portability_service.dart';

void main() {
  late MemoryFileSystem fs;
  late SettingsPortabilityService service;

  setUp(() {
    fs = MemoryFileSystem.test();
    service = SettingsPortabilityService(fileSystem: fs);
  });

  const sampleBundle = SettingsExportBundle(
    customVocabulary: 'Silvio, WhisPaste, Whispaste',
    hotkey: HotkeySettings(
      hotkeyEnabled: true,
      hotkeyKey: 'F',
      hotkeyKeyDisplay: 'F',
      hotkeyModifiers: 'ctrl+alt',
    ),
    replacements: [
      Replacement(
        id: 'a',
        triggers: ['mfg', 'mfg2'],
        replacement: 'Mit freundlichen Grüßen',
      ),
      Replacement(id: 'b', triggers: ['lg'], replacement: 'Liebe Grüße'),
    ],
  );

  // ---------------------------------------------------------------------------
  // AC1: export writes a JSON file containing all three areas.
  // ---------------------------------------------------------------------------

  test(
    'exportToFile writes JSON containing custom vocabulary, hotkey, and replacements',
    () async {
      await service.exportToFile('/exports/settings.json', sampleBundle);

      final written = await fs.file('/exports/settings.json').readAsString();
      expect(written, contains('"custom_vocabulary"'));
      expect(written, contains('Silvio, WhisPaste, Whispaste'));
      expect(written, contains('"hotkey"'));
      expect(written, contains('ctrl+alt'));
      expect(written, contains('"replacements"'));
      expect(written, contains('"triggers"'));
      expect(written, contains('mfg'));
      expect(written, contains('mfg2'));
      expect(written, contains('Mit freundlichen Grüßen'));
    },
  );

  // ---------------------------------------------------------------------------
  // AC2: import restores all three areas from the file.
  // ---------------------------------------------------------------------------

  test(
    'importFromFile restores customVocabulary, hotkey, and replacements',
    () async {
      await service.exportToFile('/exports/settings.json', sampleBundle);

      final restored = await service.importFromFile('/exports/settings.json');

      expect(restored.customVocabulary, sampleBundle.customVocabulary);
      expect(restored.hotkey, sampleBundle.hotkey);
      expect(
        restored.replacements,
        hasLength(sampleBundle.replacements.length),
      );
      for (var i = 0; i < sampleBundle.replacements.length; i++) {
        expect(
          restored.replacements[i].triggers,
          sampleBundle.replacements[i].triggers,
        );
        expect(
          restored.replacements[i].replacement,
          sampleBundle.replacements[i].replacement,
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // AC3: round-trip export → import yields an identical configuration.
  // ---------------------------------------------------------------------------

  test(
    'round trip: export then import yields identical configuration',
    () async {
      const bundle = SettingsExportBundle(
        customVocabulary: 'Kubernetes, Terraform',
        hotkey: HotkeySettings(
          hotkeyEnabled: false,
          hotkeyKey: ';',
          hotkeyKeyDisplay: 'Ö',
          hotkeyModifiers: 'meta+shift',
        ),
        replacements: [
          Replacement(
            id: 'x',
            triggers: ['tel', 'telefon'],
            replacement: '+49 123 456789',
          ),
        ],
      );

      await service.exportToFile('/roundtrip.json', bundle);
      final restored = await service.importFromFile('/roundtrip.json');

      expect(restored.customVocabulary, bundle.customVocabulary);
      expect(restored.hotkey, bundle.hotkey);
      expect(restored.replacements, hasLength(bundle.replacements.length));
      for (var i = 0; i < bundle.replacements.length; i++) {
        expect(
          restored.replacements[i].triggers,
          bundle.replacements[i].triggers,
        );
        expect(
          restored.replacements[i].replacement,
          bundle.replacements[i].replacement,
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Backward compatibility: importing an old-format export (single "trigger"
  // string per replacement, published before multi-trigger support).
  // ---------------------------------------------------------------------------

  test(
    'importFromFile reads old-format single "trigger" exports without throwing',
    () async {
      await fs
          .file('/legacy.json')
          .writeAsString(
            jsonEncode({
              'format_version': 1,
              'custom_vocabulary': 'Legacy',
              'hotkey': const HotkeySettings().toMap(),
              'replacements': [
                {'trigger': 'mfg', 'replacement': 'Mit freundlichen Grüßen'},
              ],
            }),
          );

      final restored = await service.importFromFile('/legacy.json');

      expect(restored.replacements, hasLength(1));
      expect(restored.replacements.single.triggers, ['mfg']);
      expect(
        restored.replacements.single.replacement,
        'Mit freundlichen Grüßen',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Error handling: malformed import file.
  // ---------------------------------------------------------------------------

  test(
    'importFromFile throws SettingsImportFormatException for invalid JSON',
    () async {
      await fs.file('/broken.json').writeAsString('not json at all');

      expect(
        () => service.importFromFile('/broken.json'),
        throwsA(isA<SettingsImportFormatException>()),
      );
    },
  );

  test(
    'importFromFile throws SettingsImportFormatException when required fields are missing',
    () async {
      await fs
          .file('/incomplete.json')
          .writeAsString('{"custom_vocabulary": "x"}');

      expect(
        () => service.importFromFile('/incomplete.json'),
        throwsA(isA<SettingsImportFormatException>()),
      );
    },
  );

  test(
    'importFromFile throws SettingsImportFileNotFoundException for a missing file',
    () async {
      expect(
        () => service.importFromFile('/does-not-exist.json'),
        throwsA(isA<SettingsImportFileNotFoundException>()),
      );
    },
  );
}
