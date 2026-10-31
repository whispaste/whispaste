import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart';

void main() {
  // Bundled-library path resolution (Ticket 07, Windows parity). Mirrors
  // `whisperLibraryPathFor`'s test: host-independent for the active platform,
  // asserts the resolver points at the bundled `libsmartmode_shim` next to
  // the executable, not a bare loader-search name.
  group('smartModeLibraryPathFor', () {
    test('resolves the bundled library relative to the executable', () {
      final resolved = smartModeLibraryPathFor(
        p.join('/Apps', 'WhisPaste.app', 'Contents', 'MacOS', 'whispaste'),
      );
      expect(p.isAbsolute(resolved), isTrue);
      if (Platform.isMacOS) {
        expect(
          resolved,
          p.join(
            '/Apps',
            'WhisPaste.app',
            'Contents',
            'Frameworks',
            'libsmartmode_shim.dylib',
          ),
        );
      } else if (Platform.isWindows) {
        expect(resolved, endsWith(p.join('smart_mode', 'smartmode_shim.dll')));
      }
    });

    test('Windows: lives in a dedicated subdirectory, not the bundle root '
        '(avoids colliding with libwhisper\'s own ggml*.dll build)', () {
      final exe = p.join('C:\\', 'Program Files', 'WhisPaste', 'whispaste.exe');
      final smartModeLib = smartModeLibraryPathFor(exe);
      expect(p.dirname(smartModeLib), p.join(p.dirname(exe), 'smart_mode'));
    }, skip: Platform.isWindows ? null : 'Windows-only path shape');

    // Ticket handy-catchup/21: Linux bundles libllama under
    // `lib/smart_mode/` of the Flutter bundle — a sibling of the `lib/`
    // directory libwhisper ships in, kept disjoint for the same reason as
    // Windows' `smart_mode\` (two independently pinned ggml builds).
    test('Linux: lib/smart_mode/libsmartmode_shim.so next to the executable '
        '(disjoint from libwhisper\'s lib/)', () {
      expect(
        smartModeLibraryPathFor(
          '/opt/whispaste/whispaste',
          operatingSystem: 'linux',
        ),
        '/opt/whispaste/lib/smart_mode/libsmartmode_shim.so',
      );
    }, skip: Platform.isWindows ? 'POSIX path shape' : null);

    test('never throws for any supported desktop OS', () {
      for (final os in ['macos', 'windows', 'linux']) {
        expect(
          () => smartModeLibraryPathFor(
            '/opt/whispaste/whispaste',
            operatingSystem: os,
          ),
          returnsNormally,
          reason: os,
        );
      }
    });

    test('defaultSmartModeLibraryPath is absolute', () {
      expect(p.isAbsolute(defaultSmartModeLibraryPath()), isTrue);
    });
  });

  // Until the library ships everywhere (and for dev builds that never ran
  // the bundling step) the UI must know whether the local engine can run,
  // instead of surfacing the loader failure.
  group('isSmartModeLocalEngineAvailable', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('smart_mode_lib'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('Linux: false when the bundled shim is missing', () {
      expect(
        isSmartModeLocalEngineAvailable(
          operatingSystem: 'linux',
          libraryPath: p.join(tmp.path, 'libsmartmode_shim.so'),
        ),
        isFalse,
      );
    });

    test('Linux: true once the bundled shim exists', () {
      final lib = File(p.join(tmp.path, 'libsmartmode_shim.so'))
        ..writeAsStringSync('');
      expect(
        isSmartModeLocalEngineAvailable(
          operatingSystem: 'linux',
          libraryPath: lib.path,
        ),
        isTrue,
      );
    });

    test('macOS/Windows: always bundled (their build pipelines hard-fail '
        'without it), so no file probe', () {
      for (final os in ['macos', 'windows']) {
        expect(
          isSmartModeLocalEngineAvailable(
            operatingSystem: os,
            libraryPath: p.join(tmp.path, 'missing'),
          ),
          isTrue,
          reason: os,
        );
      }
    });
  });
}
