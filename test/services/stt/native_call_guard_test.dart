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

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/headless/package_diagnose.dart'
    show selfCheckNativeCallGuard;
import 'package:whispaste/services/stt/native_call_guard.dart';
import 'package:whispaste/services/stt/whisper/whisper_bindings.dart';
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

      test('abort-flag callback reports whether the flag is raised', () {
        final cb = guard.abortFlagCallback!
            .asFunction<bool Function(ffi.Pointer<ffi.Void>)>();
        final flag = calloc<ffi.Int32>();
        addTearDown(() => calloc.free(flag));
        expect(cb(flag.cast()), isFalse);
        flag.value = 1;
        expect(cb(flag.cast()), isTrue);
        expect(cb(ffi.nullptr), isFalse);
      });

      test('a throwing void() backend call becomes a NativeCallException', () {
        expect(
          () => guard.callVoid(guard.selfTestThrowVoid),
          throwsA(isA<NativeCallException>().having((e) => e.code, 'code', -1)),
        );
      });

      test('a throwing void(cstr) backend call carries what()', () {
        expect(
          () => guard.callVoidCString(guard.selfTestThrowCString, 'vk'),
          throwsA(
            isA<NativeCallException>().having(
              (e) => e.message,
              'message',
              'wpg selftest: vk',
            ),
          ),
        );
      });

      test(
        'a throwing ptr(cstr) backend call (ggml_backend_load) is caught',
        () {
          expect(
            () => guard.callPtrCString(guard.selfTestThrowPtrCString, 'x.so'),
            throwsA(isA<NativeCallException>()),
          );
        },
      );

      test(
        'process flags are shared by every isolate of the process',
        () async {
          guard.setProcessFlag(WpgFlag.backends, 2);
          addTearDown(() => guard.setProcessFlag(WpgFlag.backends, 0));
          final seen = await _processFlagInIsolate(
            guardPath!,
            WpgFlag.backends,
          );
          expect(seen, 2);
        },
      );

      test('log lines pushed from another isolate are popped here', () async {
        // Simulates ggml logging from a worker isolate that has already ended:
        // the sink is native, so no Dart callback can be invoked late.
        await _pushLogInIsolate(guardPath!, 3, 'from worker\n');
        final lines = guard.drainLog();
        expect(
          lines.any((l) => l.level == 3 && l.text == 'from worker'),
          isTrue,
        );
      });

      test('the log ring drops the oldest lines when full and counts them', () {
        guard.drainLog();
        guard.takeDroppedLogLines();
        for (var i = 0; i < 300; i++) {
          guard.pushLogLineForTesting(2, 'line $i');
        }
        final lines = guard.drainLog();
        expect(lines.length, lessThanOrEqualTo(256));
        expect(lines.last.text, 'line 299');
        expect(guard.takeDroppedLogLines(), greaterThanOrEqualTo(44));
      });

      test('backendScore: a missing module scores 0 without a crash', () {
        expect(
          guard.backendScore(
            p.join(Directory.systemTemp.path, 'wpg_no_such_module.so'),
          ),
          0,
        );
      });

      test('backendScore: a library without ggml_backend_score scores 1', () {
        expect(guard.backendScore(guardPath!), 1);
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

  test(
    'whisper_log_set through the guard routes ggml errors into the ring',
    () {
      final bindings = WhisperBindings.fromLookup(
        ffi.DynamicLibrary.open(whisperPath!).lookup,
      );
      final guard = NativeCallGuard.tryOpen(guardPath!)!;
      final setFn = ffi.DynamicLibrary.open(
        whisperPath,
      ).lookup<ffi.Void>('whisper_log_set');
      guard.installLogSink(setFn);
      guard.drainLog();
      final missing = p.join(Directory.systemTemp.path, 'wpg_missing.bin');
      final path = missing.toNativeUtf8();
      addTearDown(() => malloc.free(path));
      final ctx = bindings.whisper_init_from_file_with_params(
        path.cast<ffi.Char>(),
        bindings.whisper_context_default_params(),
      );
      expect(ctx, ffi.nullptr);
      expect(guard.drainLog(), isNotEmpty);
    },
    skip: available ? false : 'wp_ffi_guard not built',
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

// Top-level helpers so the isolate closures capture only the path: a closure
// created inside a test body would carry the test's context, which holds the
// guard and its DynamicLibrary, and those cannot cross an isolate boundary.
Future<int> _processFlagInIsolate(String path, int flag) =>
    Isolate.run(() => NativeCallGuard.tryOpen(path)!.processFlag(flag));

Future<void> _pushLogInIsolate(String path, int level, String text) =>
    Isolate.run(
      () => NativeCallGuard.tryOpen(path)!.pushLogLineForTesting(level, text),
    );
