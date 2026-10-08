/// Host-local test for ticket 30: stopping the live preview must abort an
/// in-flight preview decode, so the final transcription queued behind it on
/// the worker isolate does not wait for a whole preview window to finish.
///
/// Uses the real `libwhisper` + `wp_ffi_guard` staged by
/// `scripts/build-libwhisper-macos.sh` (`-linux.sh`, or the Windows steps in
/// BUILD.md) and `.build/test-models/whisper/ggml-tiny.bin` — the same
/// host-local fixtures as `native_call_guard_test.dart`, so it SKIPS where
/// they are missing (CI, fresh checkouts).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/native_call_guard.dart';
import 'package:whispaste/services/stt/whisper/whisper_isolate_engine.dart';

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

/// PCM payload of a RIFF/WAVE file (the clips carry a LIST chunk, so the
/// data does not start at byte 44).
ByteData _dataChunk(Uint8List wav) {
  final bytes = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav, offset, offset + 4);
    final size = bytes.getUint32(offset + 4, Endian.little);
    if (id == 'data') return ByteData.sublistView(wav, offset + 8);
    offset += 8 + size + (size & 1);
  }
  throw StateError('no data chunk');
}

void main() {
  final root = _repoRoot();
  final whisperPath = root == null
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
          Platform.isLinux
              ? 'libwhisper.so'
              : Platform.isWindows
              ? 'whisper.dll'
              : 'libwhisper.dylib',
        );
  final modelPath = root == null
      ? null
      : p.join(root, '.build', 'test-models', 'whisper', 'ggml-tiny.bin');
  final available =
      whisperPath != null &&
      File(NativeCallGuard.pathNextTo(whisperPath)).existsSync() &&
      File(modelPath!).existsSync();

  test(
    'stopLivePreview aborts a running preview decode instead of waiting',
    () async {
      final engine = WhisperIsolateEngine(libraryPath: whisperPath);
      addTearDown(engine.shutdown);
      await engine.load(modelPath: modelPath!);

      // 25 s of real speech (consecutive LibriSpeech clips) — the longest
      // window the previewer sends.
      final window = Float32List(16000 * 25);
      var filled = 0;
      for (var clip = 0; filled < window.length; clip++) {
        final wav = File(
          p.join(
            root!,
            'website',
            'scripts',
            'librispeech-sample',
            '2277-149896-${clip.toString().padLeft(4, '0')}.wav',
          ),
        ).readAsBytesSync();
        final data = _dataChunk(wav);
        for (var i = 0; i + 1 < data.lengthInBytes; i += 2) {
          if (filled == window.length) break;
          window[filled++] = data.getInt16(i, Endian.little) / 32768;
        }
      }

      await engine.startLivePreview();
      // Warm-up, then one uninterrupted decode as the reference duration.
      await engine.decodeLivePreview(window, language: 'en');
      final full = Stopwatch()..start();
      await engine.decodeLivePreview(window, language: 'en');
      final fullMs = full.elapsedMilliseconds;

      // whisper.cpp polls the abort callback only after the encoder and
      // between decoder steps, so stop once the decoder is under way (the
      // encoder takes well under half of a speech window's decode).
      final inFlight = engine.decodeLivePreview(window, language: 'en');
      await Future<void>.delayed(Duration(milliseconds: fullMs * 6 ~/ 10));
      final stop = Stopwatch()..start();
      await engine.stopLivePreview();
      final stopMs = stop.elapsedMilliseconds;
      final aborted = await inFlight;

      // Visible in `flutter test --reporter expanded` for the ticket notes.
      // ignore: avoid_print
      print('preview decode ${fullMs}ms, stop during decode ${stopMs}ms');
      expect(aborted, isEmpty);
      expect(stopMs, lessThan(fullMs ~/ 4));

      // The next recording's preview works again (flag was reset).
      await engine.startLivePreview();
      await engine.decodeLivePreview(window, language: 'en');
      await engine.stopLivePreview();
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: available
        ? false
        : 'needs wp_ffi_guard + .build/test-models/whisper/ggml-tiny.bin',
  );
}
