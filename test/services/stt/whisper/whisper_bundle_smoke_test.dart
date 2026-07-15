/// AC2 smoke test for Issue 11 (cross-platform bundling + signing).
///
/// Proves that a PACKAGED macOS build actually loads the `libwhisper` embedded
/// into `WhisPaste.app/Contents/Frameworks/` (via the "[WP] Embed & Sign
/// libwhisper" Xcode phase + scripts/build-libwhisper-macos.sh) and transcribes
/// the fixture — i.e. the bundled dylib resolves its co-located `ggml*` backends
/// through the `@loader_path` rpath, not the durchstich's absolute build path.
///
/// Runs only when a built `.app` exists (after `flutter build macos`) and the
/// gitignored tiny model + speech fixture from the Issue-01 durchstich are
/// present; otherwise it SKIPS (CI / fresh checkouts have neither). Real
/// Windows/Linux verification is Issues 13/14.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

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

String? _bundledDylib(String root) {
  for (final config in const ['Release', 'Debug']) {
    final path = p.join(
      root,
      'build',
      'macos',
      'Build',
      'Products',
      config,
      'WhisPaste.app',
      'Contents',
      'Frameworks',
      'libwhisper.dylib',
    );
    if (File(path).existsSync()) return path;
  }
  return null;
}

void main() {
  final root = _repoRoot();
  final dylibPath = root == null ? null : _bundledDylib(root);
  final durchstich = root == null
      ? null
      : p.join(root, '.build', 'whisper-ffi-durchstich');
  final modelPath = durchstich == null
      ? null
      : p.join(durchstich, 'models', 'ggml-tiny.bin');
  final speechWavPath = durchstich == null
      ? null
      : p.join(durchstich, 'fixtures', 'hello_world_speech.wav');

  final available =
      Platform.isMacOS &&
      dylibPath != null &&
      File(modelPath!).existsSync() &&
      File(speechWavPath!).existsSync();

  test(
    'packaged .app loads embedded libwhisper and transcribes',
    () async {
      final engine = WhisperFfiEngine(libraryPath: dylibPath);
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
    skip: available
        ? null
        : 'no built WhisPaste.app or durchstich model/fixture (run flutter build macos)',
  );
}
