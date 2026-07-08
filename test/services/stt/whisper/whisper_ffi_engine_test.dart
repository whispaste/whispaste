/// Engine-level test for the real [WhisperFfiEngine] over the seam.
///
/// Loads the locally built `libwhisper.dylib` and the tiny GGML model produced
/// by the Issue-01 durchstich setup, then transcribes a real-speech fixture.
/// Those artifacts are gitignored and host-local (built via CMake, see Issue
/// 01) — on CI / other hosts they are absent, so the test SKIPS gracefully
/// rather than failing. Real cross-platform bundling is Issue 11.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

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
  final build = root == null
      ? null
      : p.join(root, '.build', 'whisper-ffi-durchstich');
  final dylibPath = build == null
      ? null
      : p.join(build, 'src', 'libwhisper.dylib');
  final modelPath = build == null
      ? null
      : p.join(build, 'models', 'ggml-tiny.bin');
  final speechWavPath = build == null
      ? null
      : p.join(build, 'fixtures', 'hello_world_speech.wav');

  final available =
      dylibPath != null &&
      File(dylibPath).existsSync() &&
      File(modelPath!).existsSync() &&
      File(speechWavPath!).existsSync();

  group(
    'WhisperFfiEngine (real libwhisper)',
    () {
      test(
        'transcribes the fixture WAV in-process over the seam',
        () async {
          final engine = WhisperFfiEngine(libraryPath: dylibPath);
          expect(engine.status.isLoaded, isFalse);

          await engine.load(modelPath: modelPath!);
          addTearDown(engine.unload);
          expect(engine.status.isLoaded, isTrue);

          final wavBytes = File(speechWavPath!).readAsBytesSync();
          final text = (await engine.transcribe(
            wavBytes,
            language: 'en',
          )).toLowerCase();

          expect(text, contains('hello'));
          expect(text, contains('world'));
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test('throws when transcribing before load', () {
        final engine = WhisperFfiEngine(libraryPath: dylibPath);
        expect(
          () => engine.transcribe(const [0, 1, 2]),
          throwsA(isA<StateError>()),
        );
      });
    },
    skip: available ? null : 'local libwhisper.dylib + tiny model absent',
  );

  // Host-independent error path (no dylib/model required): a missing model
  // surfaces via status.errorMessage without loading.
  test('surfaces a missing-model error via status.errorMessage', () async {
    final engine = WhisperFfiEngine(libraryPath: '/nonexistent/libwhisper');

    expect(
      () => engine.load(modelPath: '/nonexistent/model.bin'),
      throwsA(isA<StateError>()),
    );

    expect(engine.status.isLoaded, isFalse);
    expect(engine.status.errorMessage, 'whisper_model_not_found');
  });
}
