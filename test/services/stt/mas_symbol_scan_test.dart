import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level symbol scan proving the onDevice STT path is sandbox-clean.
///
/// A true compiled-binary symbol scan (what Apple's App Review actually
/// runs — Guideline 2.5.2) isn't feasible inside a Dart test suite. This is
/// an honest proxy: it greps the exact Dart source files that make up the
/// onDevice STT call path (subprocess/server-manifest code was removed by
/// `.scratch/whisper-ffi-engine/issues/07` and `08`; onDevice transcription
/// now runs exclusively through the FFI binding in
/// `lib/services/stt/whisper/whisper_ffi_engine.dart`) for symbols that
/// would reintroduce a subprocess or filesystem-quarantine dependency:
/// `Process.start`, `Process.run`, `xattr`, `tccutil`.
///
/// If this test ever fails, it means someone reintroduced one of those
/// symbols into the onDevice path — exactly the kind of regression Apple's
/// binary scan would reject a MAS submission for.
void main() {
  test('onDevice STT path contains no Process.start/Process.run/xattr/tccutil '
      'symbols', () {
    // Mirrors the scope Issue 08 already verified clean (its own AC2 grep
    // scope) plus lib/services/transcription — the provider-dispatch layer
    // that routes to the onDevice engine.
    const scanRoots = <String>[
      'lib/services/stt',
      'lib/services/transcription',
      'lib/services/recording',
      'lib/services/recording_orchestrator.dart',
      'lib/main.dart',
    ];

    final forbiddenPatterns = <String, RegExp>{
      'Process.start(': RegExp(r'Process\.start\('),
      'Process.run(': RegExp(r'Process\.run\('),
      'xattr': RegExp(r'\bxattr\b'),
      'tccutil': RegExp(r'\btccutil\b'),
    };

    final violations = <String>[];

    for (final rootPath in scanRoots) {
      final entity = FileSystemEntity.isDirectorySync(rootPath)
          ? Directory(rootPath)
          : File(rootPath);

      final files = <File>[];
      if (entity is Directory) {
        expect(entity.existsSync(), isTrue, reason: '$rootPath must exist');
        for (final e in entity.listSync(recursive: true)) {
          if (e is File && e.path.endsWith('.dart')) files.add(e);
        }
      } else if (entity is File) {
        expect(entity.existsSync(), isTrue, reason: '$rootPath must exist');
        files.add(entity);
      }

      for (final file in files) {
        final content = file.readAsStringSync();
        for (final MapEntry(key: label, value: pattern)
            in forbiddenPatterns.entries) {
          for (final match in pattern.allMatches(content)) {
            final lineNum = content
                .substring(0, match.start)
                .split('\n')
                .length;
            violations.add(
              '  ${file.path}:$lineNum — forbidden symbol "$label"',
            );
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'onDevice STT path contains sandbox-unclean symbols:\n'
          '${violations.join('\n')}',
    );
  });
}
