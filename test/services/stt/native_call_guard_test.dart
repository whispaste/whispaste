/// Host-local test for [NativeCallGuard] against the REAL `wp_ffi_guard`
/// staged by `scripts/build-libwhisper-macos.sh` (`-linux.sh`, or the
/// Windows steps in BUILD.md) into `.build/libwhisper/<os>/`. Gitignored,
/// host-local artifact, so the test SKIPS where it is missing (CI, fresh
/// checkouts) — same pattern as
/// `smart_mode_shim_integration_test.dart`.
///
/// The self-test hook throws from an extern "C" function compiled like the
/// third-party libraries; called directly from Dart it aborts the whole
/// test process (Windows: 0xC0000409, the Sentry 140866975 signature).
/// Through the guard it must surface as a [NativeCallException].
///
/// Optional end-to-end part: with a whisper model at
/// `.build/test-models/whisper/ggml-tiny.bin`, a real [WhisperFfiEngine]
/// loads and decodes through the guard.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/headless/package_diagnose.dart'
    show selfCheckNativeCallGuard;
import 'package:whispaste/services/stt/native_call_guard.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_resilience_policy.dart';

String? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'native', 'ffi_guard')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

void main() {
  group('nativeInferenceFailure', () {
    final caught = NativeCallException(
      -1,
      'vk::Queue::submit: ErrorDeviceLost',
    );

    test('on a GPU backend it triggers the notifier\'s CPU retry', () {
      final e = nativeInferenceFailure(
        'whisper_full',
        caught,
        WhisperBackend.vulkan,
      );
      expect(e.kind, WhisperFailureKind.gpuCrash);
      expect(const WhisperResiliencePolicy().shouldRetryOnCpu(e.kind), isTrue);
      expect(e.message, contains('ErrorDeviceLost'));
    });

    test('on CPU it is surfaced, not retried', () {
      final e = nativeInferenceFailure(
        'whisper_full',
        caught,
        WhisperBackend.cpu,
      );
      expect(e.kind, WhisperFailureKind.other);
    });
  });

  final root = _repoRoot();
  final stageDir = root == null
      ? null
      : p.join(
          root,
          '.build',
          'libwhisper',
          Platform.isLinux
              ? 'linux'
              : Platform.isWindows
              ? 'windows'
              : 'macos',
        );
  final whisperPath = stageDir == null
      ? null
      : p.join(
          stageDir,
          Platform.isLinux
              ? 'libwhisper.so'
              : Platform.isWindows
              ? 'whisper.dll'
              : 'libwhisper.dylib',
        );
  final guardPath = whisperPath == null
      ? null
      : NativeCallGuard.pathNextTo(whisperPath);
  final available = guardPath != null && File(guardPath).existsSync();

  group(
    'NativeCallGuard (real wp_ffi_guard)',
    () {
      late NativeCallGuard guard;
      setUpAll(() {
        guard = NativeCallGuard.tryOpen(guardPath!)!;
      });

      test('a call that does not throw returns normally', () {
        expect(() => guard.selfTest(0), returnsNormally);
      });

      test('std::exception becomes a NativeCallException with what()', () {
        expect(
          () => guard.selfTest(1),
          throwsA(
            isA<NativeCallException>()
                .having((e) => e.code, 'code', -1)
                .having((e) => e.message, 'message', 'wpg selftest'),
          ),
        );
      });

      test('a non-std exception becomes a NativeCallException', () {
        expect(
          () => guard.selfTest(2),
          throwsA(
            isA<NativeCallException>()
                .having((e) => e.code, 'code', -2)
                .having((e) => e.message, 'message', 'unknown C++ exception'),
          ),
        );
      });

      test('the process keeps working after a caught exception', () {
        for (var i = 0; i < 50; i++) {
          expect(() => guard.selfTest(1), throwsA(isA<NativeCallException>()));
        }
        expect(() => guard.selfTest(0), returnsNormally);
      });

      test('was built against the bundled whisper.h struct layouts', () {
        expect(guard.supportsWhisperStructs, isTrue);
      });

      test('passes the --diagnose self-check', () {
        expect(() => selfCheckNativeCallGuard(guardPath!), returnsNormally);
      });
    },
    skip: available
        ? false
        : 'wp_ffi_guard not built (scripts/build-libwhisper-macos.sh)',
  );

  final modelPath = root == null
      ? null
      : p.join(root, '.build', 'test-models', 'whisper', 'ggml-tiny.bin');
  final modelAvailable =
      available && modelPath != null && File(modelPath).existsSync();

  test(
    'WhisperFfiEngine loads and decodes through the guard',
    () async {
      final engine = WhisperFfiEngine(libraryPath: whisperPath);
      await engine.load(modelPath: modelPath!);
      addTearDown(engine.unload);
      expect(engine.usesNativeCallGuard, isTrue);
      // Real speech: a corrupted params copy would crash, return non-zero
      // or ignore `language`/`no_timestamps` instead of producing text.
      final wav = File(
        p.join(
          root!,
          'packages',
          'whispaste_gpu_probe',
          'assets',
          'reference_short.wav',
        ),
      ).readAsBytesSync();
      final text = await engine.transcribe(wav, language: 'en');
      expect(text.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: modelAvailable
        ? false
        : 'needs wp_ffi_guard + .build/test-models/whisper/ggml-tiny.bin',
  );
}
