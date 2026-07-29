/// Offline WAV→text diagnosis harness against the real whisper.cpp FFI
/// engine — a manual tool, NOT part of the default `flutter test` sweep.
///
/// Built to investigate intermittent "transcription swallowed a sentence"
/// reports (see the local diagnosis plan). Runs a WAV file through the exact
/// same [WhisperFfiEngine] the app uses in-process — no Riverpod, no
/// history DB, no orchestrator pipeline — so the same captured audio
/// reproduces the same whisper.cpp output deterministically, independent of
/// the app's settings/prompt-continuity state.
///
/// A bare `dart run` script was tried first but crashes the CFE on this
/// Dart SDK (3.12.1) inside the FFI use-site transformer, independent of
/// this file's own code (confirmed by reproducing the same crash against
/// the unmodified, pre-existing `whisper_ffi_engine.dart` via `dart run`/
/// `dart compile exe`). `flutter test` uses a different compilation path
/// that does not hit it — this file mirrors that working path, same as
/// `whisper_ffi_engine_test.dart` next to it.
///
/// Point it at a WAV retained via `kRetainDebugAudio` (see
/// `lib/core/config/build_config.dart`) to replay a real drop, or leave the
/// defaults to smoke-test against `test/fixtures/hello_world.wav` with the
/// local durchstich test model. Run it twice with different `--dart-define`
/// `LANGUAGE`/`PROMPT` values to A/B the two leading transcription suspects
/// from the diagnosis plan (auto-detect language, the rolling
/// `initial_prompt`) without touching the full app.
///
/// Usage:
/// ```sh
/// flutter test test/services/stt/whisper/transcribe_debug_harness_test.dart \
///   --dart-define=WAV=/path/to/captured.wav \
///   --dart-define=MODEL=/path/to/ggml-large-v3-turbo.bin \
///   --dart-define=LIBRARY=/path/to/libwhisper.dylib \
///   --dart-define=LANGUAGE=de \
///   --dart-define=PROMPT="optional biasing text"
/// ```
/// `LIBRARY` defaults to the locally built durchstich `libwhisper.dylib`
/// used by `whisper_ffi_engine_test.dart` (see below); point it at a real
/// app bundle's embedded library, or leave unset to use the app's own
/// resolution ([defaultWhisperLibraryPath]) when running against an
/// installed build's model cache.
library;

// ignore_for_file: avoid_print — this is a manual diagnosis tool; stdout
// IS the deliverable, not something a future maintainer should silence.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

/// Walks up from the test cwd to the repo root (the dir holding
/// `.build/whisper-ffi-durchstich`) — same helper as
/// `whisper_ffi_engine_test.dart`, duplicated here to keep this harness
/// runnable standalone.
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

const _wavPath = String.fromEnvironment(
  'WAV',
  defaultValue: 'test/fixtures/hello_world.wav',
);
const _modelPathOverride = String.fromEnvironment('MODEL');
const _libraryPathOverride = String.fromEnvironment('LIBRARY');
const _language = String.fromEnvironment('LANGUAGE', defaultValue: 'en');
const _prompt = String.fromEnvironment('PROMPT');
const _vadModelPath = String.fromEnvironment('VAD_MODEL');

void main() {
  final root = _repoRoot();
  final durchstichModel = root == null
      ? null
      : p.join(
          root,
          '.build',
          'whisper-ffi-durchstich',
          'models',
          'ggml-tiny.bin',
        );
  final durchstichLibrary = root == null
      ? null
      : p.join(
          root,
          '.build',
          'whisper-ffi-durchstich',
          'src',
          'libwhisper.dylib',
        );

  final modelPath = _modelPathOverride.isNotEmpty
      ? _modelPathOverride
      : durchstichModel;
  final libraryPath = _libraryPathOverride.isNotEmpty
      ? _libraryPathOverride
      : durchstichLibrary;

  final wavFile = File(_wavPath);
  final available =
      modelPath != null &&
      libraryPath != null &&
      File(modelPath).existsSync() &&
      File(libraryPath).existsSync() &&
      wavFile.existsSync();

  test(
    'transcribe debug harness',
    () async {
      final wavBytes = wavFile.readAsBytesSync();
      // 16 kHz mono 16-bit PCM + 44-byte WAV header — same derivation the
      // app uses (see `stt_server_state_notifier.dart`'s `audioDurationMs`).
      final audioDurationMs = wavBytes.length > 44
          ? ((wavBytes.length - 44) / 32000 * 1000).round()
          : 0;

      final engine = WhisperFfiEngine(libraryPath: libraryPath);
      await engine.load(
        modelPath: modelPath!,
        vadModelPath: _vadModelPath.isEmpty ? null : _vadModelPath,
      );
      addTearDown(engine.unload);

      final sw = Stopwatch()..start();
      final text = await engine.transcribe(
        wavBytes,
        language: _language,
        prompt: _prompt.isEmpty ? null : _prompt,
        includeTimestamps: true,
        vadEnabled: _vadModelPath.isNotEmpty,
      );
      sw.stop();

      final charsPerSec = audioDurationMs > 0
          ? (text.length / (audioDurationMs / 1000)).toStringAsFixed(1)
          : 'n/a';

      print('');
      print('=== transcribe debug harness ===');
      print(
        'wav: $_wavPath (${wavBytes.length} bytes, ~${audioDurationMs}ms audio)',
      );
      print(
        'language: $_language  prompt: '
        '${_prompt.isEmpty ? "(none)" : '"$_prompt"'}',
      );
      print(
        'inference: ${sw.elapsedMilliseconds}ms  textLen=${text.length}  '
        'charsPerSec=$charsPerSec',
      );
      print('--- segments (${engine.lastSegments.length}) ---');
      for (final segment in engine.lastSegments) {
        print(segment);
      }
      print('--- full transcript ---');
      print(text);

      // Smoke assertion so a missing/garbled transcript fails loudly rather
      // than silently printing an empty result.
      expect(text.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: available
        ? null
        : 'set --dart-define=MODEL=<path> (and WAV/LIBRARY as needed) — '
              'see this file\'s doc comment',
  );
}
