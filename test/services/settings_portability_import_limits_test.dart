/// WP-43a C-M-3 and C-M-5: a settings file cannot enable the automation API or
/// its hooks, and an oversized or over-long file is refused before it is
/// decoded.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/settings_portability_service.dart';

String _file({
  Map<String, String> settings = const {},
  List<Object?> replacements = const [],
}) => jsonEncode({
  'format_version': 2,
  'settings': settings,
  'replacements': replacements,
});

void main() {
  const service = SettingsPortabilityService();

  group('automation keys are never applied from a file (C-M-5)', () {
    test('automation_api_enabled and automation_hooks are dropped', () {
      final bundle = service.decode(
        _file(
          settings: {
            'automation_api_enabled': 'true',
            'automation_hooks': '[{"url":"http://127.0.0.1:9/"}]',
            'check_updates': 'true',
          },
        ),
      );
      expect(bundle.settings.containsKey('automation_api_enabled'), isFalse);
      expect(bundle.settings.containsKey('automation_hooks'), isFalse);
      expect(bundle.settings['check_updates'], 'true');
    });
  });

  group('import limits (C-M-3)', () {
    test('a file over the byte limit is refused before decoding', () {
      final big = _file(
        settings: {'custom_vocabulary': 'x' * (5 * 1024 * 1024)},
      );
      expect(
        () => service.decode(big),
        throwsA(isA<SettingsImportTooLargeException>()),
      );
    });

    test('more replacements than the entry limit are refused', () {
      final rows = [
        for (var i = 0; i < settingsImportMaxEntries + 1; i++)
          {
            'triggers': ['t$i'],
            'replacement': 'r$i',
          },
      ];
      expect(
        () => service.decode(_file(replacements: rows)),
        throwsA(isA<SettingsImportFormatException>()),
      );
    });

    test(
      'importFromFile refuses an oversized file without reading it',
      () async {
        final tmp = Directory.systemTemp.createTempSync('wp43a-settings-');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final file = File('${tmp.path}/big.json')
          ..writeAsStringSync(_file(settings: {'x': 'y' * (5 * 1024 * 1024)}));
        await expectLater(
          service.importFromFile(file.path),
          throwsA(isA<SettingsImportTooLargeException>()),
        );
      },
    );
  });
}
