/// Engine-level test for the real [WhisperFfiEngine] over the seam.
///
/// Loads the locally built `libwhisper.dylib` and the tiny GGML model produced
/// by the Issue-01 durchstich setup, then transcribes a real-speech fixture.
/// Those artifacts are gitignored and host-local (built via CMake, see Issue
/// 01) — on CI / other hosts they are absent, so the test SKIPS gracefully
/// rather than failing. Real cross-platform bundling is Issue 11.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
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

      // Wires the real, committed VAD model (assets/models/vad/, see
      // NOTICE.md — unlike the gitignored durchstich dylib/model, this file
      // ships in every checkout) through the actual [WhisperFfiEngine]
      // production code path. Regression coverage for the "Vielen Dank"
      // trailing-hallucination investigation: proves `vadEnabled` doesn't
      // crash or corrupt real speech end-to-end, not just via the manual
      // debug harness. Deeper behavioural validation (silence/noise tails
      // dropped, genuine trailing content preserved) was done empirically
      // against the production large-v3-turbo model — see the commit
      // history for `vad_debug_harness_test.dart` and this file's VAD
      // wiring in `whisper_ffi_engine.dart`; the tiny durchstich model here
      // is only asserted for mechanical correctness, not hallucination
      // behaviour (too small/undertrained to reproduce that reliably).
      test(
        'transcribes correctly with VAD enabled',
        () async {
          final vadModelPath = p.join(
            _repoRoot() ?? Directory.current.path,
            'assets',
            'models',
            'vad',
            'ggml-silero-v5.1.2.bin',
          );
          if (!File(vadModelPath).existsSync()) {
            markTestSkipped('VAD model asset not found at $vadModelPath');
            return;
          }

          final engine = WhisperFfiEngine(libraryPath: dylibPath);
          await engine.load(modelPath: modelPath!, vadModelPath: vadModelPath);
          addTearDown(engine.unload);

          final wavBytes = File(speechWavPath!).readAsBytesSync();
          final text = (await engine.transcribe(
            wavBytes,
            language: 'en',
            vadEnabled: true,
          )).toLowerCase();

          expect(text, contains('hello'));
          expect(text, contains('world'));
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: available ? null : 'local libwhisper.dylib + tiny model absent',
  );

  // Bundled-library path resolution (Issue 11). Host-independent for the
  // active platform (macOS on this runner): asserts the resolver points at the
  // embedded `libwhisper` next to the executable, not a bare loader-search name.
  group('whisperLibraryPathFor', () {
    test('resolves the bundled library relative to the executable', () {
      final resolved = whisperLibraryPathFor(
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
            'libwhisper.dylib',
          ),
        );
      } else if (Platform.isWindows) {
        expect(resolved, endsWith('whisper.dll'));
      } else {
        expect(resolved, endsWith(p.join('lib', 'libwhisper.so')));
      }
    });

    test('defaultWhisperLibraryPath is absolute', () {
      expect(p.isAbsolute(defaultWhisperLibraryPath()), isTrue);
    });
  });

  // Bundled VAD-model path resolution (2026-07-29 "Vielen Dank" follow-up):
  // asserts the resolver points at the model co-located with `libwhisper`
  // itself, not some separate/downloaded location.
  group('whisperVadModelPathFor', () {
    test('resolves next to the bundled library', () {
      final exe = p.join(
        '/Apps',
        'WhisPaste.app',
        'Contents',
        'MacOS',
        'whispaste',
      );
      final resolved = whisperVadModelPathFor(exe);
      expect(p.isAbsolute(resolved), isTrue);
      expect(
        p.dirname(resolved),
        p.dirname(whisperLibraryPathFor(exe)),
        reason: 'VAD model must live in the same dir as libwhisper',
      );
      expect(p.basename(resolved), 'ggml-silero-v5.1.2.bin');
    });

    test('defaultWhisperVadModelPath is absolute', () {
      expect(p.isAbsolute(defaultWhisperVadModelPath()), isTrue);
    });
  });

  // Confirms `_confirmBackend`'s ggml device-registry probe against a real
  // bundled dylib (2026-08-12, GPU→CPU silent-fallback investigation):
  // `WhisperEngineStatus.backend` used to echo back whichever backend was
  // requested at construction, even when ggml silently fell back to CPU
  // inside `whisper_init_from_file_with_params` without throwing. Uses the
  // app's own already-built Debug dylib (gitignored, host-local) instead of
  // a full model load — SKIPS gracefully if it hasn't been built.
  group('confirmBackendForTesting — real device registry', () {
    String? debugDylibPath() {
      var dir = Directory.current;
      for (var i = 0; i < 8; i++) {
        final candidate = p.join(
          dir.path,
          'build',
          'macos',
          'Build',
          'Products',
          'Debug',
          'WhisPaste.app',
          'Contents',
          'Frameworks',
          'libwhisper.dylib',
        );
        if (File(candidate).existsSync()) return candidate;
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      return null;
    }

    test('a GPU-capable Mac confirms the requested Metal backend', () {
      if (!Platform.isMacOS) {
        markTestSkipped('macOS-only (Metal)');
        return;
      }
      final path = debugDylibPath();
      if (path == null) {
        markTestSkipped('local Debug app build not found — run a Debug build');
        return;
      }
      final dylib = ffi.DynamicLibrary.open(path);
      expect(
        confirmBackendForTesting(dylib, path, WhisperBackend.metal),
        WhisperBackend.metal,
      );
    });

    test('CPU is never downgraded (no registry probe needed)', () {
      final path = debugDylibPath();
      if (path == null) {
        markTestSkipped('local Debug app build not found — run a Debug build');
        return;
      }
      final dylib = ffi.DynamicLibrary.open(path);
      expect(
        confirmBackendForTesting(dylib, path, WhisperBackend.cpu),
        WhisperBackend.cpu,
      );
    });
  });

  // Guards against the vendored VAD model asset silently disappearing —
  // always runs (no gitignored artifacts needed), since it's a committed
  // repo file (see assets/models/vad/NOTICE.md).
  test('vendored VAD model asset exists in the repo', () {
    final repoRoot = _repoRoot();
    // Falls back to walking up from cwd for a `assets/` dir when the
    // durchstich marker (used by `_repoRoot()` above) isn't present, e.g. on
    // CI checkouts that never ran the local FFI durchstich setup.
    var dir = repoRoot != null ? Directory(repoRoot) : Directory.current;
    if (repoRoot == null) {
      for (var i = 0; i < 8; i++) {
        if (Directory(
          p.join(dir.path, 'assets', 'models', 'vad'),
        ).existsSync()) {
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    final assetPath = p.join(
      dir.path,
      'assets',
      'models',
      'vad',
      'ggml-silero-v5.1.2.bin',
    );
    expect(
      File(assetPath).existsSync(),
      isTrue,
      reason: 'missing $assetPath — see assets/models/vad/NOTICE.md',
    );
  });

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
