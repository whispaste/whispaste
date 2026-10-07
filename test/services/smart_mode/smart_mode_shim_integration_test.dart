/// Host-local integration test for [SmartModeFfiEngine] against the REAL
/// `libsmartmode_shim` (session API: load / generate / unload / abort flag).
///
/// Needs artifacts that are gitignored and host-local, so it SKIPS
/// gracefully wherever they're missing (CI, fresh checkouts) — same pattern
/// as `whisper_isolate_engine_test.dart`:
/// - `.build/libllama/macos/libsmartmode_shim.dylib`
///   (`scripts/build-libllama-macos.sh && scripts/build-smartmode-shim-macos.sh`)
/// - any small GGUF chat model at `.build/test-models/smart_mode/test.gguf`
///   (a tiny one is enough — this proves the native session lifecycle, not
///   output quality; the production Gemma model works the same way).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart';

String? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'native', 'smart_mode')).existsSync()) {
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
  final libPath = root == null
      ? null
      : p.join(root, '.build', 'libllama', 'macos', 'libsmartmode_shim.dylib');
  final modelPath = root == null
      ? null
      : p.join(root, '.build', 'test-models', 'smart_mode', 'test.gguf');
  final available =
      Platform.isMacOS &&
      libPath != null &&
      File(libPath).existsSync() &&
      File(modelPath!).existsSync();

  group(
    'SmartModeFfiEngine (real libsmartmode_shim)',
    () {
      test(
        'loads once, reuses the resident model, aborts, unloads',
        () async {
          final engine = SmartModeFfiEngine(
            libraryPath: libPath,
            modelPath: modelPath,
            detectRamMB: () async => 32768,
          );
          addTearDown(engine.shutdown);

          // Main-isolate responsiveness during the blocking native load +
          // decode (UI-smoothness proxy), measured with a 10 ms ticker.
          var maxGap = Duration.zero;
          var last = DateTime.now();
          final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
            final now = DateTime.now();
            final gap = now.difference(last);
            if (gap > maxGap) maxGap = gap;
            last = now;
          });

          final cold = Stopwatch()..start();
          final first = await engine.run(
            systemPrompt: 'Repeat the text.',
            userText: 'Once upon a time',
          );
          cold.stop();
          final warm = Stopwatch()..start();
          await engine.run(
            systemPrompt: 'Repeat the text.',
            userText: 'There was a cat',
          );
          warm.stop();
          ticker.cancel();

          // Printed on purpose: these are the ticket's latency measurements.
          // ignore: avoid_print
          print(
            'smart_mode shim: 1st call ${cold.elapsedMilliseconds} ms '
            '(load ${engine.modelLoadCount == 1 ? 'once' : '?'}), '
            '2nd call ${warm.elapsedMilliseconds} ms '
            '(loadedModel=${engine.lastRunStats!.loadedModel}, '
            'generate ${engine.lastRunStats!.generateTime.inMilliseconds} ms), '
            'max main-isolate stall ${maxGap.inMilliseconds} ms',
          );
          expect(first, isA<String>());
          expect(engine.modelLoadCount, 1);
          expect(engine.lastRunStats!.loadedModel, isFalse);
          expect(engine.isModelResident, isTrue);
          // maxGap is reported, not asserted: with the real decoder on the
          // CPU (no Metal in flutter_tester) it saturates every core, so the
          // wall-clock stall depends on host load. The deterministic
          // off-isolate check lives in smart_mode_engine_lifecycle_test.dart.

          // Abort: cancel right away — the shim's per-token check must stop
          // the decode loop and return NULL (→ SmartModeAbortedException).
          final pending = engine.run(
            systemPrompt: 'Write a very long story.',
            userText: 'Tell a long story about a dragon',
          );
          await engine.cancel();
          await expectLater(pending, throwsA(isA<SmartModeAbortedException>()));
          expect(engine.isModelResident, isTrue);

          await engine.unload();
          expect(engine.isModelResident, isFalse);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: available
        ? null
        : 'libsmartmode_shim / test GGUF not staged on this host',
  );
}
