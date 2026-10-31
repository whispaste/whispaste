/// Without `wp_ffi_guard` the engine loads one CPU backend module unguarded
/// (Maintainer decision 12a, 2026-10-25) so transcription runs on CPU instead of
/// failing in whisper_init. No score can be read without the guard, so the
/// module must be the baseline variant that runs on every CPU of its
/// architecture. A higher variant (AVX2, apple_m4, ...) could die with SIGILL.
/// GPU modules are never picked here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

void main() {
  group('cpuBaselineModuleFor (no guard, no score)', () {
    test('macOS picks the Apple M1 baseline, not m2/m4', () {
      expect(
        cpuBaselineModuleFor(const [
          'libggml-cpu-apple_m4.so',
          'libggml-cpu-apple_m1.so',
          'libggml-cpu-apple_m2_m3.so',
          'libggml-metal.so',
        ], os: 'macos'),
        'libggml-cpu-apple_m1.so',
      );
    });

    test('Linux picks the x64 baseline, not haswell', () {
      expect(
        cpuBaselineModuleFor(const [
          'libggml-cpu-haswell.so',
          'libggml-cpu-x64.so',
          'libggml-cuda.so',
          'libggml-vulkan.so',
        ], os: 'linux'),
        'libggml-cpu-x64.so',
      );
    });

    test('Windows picks the x64 baseline DLL', () {
      expect(
        cpuBaselineModuleFor(const [
          'ggml-cpu-x64.dll',
          'ggml-cpu-haswell.dll',
          'ggml-cuda.dll',
        ], os: 'windows'),
        'ggml-cpu-x64.dll',
      );
    });

    test('no baseline variant present gives null, never a higher one', () {
      expect(
        cpuBaselineModuleFor(const [
          'libggml-cpu-haswell.so',
          'libggml-cpu-skylakex.so',
        ], os: 'linux'),
        isNull,
      );
    });

    test('a GPU-only directory never yields a module', () {
      expect(
        cpuBaselineModuleFor(const [
          'libggml-cuda.so',
          'libggml-vulkan.so',
          'libggml-metal.so',
        ], os: 'linux'),
        isNull,
      );
    });

    test('x64 is not a macOS baseline', () {
      expect(
        cpuBaselineModuleFor(const ['libggml-cpu-x64.so'], os: 'macos'),
        isNull,
      );
    });
  });
}
