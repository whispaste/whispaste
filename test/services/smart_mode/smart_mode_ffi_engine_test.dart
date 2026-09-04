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
    test(
      'resolves the bundled library relative to the executable',
      () {
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
          expect(
            resolved,
            endsWith(p.join('smart_mode', 'smartmode_shim.dll')),
          );
        }
      },
      skip: Platform.isLinux ? kLinuxNotBundledSkipReason : null,
    );

    test('Windows: lives in a dedicated subdirectory, not the bundle root '
        '(avoids colliding with libwhisper\'s own ggml*.dll build)', () {
      final exe = p.join('C:\\', 'Program Files', 'WhisPaste', 'whispaste.exe');
      final smartModeLib = smartModeLibraryPathFor(exe);
      expect(p.dirname(smartModeLib), p.join(p.dirname(exe), 'smart_mode'));
    }, skip: Platform.isWindows ? null : 'Windows-only path shape');

    test(
      'defaultSmartModeLibraryPath is absolute',
      () {
        expect(p.isAbsolute(defaultSmartModeLibraryPath()), isTrue);
      },
      skip: Platform.isLinux ? kLinuxNotBundledSkipReason : null,
    );
  });
}

/// [smartModeLibraryPathFor] throws [UnsupportedError] on Linux by design
/// (see its doc comment) — Smart Mode's FFI engine isn't bundled there yet.
const kLinuxNotBundledSkipReason =
    'Linux: SmartModeFfiEngine is not bundled for this platform yet '
    '(see smartModeLibraryPathFor doc)';
