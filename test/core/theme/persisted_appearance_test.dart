import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/theme/appearance.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/core/theme/persisted_appearance.dart';

void main() {
  late Directory tempDir;
  late File mirror;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp_appearance_mirror');
    mirror = File('${tempDir.path}/appearance');
    appearanceMirrorPathOverride = mirror.path;
  });

  tearDown(() {
    appearanceMirrorPathOverride = null;
    WpColors.activate(wpLightColors);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('appearance mirror', () {
    test('round-trips every mode', () {
      for (final mode in AppearanceMode.values) {
        writeAppearanceMirror(mode.value);
        expect(readAppearanceMirror(), mode);
      }
    });

    test('maps a legacy brand mirror to navy and rewrites it as navy', () {
      mirror.writeAsStringSync('brand');
      expect(readAppearanceMirror(), AppearanceMode.navy);

      writeAppearanceMirror('navy');
      expect(mirror.readAsStringSync(), 'navy');
    });

    test('reads navy when no mirror exists', () {
      expect(readAppearanceMirror(), AppearanceMode.navy);
    });

    test('reads navy for unknown or empty mirror content', () {
      mirror.writeAsStringSync('sepia');
      expect(readAppearanceMirror(), AppearanceMode.navy);

      mirror.writeAsStringSync('   ');
      expect(readAppearanceMirror(), AppearanceMode.navy);
    });

    test('an explicitly mirrored light stays light', () {
      writeAppearanceMirror('light');
      expect(readAppearanceMirror(), AppearanceMode.light);
    });

    test('ignores an empty or null value instead of clearing the mirror', () {
      writeAppearanceMirror('dark');
      writeAppearanceMirror(null);
      writeAppearanceMirror('');
      writeAppearanceMirror('   ');
      expect(readAppearanceMirror(), AppearanceMode.dark);
    });

    test('stores only a known mode, normalising unknown values to navy', () {
      writeAppearanceMirror('sepia');
      expect(mirror.readAsStringSync(), 'navy');
    });

    test('creates the parent directory on first write', () {
      final nested = '${tempDir.path}/does/not/exist/appearance';
      appearanceMirrorPathOverride = nested;

      writeAppearanceMirror('navy');

      expect(File(nested).existsSync(), isTrue);
      expect(readAppearanceMirror(), AppearanceMode.navy);
    });

    test('a broken mirror path never throws', () {
      // A directory where the file is expected: every read and write must
      // swallow the FileSystemException, a secondary engine must boot anyway.
      final asDirectory = '${tempDir.path}/appearance_dir';
      Directory(asDirectory).createSync();
      appearanceMirrorPathOverride = asDirectory;

      expect(() => writeAppearanceMirror('dark'), returnsNormally);
      expect(readAppearanceMirror(), AppearanceMode.navy);
    });
  });

  group('resolvePersistedAppearance', () {
    test('activates the colour set for every mode and platform brightness', () {
      for (final mode in AppearanceMode.values) {
        for (final platform in Brightness.values) {
          writeAppearanceMirror(mode.value);

          final colors = resolvePersistedAppearance(platform);

          expect(colors, same(colorsForAppearance(mode, platform)));
          expect(WpColors.current, same(colors));
        }
      }
    });

    test('system follows the platform brightness of the engine', () {
      writeAppearanceMirror('system');

      expect(resolvePersistedAppearance(Brightness.dark), same(wpDarkColors));
      expect(resolvePersistedAppearance(Brightness.light), same(wpLightColors));
    });

    test('a missing mirror activates the navy set', () {
      expect(resolvePersistedAppearance(Brightness.dark), same(wpNavyColors));
    });
  });

  group('recording overlay and floating button stay navy', () {
    test('overlay colours ignore the active colour set', () {
      final reference = OverlayDesignSpec.colorsFor();
      for (final mode in AppearanceMode.values) {
        WpColors.activate(colorsForAppearance(mode, Brightness.light));
        expect(OverlayDesignSpec.colorsFor(), equals(reference));
      }
    });

    test('overlay and button sources never read the runtime facade', () {
      final sources = <File>[
        File('lib/floating_overlay_render_entrypoint.dart'),
        File('lib/floating_button_render_entrypoint.dart'),
        ...Directory(
          'lib/widgets/floating_overlay',
        ).listSync(recursive: true).whereType<File>(),
        ...Directory(
          'lib/widgets/floating_button',
        ).listSync(recursive: true).whereType<File>(),
      ].where((f) => f.path.endsWith('.dart'));

      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(
          source.readAsStringSync(),
          isNot(contains('WpColors.')),
          reason: '${source.path} must stay on the navy WpColorsDark palette',
        );
      }
    });
  });
}
