import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_bindings.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_engine.dart';

/// Real libparakeet tests. They skip unless both the library and a GGUF model
/// are present:
///  - library: `.build/libwhisper/macos/libparakeet.dylib`, produced by
///    `scripts/build-libwhisper-macos.sh`
///  - model: the path in the `WP_PARAKEET_GGUF` environment variable
/// Without the library they skip silently, like `confirmBackendForTesting` in
/// the whisper tests.
String? _libraryPath() {
  final candidates = [
    '.build/libwhisper/macos/libparakeet.dylib',
    '.build/libwhisper/linux/libparakeet.so',
  ];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f.absolute.path;
  }
  return null;
}

String? _modelPath() {
  final p = Platform.environment['WP_PARAKEET_GGUF'];
  if (p == null || p.isEmpty || !File(p).existsSync()) return null;
  return p;
}

void main() {
  test('struct layout matches parakeet_full_params on 64-bit targets', () {
    if (ffi.sizeOf<ffi.IntPtr>() != 8) return;
    // 4 ints (strategy, n_threads, offset_ms, duration_ms) + bool + int
    // with natural alignment, then 10 pointers: 104 bytes in total.
    expect(ffi.sizeOf<ParakeetFullParams>(), 104);
    expect(ffi.sizeOf<ParakeetContextParams>(), 8);
  });

  group('real libparakeet', () {
    final lib = _libraryPath();
    final model = _modelPath();
    final skip = lib == null
        ? 'libparakeet not built (scripts/build-libwhisper-macos.sh)'
        : model == null
        ? 'set WP_PARAKEET_GGUF to a verified GGUF file'
        : null;

    test(
      'loads the library, reports its version and runs a silent clip',
      () async {
        final bindings = ParakeetBindings(ffi.DynamicLibrary.open(lib!));
        expect(bindings.version(), isNotEmpty);

        final engine = await ParakeetGpuEngine.open(
          libraryPath: lib,
          modelPath: model!,
          threads: 4,
        );
        addTearDown(engine.close);
        expect(engine.device, isNotEmpty);

        final text = await engine.transcribe(
          Float32List(16000 * 2),
          timeout: const Duration(seconds: 60),
        );
        // Silence may or may not produce text; the call must complete.
        expect(text, isA<String>());
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a timeout aborts the native call through abort_callback',
      () async {
        final engine = await ParakeetGpuEngine.open(
          libraryPath: lib!,
          modelPath: model!,
          threads: 4,
        );
        addTearDown(engine.close);
        // 60 s of audio with a 1 ms budget: the flag is set long before the
        // encoder finishes, so the call must fail instead of running on.
        await expectLater(
          engine.transcribe(
            Float32List(16000 * 60),
            timeout: const Duration(milliseconds: 1),
          ),
          throwsA(isA<ParakeetGpuException>()),
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
