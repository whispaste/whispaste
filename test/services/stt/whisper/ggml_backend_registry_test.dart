/// Without `wp_ffi_guard` (not bundled, or ABI mismatch makes
/// `NativeCallGuard.tryOpen` return null) every ggml backend call must
/// report "nothing" instead of calling into native code.
library;

import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/ggml_backend_registry.dart';

void main() {
  group('GgmlBackendRegistry without the guard', () {
    const registry = GgmlBackendRegistry(null);
    final lib = ffi.DynamicLibrary.process();

    test('loading backends reports failure without calling native code', () {
      expect(registry.loadAllFromPath(lib, '/nonexistent'), isFalse);
      expect(registry.loadAll(lib), isFalse);
      expect(registry.loadModule(lib, '/nonexistent/module.so'), isNull);
    });

    test('enumeration and scoring report nothing', () {
      expect(registry.backendScore('/nonexistent/module.so'), 0);
      expect(registry.printSystemInfo(lib), isNull);
      expect(registry.devCount(lib), isNull);
    });
  });
}
