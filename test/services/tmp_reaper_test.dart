/// Unit tests for [reapReadyEntries] and [sweepOrphanedTmpFiles].
///
/// All four acceptance-criteria cases (AC2a–d) are covered as table tests
/// against the pure [reapReadyEntries] function. No disk I/O is required for
/// those tests. Additional integration-style tests exercise
/// [sweepOrphanedTmpFiles] against a real temp directory.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/tmp_reaper.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // Pure function — reapReadyEntries (AC1 + AC2)
  // ──────────────────────────────────────────────────────────────────────────

  group('reapReadyEntries — pure decision function', () {
    const threshold = Duration(hours: 1);

    // Convenience builders.
    TmpDirEntry old(String name) =>
        TmpDirEntry(name: name, age: threshold + const Duration(seconds: 1));
    TmpDirEntry fresh(String name) =>
        TmpDirEntry(name: name, age: threshold - const Duration(seconds: 1));
    TmpDirEntry exactly(String name) => TmpDirEntry(name: name, age: threshold);

    // ── AC2a: orphan over threshold age → reap-ready ──────────────────────

    test(
      'AC2a: .tmp without active download, age > threshold → reap-ready',
      () {
        final entries = [old('ggml-small-q5_1.bin.tmp')];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {},
          ageThreshold: threshold,
        );
        expect(result, hasLength(1));
        expect(result.first.name, 'ggml-small-q5_1.bin.tmp');
      },
    );

    test(
      'AC2a: multiple orphaned .tmp files, all over threshold → all reap-ready',
      () {
        final entries = [
          old('ggml-small-q5_1.bin.tmp'),
          old('ggml-medium-q5_0.bin.tmp'),
          old('_whisper-server.zip.tmp'),
        ];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {},
          ageThreshold: threshold,
        );
        expect(result, hasLength(3));
      },
    );

    // ── AC2b: active download (running/paused) → NOT reap-ready ──────────

    test('AC2b: .tmp with matching active download path → NOT reap-ready', () {
      const name = 'ggml-small-q5_1.bin.tmp';
      final entries = [old(name)];
      final result = reapReadyEntries(
        entries: entries,
        activeDownloadPaths: {name},
        ageThreshold: threshold,
      );
      expect(result, isEmpty);
    });

    test(
      'AC2b: active downloads protect their own file, others are still reaped',
      () {
        const activeName = 'ggml-small-q5_1.bin.tmp';
        const orphanName = 'ggml-medium-q5_0.bin.tmp';
        final entries = [old(activeName), old(orphanName)];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {activeName},
          ageThreshold: threshold,
        );
        expect(result, hasLength(1));
        expect(result.first.name, orphanName);
      },
    );

    // ── AC2c: fresh under threshold → NOT reap-ready ─────────────────────

    test(
      'AC2c: .tmp without active download, age < threshold → NOT reap-ready',
      () {
        final entries = [fresh('ggml-small-q5_1.bin.tmp')];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {},
          ageThreshold: threshold,
        );
        expect(result, isEmpty);
      },
    );

    test(
      'AC2c: .tmp exactly at threshold (not strictly greater) → NOT reap-ready',
      () {
        final entries = [exactly('ggml-small-q5_1.bin.tmp')];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {},
          ageThreshold: threshold,
        );
        // age == threshold is NOT strictly greater than threshold → skip.
        expect(result, isEmpty);
      },
    );

    // ── AC2d: non-.tmp files → NEVER reap-ready ───────────────────────────

    test('AC2d: .bin file (no .tmp suffix) → NOT reap-ready', () {
      final entries = [old('ggml-small-q5_1.bin')];
      final result = reapReadyEntries(
        entries: entries,
        activeDownloadPaths: {},
        ageThreshold: threshold,
      );
      expect(result, isEmpty);
    });

    test(
      'AC2d: whisper-server binary without .tmp suffix → NOT reap-ready',
      () {
        final entries = [old('whisper-server')];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {},
          ageThreshold: threshold,
        );
        expect(result, isEmpty);
      },
    );

    test(
      'AC2d: mix of .tmp and non-.tmp → only .tmp over threshold reaped',
      () {
        final entries = [
          old('ggml-small-q5_1.bin.tmp'), // should be reaped
          old('ggml-small-q5_1.bin'), // should NOT be reaped
          old('whisper-server'), // should NOT be reaped
          old('some-log.txt'), // should NOT be reaped
        ];
        final result = reapReadyEntries(
          entries: entries,
          activeDownloadPaths: {},
          ageThreshold: threshold,
        );
        expect(result, hasLength(1));
        expect(result.first.name, 'ggml-small-q5_1.bin.tmp');
      },
    );

    // ── Zero-Duration threshold edge case ─────────────────────────────────

    test('zero-duration threshold: any .tmp with age > 0 is reap-ready', () {
      final entries = [
        const TmpDirEntry(
          name: 'ggml-small.bin.tmp',
          age: Duration(seconds: 1),
        ),
      ];
      final result = reapReadyEntries(
        entries: entries,
        activeDownloadPaths: {},
        ageThreshold: Duration.zero,
      );
      expect(result, hasLength(1));
    });

    test('empty entry list → empty result', () {
      final result = reapReadyEntries(
        entries: [],
        activeDownloadPaths: {'some.tmp'},
        ageThreshold: threshold,
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // I/O wrapper — sweepOrphanedTmpFiles
  // ──────────────────────────────────────────────────────────────────────────

  group('sweepOrphanedTmpFiles — I/O wrapper', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wp_reaper_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes aged orphan .tmp files from directory', () async {
      final tmpFile = File(p.join(tempDir.path, 'ggml-small-q5_1.bin.tmp'));
      await tmpFile.writeAsBytes([1, 2, 3]);

      // Back-date the file so it appears old.
      final past = DateTime.now().subtract(const Duration(hours: 2));
      await tmpFile.setLastModified(past);

      await sweepOrphanedTmpFiles(
        directory: tempDir.path,
        ageThreshold: const Duration(hours: 1),
      );

      expect(tmpFile.existsSync(), isFalse);
    });

    test('does NOT delete fresh .tmp files under threshold', () async {
      final tmpFile = File(p.join(tempDir.path, 'ggml-small-q5_1.bin.tmp'));
      await tmpFile.writeAsBytes([1, 2, 3]);
      // Leave mtime = now (fresh).

      await sweepOrphanedTmpFiles(
        directory: tempDir.path,
        ageThreshold: const Duration(hours: 1),
      );

      expect(tmpFile.existsSync(), isTrue);
    });

    test('does NOT delete .tmp files in activeDownloadPaths', () async {
      final tmpFile = File(p.join(tempDir.path, 'ggml-small-q5_1.bin.tmp'));
      await tmpFile.writeAsBytes([1, 2, 3]);
      final past = DateTime.now().subtract(const Duration(hours: 2));
      await tmpFile.setLastModified(past);

      await sweepOrphanedTmpFiles(
        directory: tempDir.path,
        activeDownloadPaths: {tmpFile.path}, // protected by absolute path
        ageThreshold: const Duration(hours: 1),
      );

      expect(tmpFile.existsSync(), isTrue);
    });

    test('does NOT delete non-.tmp files', () async {
      final binFile = File(p.join(tempDir.path, 'ggml-small-q5_1.bin'));
      await binFile.writeAsBytes([1, 2, 3]);
      final past = DateTime.now().subtract(const Duration(hours: 2));
      await binFile.setLastModified(past);

      await sweepOrphanedTmpFiles(
        directory: tempDir.path,
        ageThreshold: const Duration(hours: 1),
      );

      expect(binFile.existsSync(), isTrue);
    });

    test('is a no-op when directory does not exist', () async {
      final nonexistent = p.join(tempDir.path, 'does_not_exist');
      // Must not throw.
      await expectLater(
        sweepOrphanedTmpFiles(directory: nonexistent),
        completes,
      );
    });

    test(
      'sweeps only aged files when both aged and fresh .tmp exist',
      () async {
        final agedFile = File(p.join(tempDir.path, 'ggml-medium.bin.tmp'));
        final freshFile = File(p.join(tempDir.path, 'ggml-small.bin.tmp'));
        await agedFile.writeAsBytes([0xAA]);
        await freshFile.writeAsBytes([0xBB]);

        final past = DateTime.now().subtract(const Duration(hours: 2));
        await agedFile.setLastModified(past);
        // freshFile mtime = now (not back-dated).

        await sweepOrphanedTmpFiles(
          directory: tempDir.path,
          ageThreshold: const Duration(hours: 1),
        );

        expect(
          agedFile.existsSync(),
          isFalse,
          reason: 'aged file must be reaped',
        );
        expect(
          freshFile.existsSync(),
          isTrue,
          reason: 'fresh file must survive',
        );
      },
    );
  });
}
