/// Regression test for ggml's process-wide log hook across worker isolates
/// (WP-48). [WhisperIsolateEngine] runs libwhisper in a worker isolate; the
/// hook used to be registered from inside that worker. Once the worker shut
/// down, ggml still held the pointer to the closed `NativeCallable`, and the
/// next native log line aborted the VM ("Callback invoked after it has been
/// deleted"). The hook now lives in the main isolate, which outlives workers.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/whisper/whisper_bindings.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_isolate_engine.dart';

/// Walks up from the test cwd to the repo root (the dir holding
/// `.build/whisper-ffi-durchstich`).
String? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (Directory(
      p.join(dir.path, '.build', 'whisper-ffi-durchstich'),
    ).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

void main() {
  final root = _repoRoot();
  final dylibPath = root == null
      ? null
      : p.join(
          root,
          '.build',
          'whisper-ffi-durchstich',
          'src',
          'libwhisper.dylib',
        );
  final available = dylibPath != null && File(dylibPath).existsSync();

  group(
    'ggml log hook across worker isolates',
    () {
      test(
        'native logs after the worker was shut down do not abort the process',
        () async {
          final dir = Directory.systemTemp.createTempSync('whisper_log_hook_');
          addTearDown(() => dir.deleteSync(recursive: true));
          // A model file that exists but is not a model: the worker gets as
          // far as native init (after backend and log setup) and fails there.
          final bogusModel = File(p.join(dir.path, 'bogus.bin'))
            ..writeAsBytesSync([0, 1, 2, 3]);

          final engine = WhisperIsolateEngine(
            libraryPath: dylibPath,
            backend: WhisperBackend.cpu,
          );
          await expectLater(
            engine.load(modelPath: bogusModel.path),
            throwsA(isA<StateError>()),
          );
          await engine.shutdown();

          // A native call that logs through ggml, made after the worker is
          // gone. Before the fix this aborted the test process.
          final bindings = WhisperBindings.fromLookup(
            ffi.DynamicLibrary.open(dylibPath!).lookup,
          );
          final missing = p.join(dir.path, 'missing.bin').toNativeUtf8();
          addTearDown(() => malloc.free(missing));
          final ctx = bindings.whisper_init_from_file_with_params(
            missing.cast<ffi.Char>(),
            bindings.whisper_context_default_params(),
          );
          expect(ctx, ffi.nullptr);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'a second worker loads after the first one was shut down',
        () async {
          final dir = Directory.systemTemp.createTempSync('whisper_log_hook_');
          addTearDown(() => dir.deleteSync(recursive: true));
          final bogusModel = File(p.join(dir.path, 'bogus.bin'))
            ..writeAsBytesSync([0, 1, 2, 3]);

          for (var round = 0; round < 2; round++) {
            final engine = WhisperIsolateEngine(
              libraryPath: dylibPath,
              backend: WhisperBackend.cpu,
            );
            await expectLater(
              engine.load(modelPath: bogusModel.path),
              throwsA(isA<StateError>()),
            );
            await engine.shutdown();
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: available
        ? false
        : 'needs .build/whisper-ffi-durchstich/src/libwhisper.dylib',
  );
}
