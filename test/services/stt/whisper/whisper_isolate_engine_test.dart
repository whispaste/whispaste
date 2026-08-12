/// Engine-level test for [WhisperIsolateEngine] — proves the worker-isolate
/// wrapper (FLUTTER_WHISPASTE-BB) round-trips load/transcribe/unload
/// correctly across the isolate boundary, using the same real `libwhisper`
/// fixture [WhisperFfiEngine]'s own test uses.
///
/// Mirrors `whisper_ffi_engine_test.dart`'s fixture-detection: those
/// artifacts are gitignored and host-local (built via CMake, see Issue 01) —
/// on CI / other hosts this test SKIPS gracefully rather than failing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
    'WhisperIsolateEngine (real libwhisper, worker isolate)',
    () {
      test(
        'loads and transcribes the fixture WAV via the worker isolate',
        () async {
          final engine = WhisperIsolateEngine(libraryPath: dylibPath);
          expect(engine.status.isLoaded, isFalse);

          await engine.load(modelPath: modelPath!);
          addTearDown(engine.shutdown);
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

      test('throws when transcribing before load', () async {
        final engine = WhisperIsolateEngine(libraryPath: dylibPath);
        addTearDown(engine.shutdown);
        expect(
          () => engine.transcribe(const [0, 1, 2]),
          throwsA(isA<StateError>()),
        );
      });

      test('unload() resets isLoaded and a later load() works again', () async {
        final engine = WhisperIsolateEngine(libraryPath: dylibPath);
        addTearDown(engine.shutdown);

        await engine.load(modelPath: modelPath!);
        expect(engine.status.isLoaded, isTrue);

        await engine.unload();
        expect(engine.status.isLoaded, isFalse);

        await engine.load(modelPath: modelPath);
        expect(engine.status.isLoaded, isTrue);
      });

      test('unload() called while a transcribe is in flight does not wait for '
          'it to finish (regression: SIGTERM arriving during post-load '
          'warmup/benchmark inference pegged the app at ~100% CPU for up to '
          '10s before exiting, because unload() waited for a worker ack that '
          'could not arrive until that inference finished — the worker '
          'processes messages strictly one at a time, so a fixed unload() '
          'must return before the earlier-queued transcribe result is even '
          'delivered)', () async {
        final engine = WhisperIsolateEngine(libraryPath: dylibPath);
        addTearDown(engine.shutdown);

        await engine.load(modelPath: modelPath!);
        final wavBytes = File(speechWavPath!).readAsBytesSync();
        // Not awaited — mirrors _warmupInference/_runBenchmark firing a
        // transcribe() and SIGTERM landing on the worker mid-inference.
        var transcribeCompleted = false;
        final transcribeFuture = engine
            .transcribe(wavBytes, language: 'en')
            .whenComplete(() => transcribeCompleted = true);

        await engine.unload();

        // Ordering guarantee, not a timing race: the worker's message
        // queue delivers the transcribe's result before it can even look
        // at the (later-queued) unload request, so a still-waiting
        // unload() could never observe this as false — only a fixed
        // unload() that skips the wait can return this early.
        expect(transcribeCompleted, isFalse);
        expect(engine.status.isLoaded, isFalse);

        await transcribeFuture;
      }, timeout: const Timeout(Duration(minutes: 2)));

      test(
        'unload() left unawaited, then load() again, still reloads for real '
        '(regression: a model switch mid-session left the engine claiming '
        'readiness while the worker had actually freed its native context, '
        'so the next transcribe() threw whisper_engine_not_loaded)',
        () async {
          final engine = WhisperIsolateEngine(libraryPath: dylibPath);
          addTearDown(engine.shutdown);

          await engine.load(modelPath: modelPath!);
          expect(engine.status.isLoaded, isTrue);

          // Mirrors SttServerStateNotifier._debouncedPrewarmOnModelChange:
          // stop() (-> unload()) is fired without awaiting it, then a fresh
          // load() starts immediately — deliberately not awaiting unload()
          // here reproduces that exact interleaving.
          final unloadFuture = engine.unload();
          await engine.load(modelPath: modelPath);
          expect(engine.status.isLoaded, isTrue);

          final wavBytes = File(speechWavPath!).readAsBytesSync();
          final text = (await engine.transcribe(
            wavBytes,
            language: 'en',
          )).toLowerCase();
          expect(text, contains('hello'));
          expect(text, contains('world'));

          await unloadFuture;
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: available ? null : 'local libwhisper.dylib + tiny model absent',
  );

  // Host-independent error path (no dylib/model required): a missing model
  // surfaces via a thrown StateError, same contract as WhisperFfiEngine.
  test('surfaces a missing-model error without crashing the worker', () async {
    final engine = WhisperIsolateEngine(libraryPath: '/nonexistent/libwhisper');
    addTearDown(engine.shutdown);

    await expectLater(
      () => engine.load(modelPath: '/nonexistent/model.bin'),
      throwsA(isA<StateError>()),
    );
    expect(engine.status.isLoaded, isFalse);
  });

  test('status.backend reflects the configured backend without spawning', () {
    final engine = WhisperIsolateEngine(backend: WhisperBackend.metal);
    addTearDown(engine.shutdown);
    expect(engine.status.backend, WhisperBackend.metal);
    expect(engine.status.isLoaded, isFalse);
  });
}
